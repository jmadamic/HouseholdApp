// VoiceCaptureView.swift
// Hold-free voice entry: tap to record, tap to stop, see what was
// understood, then confirm in the normal form.
//
// Nothing is saved directly from here — the parsed result prefills the
// chore or shopping form so a misparse is a visible edit, never bad data
// created behind your back.

import SwiftUI

struct VoiceCaptureView: View {

    @Environment(\.dismiss)           private var dismiss
    @EnvironmentObject private var appSettings: AppSettings

    @StateObject private var speech = SpeechCapture()
    @State private var intent: VoiceIntent? = nil
    @State private var choreDraft: ChoreDoc? = nil
    @State private var shoppingDraft: ShoppingItemDoc? = nil

    private let parser = RuleBasedVoiceIntentParser()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // ── Mic ────────────────────────────────────────────────────────
                Button {
                    Task {
                        if speech.isRecording {
                            speech.stop()
                            parseTranscript()
                        } else {
                            intent = nil
                            await speech.start()
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(speech.isRecording ? Color.red.opacity(0.15) : Color.blue.opacity(0.12))
                            .frame(width: 140, height: 140)
                        Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(speech.isRecording ? .red : .blue)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speech.isRecording ? "Stop recording" : "Start recording")

                Text(speech.isRecording ? "Listening — tap to stop" : "Tap the mic and say what you need")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // ── Transcript ─────────────────────────────────────────────────
                if !speech.transcript.isEmpty {
                    Text("\u{201C}\(speech.transcript)\u{201D}")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }

                // ── What we understood ─────────────────────────────────────────
                if let intent {
                    VStack(spacing: 10) {
                        VStack(spacing: 4) {
                            Text(intent.title).font(.headline)
                            Text(intent.summary { appSettings.memberName(at: $0) })
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                        Button {
                            openDraft(for: intent)
                        } label: {
                            Label(intent.kind == .chore ? "Review Chore" : "Review Item",
                                  systemImage: "arrow.right.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Text("You'll confirm the details before it's saved.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                if let error = speech.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // ── Examples ───────────────────────────────────────────────────
                if speech.transcript.isEmpty && intent == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Try saying:").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("\u{201C}Add task due tomorrow to clean the bathroom\u{201D}")
                        Text("\u{201C}Add milk to the shopping list\u{201D}")
                        Text("\u{201C}Remind me to mow the lawn Friday at 9am\u{201D}")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
            .navigationTitle("Voice Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { speech.reset(); dismiss() }
                }
            }
            .onDisappear { speech.reset() }
            .sheet(item: $choreDraft) { draft in
                ChoreFormView(chore: draft, isPrefilledDraft: true)
            }
            .sheet(item: $shoppingDraft) { draft in
                ShoppingFormView(item: draft, isPrefilledDraft: true)
            }
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    private func parseTranscript() {
        let text = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        intent = parser.parse(text, members: appSettings.members)
    }

    /// Builds the prefilled document and opens the matching form.
    private func openDraft(for intent: VoiceIntent) {
        switch intent.kind {
        case .chore:
            var chore = ChoreDoc(
                id: UUID().uuidString, title: intent.title, notes: nil,
                assignedToMembers: intent.assignedMembers,
                dueDateType: DueDateType.none.rawValue, dueDate: nil,
                repeatInterval: RepeatInterval.none.rawValue,
                isCompleted: false, completedAt: nil, completedByMembers: [],
                categoryId: nil, sortOrder: 0, createdAt: Date()
            )
            if let date = intent.date {
                chore.dueDateTypeEnum = .specificDate
                chore.dueDate    = date
                chore.hasDueTime = intent.hasTime
            }
            choreDraft = chore

        case .shopping:
            var item = ShoppingItemDoc(
                id: UUID().uuidString, name: intent.title, quantity: nil,
                store: nil, itemType: nil,
                assignedToMembers: intent.assignedMembers,
                isPurchased: false, purchasedAt: nil, notes: nil,
                sortOrder: 0, createdAt: Date()
            )
            if let date = intent.date {
                item.needByDate    = date
                item.hasNeedByTime = intent.hasTime
            }
            shoppingDraft = item
        }
    }
}
