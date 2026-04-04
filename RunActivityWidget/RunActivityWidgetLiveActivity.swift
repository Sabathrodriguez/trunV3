//
//  RunActivityWidgetLiveActivity.swift
//  RunActivityWidget
//
//  Created by Sabath  Rodriguez on 3/26/26.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct RunActivityWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            // MARK: - Lock Screen / Banner UI
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DISTANCE")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatDistance(context.state.distanceMiles))
                            .font(.system(.title2, design: .rounded).bold())
                        Text("mi")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(paceLabel(context.attributes.activityType))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.pace)
                            .font(.system(.title2, design: .rounded).bold())
                        Text(paceUnit(context.attributes.activityType))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("TIME")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if context.state.isPaused {
                            Text(formatElapsed(context.state.elapsedSeconds))
                                .font(.system(.title3, design: .monospaced).bold())
                        } else {
                            Text(context.state.timerDate, style: .timer)
                                .font(.system(.title3, design: .monospaced).bold())
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isPaused {
                        Text("PAUSED")
                            .font(.caption.bold())
                            .foregroundStyle(.yellow)
                    }
                }
            } compactLeading: {
                // Only show compact leading/trailing when running a route
                if context.attributes.isRouteRun {
                    Text(formatDistance(context.state.distanceMiles))
                        .font(.system(.body, design: .rounded).bold())
                        .foregroundStyle(.green)
                }
            } compactTrailing: {
                if context.attributes.isRouteRun {
                    Text(context.state.pace)
                        .font(.system(.body, design: .rounded).bold())
                }
            } minimal: {
                Image(systemName: "figure.run")
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<RunActivityAttributes>) -> some View {
        HStack(spacing: 20) {
            // Distance
            VStack(alignment: .leading, spacing: 2) {
                Text("DISTANCE")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(formatDistance(context.state.distanceMiles))
                    .font(.system(.largeTitle, design: .rounded).bold())
                Text("miles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Time
            VStack(spacing: 2) {
                Text("TIME")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                if context.state.isPaused {
                    Text(formatElapsed(context.state.elapsedSeconds))
                        .font(.system(.title2, design: .monospaced).bold())
                } else {
                    Text(context.state.timerDate, style: .timer)
                        .font(.system(.title2, design: .monospaced).bold())
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()

            // Pace
            VStack(alignment: .trailing, spacing: 2) {
                Text(paceLabel(context.attributes.activityType))
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(context.state.pace)
                    .font(.system(.title2, design: .rounded).bold())
                Text(paceUnit(context.attributes.activityType))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .overlay(alignment: .topTrailing) {
            if context.state.isPaused {
                Text("PAUSED")
                    .font(.caption2.bold())
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.yellow.opacity(0.2), in: Capsule())
                    .padding(8)
            }
        }
    }

    // MARK: - Helpers

    private func formatDistance(_ miles: Double) -> String {
        String(format: "%.2f", miles)
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }


    private func paceLabel(_ activityType: String) -> String {
        activityType == "Cycling" ? "SPEED" : "PACE"
    }

    private func paceUnit(_ activityType: String) -> String {
        activityType == "Cycling" ? "mph" : "/mi"
    }
}
