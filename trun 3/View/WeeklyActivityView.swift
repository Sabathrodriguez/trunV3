//
//  WeeklyActivityView.swift
//  trun 3
//

import SwiftUI
import HealthKit

struct WeeklyActivityView: View {
    var runMiles: Double
    var cycleMiles: Double
    var walkMiles: Double

    var body: some View {
        HStack(spacing: 20) {
            ActivityCircle(label: "Run", miles: runMiles, color: .green)
            ActivityCircle(label: "Ride", miles: cycleMiles, color: .orange)
            ActivityCircle(label: "Walk", miles: walkMiles, color: .blue)
        }
        .padding(.vertical, 8)
    }
}

private struct ActivityCircle: View {
    let label: String
    let miles: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 60, height: 60)
                Circle()
                    .stroke(color, lineWidth: 3)
                    .frame(width: 60, height: 60)
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", miles))
                        .font(.system(.callout, design: .rounded).bold())
                        .foregroundColor(color)
                    Text("mi")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(color.opacity(0.7))
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
