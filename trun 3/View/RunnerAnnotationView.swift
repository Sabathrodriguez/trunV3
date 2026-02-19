//
//  RunnerAnnotationView.swift
//  trun
//
//  Created by Claude on 2/18/26.
//

import SwiftUI

struct RunnerAnnotationView: View {
    let runner: Runner

    var body: some View {
        VStack(spacing: 2) {
            Text(runner.name.prefix(1).uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(runner.color))
                .shadow(color: runner.color.opacity(0.6), radius: 4)

            // Small pointer triangle
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 6))
                .foregroundColor(runner.color)
        }
    }
}
