// Color+Hex.swift
// HouseholdApp
//
// Extends SwiftUI.Color with hex string initialisation and export.
// Used by Category to store and retrieve colors from Core Data.

import SwiftUI

extension Color {

    /// Initialises a Color from a hex string.
    /// Supports:  "#RGB"  "#RRGGBB"  "#RRGGBBAA"  (leading # optional)
    ///
    /// Returns nil if the string cannot be parsed.
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }

        let len = cleaned.count
        guard len == 3 || len == 6 || len == 8 else { return nil }

        // Expand shorthand "#RGB" → "#RRGGBB"
        if len == 3 {
            cleaned = cleaned.map { "\($0)\($0)" }.joined()
        }

        var rgbValue: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&rgbValue) else { return nil }

        let r, g, b, a: Double
        if len == 8 {
            r = Double((rgbValue >> 24) & 0xFF) / 255
            g = Double((rgbValue >> 16) & 0xFF) / 255
            b = Double((rgbValue >>  8) & 0xFF) / 255
            a = Double( rgbValue        & 0xFF) / 255
        } else {
            r = Double((rgbValue >> 16) & 0xFF) / 255
            g = Double((rgbValue >>  8) & 0xFF) / 255
            b = Double( rgbValue        & 0xFF) / 255
            a = 1.0
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Returns a hex string representation e.g. "#FF6B6B".
    /// Uses the sRGB color space; clips out-of-gamut values.
    var hexString: String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(min(max(r, 0), 1) * 255)
        let gi = Int(min(max(g, 0), 1) * 255)
        let bi = Int(min(max(b, 0), 1) * 255)
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}
