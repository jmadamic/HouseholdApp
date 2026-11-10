#!/usr/bin/env python3
"""Checks the DEPLOYED Firestore rules for households and invites.

Run from the repo root after `firebase deploy --only firestore:rules`:

    python3 scripts/test-firestore-rules.py

Self-contained: it signs up two throwaway guest accounts, creates its own
household, attacks it, then deletes the household and both accounts. It never
reads or writes any other household. Exits non-zero if any check is wrong.

There is no local emulator run because that needs Java; this talks to the
real project with the app's own client key, exactly as the app does.
"""
import json
import plistlib
import secrets
import sys
import urllib.error
import urllib.request

cfg = plistlib.load(open("HouseholdApp/GoogleService-Info.plist", "rb"))
KEY, PROJECT = cfg["API_KEY"], cfg["PROJECT_ID"]
HEADERS = {"Content-Type": "application/json", "X-Ios-Bundle-Identifier": cfg["BUNDLE_ID"]}
ROOT = f"projects/{PROJECT}/databases/(default)/documents"
BASE = f"https://firestore.googleapis.com/v1/{ROOT}"
AUTH = "https://identitytoolkit.googleapis.com/v1/accounts"
ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


def call(url, body=None, token=None, method=None):
    headers = dict(HEADERS)
    if token:
        headers["Authorization"] = "Bearer " + token
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as err:
        return err.code, None


def sign_up():
    status, user = call(f"{AUTH}:signUp?key={KEY}", {"returnSecureToken": True})
    assert status == 200, "guest sign-up failed"
    return user["idToken"], user["localId"]


def new_code():
    return "".join(secrets.choice(ALPHABET) for _ in range(8))


def s(value):
    return {"stringValue": value}


def commit(token, writes):
    return call(f"{BASE}:commit", {"writes": writes}, token)[0]


results = []


def expect(name, got, want):
    results.append((name, got, got == want))


owner_token, owner = sign_up()
joiner_token, joiner = sign_up()
hid = "rulestest-" + secrets.token_hex(8)
code = new_code()
household = f"{ROOT}/households/{hid}"


def invite(c):
    return f"{ROOT}/invites/{c}"


def update(fields, mask, transforms=None):
    write = {"update": {"name": household, "fields": fields},
             "updateMask": {"fieldPaths": mask}, "currentDocument": {"exists": True}}
    if transforms:
        write["updateTransforms"] = transforms
    return write


def add_member(uid):
    return [{"fieldPath": "memberIds", "appendMissingElements": {"values": [s(uid)]}}]


def remove_member(uid):
    return [{"fieldPath": "memberIds", "removeAllFromArray": {"values": [s(uid)]}}]


def join_code(uid, value):
    return {"joinCodes": {"mapValue": {"fields": {uid: s(value)}}}}


def join(token, uid, value, extra=None, mask_extra=()):
    fields = join_code(uid, value)
    fields.update(extra or {})
    return commit(token, [update(fields, [f"joinCodes.`{uid}`", *mask_extra], add_member(uid))])


try:
    # ── Create (as the app does: household + invite in one batch) ──────────
    expect("owner creates household + invite", commit(owner_token, [
        {"update": {"name": household, "fields": {
            "inviteCode": s(code), "ownerId": s(owner), "name": s("Rules test"),
            "memberIds": {"arrayValue": {"values": [s(owner)]}},
            "createdAt": {"timestampValue": "2026-01-01T00:00:00Z"}}},
         "currentDocument": {"exists": False}},
        {"update": {"name": invite(code), "fields": {"householdId": s(hid)}},
         "currentDocument": {"exists": False}},
    ]), 200)

    # ── A stranger who knows the code's household ID but not how to join ───
    expect("stranger reads household", call(f"{BASE}/households/{hid}", token=joiner_token)[0], 403)
    expect("stranger lists invites", call(f"{BASE}/invites", token=joiner_token)[0], 403)
    expect("stranger reads a chore", call(f"{BASE}/households/{hid}/chores/x", token=joiner_token)[0], 403)
    expect("join with no code", commit(joiner_token, [
        {"transform": {"document": household, "fieldTransforms": add_member(joiner)}}]), 403)
    expect("join with wrong code", join(joiner_token, joiner, "WRONGCODE"), 403)
    expect("join presenting the code under someone else's key", commit(joiner_token, [
        update(join_code(owner, code), [f"joinCodes.`{owner}`"], add_member(joiner))]), 403)
    expect("join with right code + rename household",
           join(joiner_token, joiner, code, {"name": s("Hijacked")}, ["name"]), 403)
    expect("join with right code + take ownership",
           join(joiner_token, joiner, code, {"ownerId": s(joiner)}, ["ownerId"]), 403)
    expect("join with right code, replacing the members", commit(joiner_token, [
        update({**join_code(joiner, code), "memberIds": {"arrayValue": {"values": [s(joiner)]}}},
               [f"joinCodes.`{joiner}`", "memberIds"])]), 403)
    expect("stranger mints an invite for the household", commit(joiner_token, [
        {"update": {"name": invite(new_code()), "fields": {"householdId": s(hid)}}}]), 403)

    # ── The real join, then what a member may and may not do ───────────────
    expect("join with right code", join(joiner_token, joiner, code), 200)
    expect("member reads household", call(f"{BASE}/households/{hid}", token=joiner_token)[0], 200)
    expect("member renames household", commit(joiner_token, [update({"name": s("Ours")}, ["name"])]), 200)
    expect("member takes ownership", commit(joiner_token, [update({"ownerId": s(joiner)}, ["ownerId"])]), 403)
    expect("member adds another account", commit(joiner_token, [update({}, [], add_member("intruder"))]), 403)
    expect("member removes someone else", commit(joiner_token, [update({}, [], remove_member(owner))]), 403)
    expect("member mints a second invite", commit(joiner_token, [
        {"update": {"name": invite(new_code()), "fields": {"householdId": s(hid)}}}]), 403)

    # ── Leave, change the code, and the old code must stop working ─────────
    expect("member leaves", commit(joiner_token, [update({}, [], remove_member(joiner))]), 200)
    old_code, code = code, new_code()
    expect("owner changes the invite code", commit(owner_token, [
        update({"inviteCode": s(code)}, ["inviteCode"]),
        {"delete": invite(old_code)},
        {"update": {"name": invite(code), "fields": {"householdId": s(hid)}},
         "currentDocument": {"exists": False}},
    ]), 200)
    expect("ex-member rejoins with no code", commit(joiner_token, [
        {"transform": {"document": household, "fieldTransforms": add_member(joiner)}}]), 403)
    expect("ex-member rejoins with the old code", join(joiner_token, joiner, old_code), 403)
    expect("rejoin with the new code", join(joiner_token, joiner, code), 200)
    expect("member leaves again", commit(joiner_token, [update({}, [], remove_member(joiner))]), 200)
finally:
    # ── Clean up everything this run created ───────────────────────────────
    expect("cleanup: owner deletes invite + household", commit(owner_token, [
        {"delete": invite(code)}, {"delete": household}]), 200)
    expect("cleanup: household is gone",
           call(f"{BASE}/households/{hid}", token=owner_token)[0] in (403, 404), True)
    for label, token in (("owner", owner_token), ("joiner", joiner_token)):
        expect(f"cleanup: delete {label} test account",
               call(f"{AUTH}:delete?key={KEY}", {"idToken": token})[0], 200)

failed = [r for r in results if not r[2]]
for name, got, ok in results:
    print(f"{'ok' if ok else 'WRONG':6} {got!s:5} {name}")
print(f"\n{len(results) - len(failed)}/{len(results)} checks as expected")
sys.exit(1 if failed else 0)
