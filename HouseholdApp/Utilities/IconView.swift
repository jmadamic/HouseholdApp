// IconView.swift
// HouseholdApp
//
// Shared icon rendering + picker that supports both SF Symbols and emoji.
// Use AppIcon / AppIconLabel anywhere you'd use Image(systemName:) / Label(_, systemImage:).
// Use IconPickerSection inside a Form to let users choose an icon.

import SwiftUI

// ── Detection ─────────────────────────────────────────────────────────────────

extension String {
    /// True when this string is an emoji/unicode character rather than an SF Symbol name.
    /// SF Symbol names are pure ASCII (letters, digits, dots, hyphens), so any
    /// non-ASCII scalar means it's an emoji.
    var isEmojiIcon: Bool {
        unicodeScalars.contains { $0.value > 127 }
    }
}

// ── AppIcon ───────────────────────────────────────────────────────────────────

/// Renders either an emoji (Text) or an SF Symbol (Image), depending on the name.
struct AppIcon: View {
    let name: String
    var color: Color = .primary
    var font: Font = .body

    var body: some View {
        if name.isEmojiIcon {
            Text(name).font(font)
        } else {
            Image(systemName: name).font(font).foregroundStyle(color)
        }
    }
}

// ── AssigneeBadges ────────────────────────────────────────────────────────────

/// Who an item is assigned to, shown on list rows: a small initial avatar per
/// member ("J", "S") in that member's color, so it reads without relying on
/// color alone. Everyone gets the two-person glyph in Everyone purple. Shows up
/// to three avatars, then "+N".
struct AssigneeBadges: View {
    @EnvironmentObject private var appSettings: AppSettings
    let indices: [Int]
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 20

    var body: some View {
        let sorted = indices.sorted()
        HStack(spacing: 3) {
            if sorted.isEmpty {
                avatar(color: .purple) {
                    Image(systemName: "person.2.fill").font(.caption2)
                }
            } else {
                ForEach(sorted.prefix(3), id: \.self) { idx in
                    avatar(color: appSettings.memberColor(at: idx)) {
                        Text(appSettings.memberInitials(at: idx))
                            .font(.caption2.weight(.bold))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                }
                if sorted.count > 3 {
                    Text("+\(sorted.count - 3)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sorted.isEmpty
            ? "Everyone"
            : sorted.map { appSettings.memberName(at: $0) }.joined(separator: " and "))
    }

    /// Twelve Percent Rule: a soft wash of the member's color with the
    /// full-strength color on the letter.
    private func avatar<Content: View>(color: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: Circle())
    }
}

// ── MemberFilterMenu ──────────────────────────────────────────────────────────

/// Toolbar dropdown that filters a list to one member's items (plus
/// Everyone's). Replaces the old segmented "All / Me / Partner" bar, which
/// cramped with more than three members or long names. `selection` is -2 for
/// All, otherwise a member index. The label names the current choice, and the
/// icon fills while the list is narrowed so a filtered list is obvious.
struct MemberFilterMenu: View {
    @EnvironmentObject private var appSettings: AppSettings
    @Binding var selection: Int

    static let all = -2
    private var isFiltered: Bool { selection >= 0 }

    var body: some View {
        Menu {
            Picker("Show items for", selection: $selection) {
                Text("All").tag(Self.all)
                ForEach(Array(appSettings.members.indices), id: \.self) { idx in
                    Text(appSettings.memberName(at: idx)).tag(idx)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isFiltered
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                Text(isFiltered ? appSettings.memberName(at: selection) : "All")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 110)
            }
            .font(.subheadline.weight(.medium))
        }
        .accessibilityLabel("Filter by person")
        .accessibilityValue(isFiltered ? appSettings.memberName(at: selection) : "All")
        // Reset if the selected member was removed in Settings.
        .onChange(of: appSettings.members.count) { _, count in
            if selection >= count { selection = Self.all }
        }
    }
}

// ── AppIconLabel ──────────────────────────────────────────────────────────────

/// Drop-in replacement for Label(title, systemImage:) that supports emoji icons.
struct AppIconLabel: View {
    let title: String
    let icon: String
    var color: Color = .primary

    var body: some View {
        Label {
            Text(title)
        } icon: {
            AppIcon(name: icon, color: color)
        }
    }
}

// ── IconPickerSection ─────────────────────────────────────────────────────────

/// A Form Section containing a Symbols / Emoji segmented picker + grid.
/// Bind `iconName` — it holds either an SF Symbol name or an emoji string.
struct IconPickerSection: View {
    @Binding var iconName: String
    var accentColor: Color = .blue

    @State private var tab: IconTab = .symbols

    enum IconTab: Hashable { case symbols, emoji }

    // ── SF Symbol list ────────────────────────────────────────────────────────
    static let sfSymbolOptions: [String] = [
        "fork.knife",   "cup.and.saucer.fill", "trash.fill",       "washer.fill",
        "shower",       "bed.double.fill",      "sofa.fill",        "chair.fill",
        "cart.fill",    "leaf.fill",            "figure.walk",      "car.fill",
        "house.fill",   "envelope.fill",        "phone.fill",       "pawprint.fill",
        "wrench.fill",  "lightbulb.fill",       "paintbrush.fill",  "scissors",
        "hammer.fill",  "archivebox.fill",      "bag.fill",         "star.fill",
    ]

    // ── Emoji list ────────────────────────────────────────────────────────────
    static let emojiOptions: [String] = [
        // Household & cleaning
        "🏠", "🛁", "🚿", "🪥", "🧹", "🧺", "🧻", "🧼", "🪣", "🧯",
        // Kitchen
        "🍽️", "🥘", "☕", "🍳", "🧊", "🫖",
        // Home items
        "🛏️", "🛋️", "🪑", "🚪", "🪟", "🔑",
        // Food & grocery
        "🍎", "🥦", "🥛", "🧀", "🥩", "🍞", "🥚", "🧈", "🥕", "🍋",
        // Shopping
        "🛍️", "🏪", "🏬", "📦", "🎁",
        // Tools & maintenance
        "🔧", "🔨", "🪛", "🔩", "⚙️", "🪜", "🔦", "💡", "🔋", "🪝",
        // Nature & outdoor
        "🌿", "🌱", "🌻", "🌳", "☀️", "🌙", "⭐", "🍂", "🌸",
        // Transport
        "🚗", "🚲", "✈️", "⛽",
        // Health & personal
        "💊", "💪", "🧴", "🩺",
        // Misc
        "❤️", "🎉", "📋", "🗑️", "📝", "💰", "🎯", "🏆",
    ]

    var body: some View {
        Section("Icon") {
            Picker("", selection: $tab) {
                Text("Symbols").tag(IconTab.symbols)
                Text("Emoji").tag(IconTab.emoji)
            }
            .pickerStyle(.segmented)

            if tab == .symbols {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 6),
                    spacing: 14
                ) {
                    ForEach(Self.sfSymbolOptions, id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundStyle(iconName == icon ? .white : accentColor)
                            .frame(width: 40, height: 40)
                            .background(
                                iconName == icon ? accentColor : accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .onTapGesture { iconName = icon }
                    }
                }
                .padding(.vertical, 4)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 7),
                    spacing: 10
                ) {
                    ForEach(Self.emojiOptions, id: \.self) { emoji in
                        Text(emoji)
                            .font(.title3)
                            .frame(width: 38, height: 38)
                            .background(
                                iconName == emoji
                                    ? accentColor.opacity(0.25)
                                    : accentColor.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(iconName == emoji ? accentColor : .clear, lineWidth: 2)
                            )
                            .onTapGesture { iconName = emoji }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            tab = iconName.isEmojiIcon ? .emoji : .symbols
        }
        .onChange(of: iconName) { _, new in
            // Keep tab in sync if icon is changed from outside (e.g. onAppear populate)
            let expected: IconTab = new.isEmojiIcon ? .emoji : .symbols
            if tab != expected { tab = expected }
        }
    }
}
