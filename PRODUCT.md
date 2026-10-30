# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users
Today: Jordan and his wife, each on their own iPhone (an iPhone 12 Pro and an iPhone 16), sharing one household. They open the app in short bursts through the day: checking what's due, ticking off a chore, adding something to the shopping list while standing in the kitchen or the store aisle.

Later: other households (families, roommates) with any number of members. Nothing in the product should assume exactly two people; it already supports N members.

## Product Purpose
One shared place for the running logistics of a home: chores, shopping, meal planning, the garden, trip packing, and "things we're looking for" research. Success is that both people trust the list enough to stop keeping it in their heads, and that adding or checking off an item takes seconds.

## Positioning
Everything household-shaped in one app, with the pieces linked rather than siloed: a meal's missing ingredients become shopping items that route back to the meal, garden harvests show up as "Growing" hints on the shopping list, trip meals feed the packing list, and a spreadsheet meal plan can populate meals, shopping, trips, and packing in one import.

## Operating Context
- Used one-handed, mid-task, often while doing the chore or standing in a store.
- Each item can be assigned to a person or to Everyone; filter bars show "All" plus one tab per member.
- Voice entry ("add task due tomorrow to clean bathroom") prefills a form for confirmation.
- Meal plans can be drafted in Excel or Google Sheets from a bundled template and imported.
- Local reminders only (no push between devices).

## Capabilities and Constraints
- Native SwiftUI app; data in Firebase/Firestore, shared per household and synced live between phones.
- Seven tabs (Chores, Shopping, Meals, Garden, Packing, Looking For, Settings); tab order is configurable per device, so iOS shows the first four and puts the rest under More.
- Currently sideloaded on a free Apple developer account (7-day signing). No App Store distribution yet, no paid capabilities (no push notifications, no image storage).
- In daily use: changes must never wipe or orphan household data, and older builds on the other phone must keep working.
- Must run on an iPhone 12 Pro, so no Apple Intelligence-dependent features.

## Brand Commitments
Name: HouseholdApp (working name). No logo, typeface, or brand voice has been committed beyond the existing app.

## Evidence on Hand
No testimonials, users beyond the founding household, metrics, or press. Do not invent any.

## Product Principles
1. Fast capture beats rich data: adding or completing an item should never take more than a tap or two.
2. Shared by default, personal on demand: everything is visible to the household; assignment and filtering narrow it to one person.
3. Connected, not duplicated: link items across tabs (meal → shopping → packing) instead of copying them.
4. Never lose the household's data; archive before delete.
5. Works for any household size, not just two.
