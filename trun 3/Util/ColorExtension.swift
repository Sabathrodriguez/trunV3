//
//  ColorExtension.swift
//  trun
//
//  Created by Claude on 2/18/26.
//

import SwiftUI

extension Color {
    /// Deterministically maps a UID string to one of 8 predefined colors.
    /// Same UID always produces the same color on all devices.
    static func fromUID(_ uid: String) -> Color {
        let colors: [Color] = [
            .blue, .green, .red, .orange,
            .purple, .teal, .pink, .indigo
        ]
        var hash: UInt64 = 5381
        for byte in uid.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        let index = Int(hash % UInt64(colors.count))
        return colors[index]
    }
}
