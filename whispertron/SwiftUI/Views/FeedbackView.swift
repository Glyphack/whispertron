//
//  FeedbackView.swift
//  whispertron
//
//  Created by shayegan hooshyari on 12/15/25.
//

import SwiftUI

struct FeedbackView: View {
  @ObservedObject var viewModel: FeedbackViewModel

  var body: some View {
    ZStack {
      backgroundView
        .frame(width: 200, height: 200)

      VStack(spacing: 12) {
        switch viewModel.state {
        case .recording:
          audioVisualizerView
          timerView

        case .transcribing:
          audioVisualizerView
          timerView

        case .downloading(let progress):
          VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
              .font(.system(size: 80, weight: .medium))
              .foregroundColor(.primary)

            ProgressView(value: progress, total: 1.0)
              .frame(width: 120)
          }
        }
      }
    }
    .frame(width: 200, height: 200)
  }

  @ViewBuilder
  private var backgroundView: some View {
    if #available(macOS 12.0, *) {
      RoundedRectangle(cornerRadius: 15)
        .fill(Material.ultraThinMaterial)
    } else {
      RoundedRectangle(cornerRadius: 15)
        .fill(Color(NSColor.windowBackgroundColor).opacity(0.8))
    }
  }

  @ViewBuilder
  private var audioVisualizerView: some View {
    let heights = barHeights(
      audioLevel: viewModel.state == .recording ? viewModel.audioLevel : 0,
      barCount: 12
    )

    HStack(spacing: 4) {
      ForEach(0..<12, id: \.self) { index in
        RoundedRectangle(cornerRadius: 3)
          .fill(Color.primary)
          .frame(width: 6, height: heights[index])
          .animation(.easeInOut(duration: 0.08), value: heights[index])
      }
    }
    .frame(height: 80)
  }

  @ViewBuilder
  private var timerView: some View {
    Text(formattedDuration)
      .font(.system(size: 16, weight: .medium, design: .monospaced))
      .foregroundColor(.primary)
  }

  private var formattedDuration: String {
    let duration = viewModel.recordingDuration

    if duration < 60 {
      return String(format: "%.1fs", duration)
    } else {
      let minutes = Int(duration) / 60
      let seconds = Int(duration) % 60
      return String(format: "%d:%02d", minutes, seconds)
    }
  }

  private func barHeights(audioLevel: Float, barCount: Int = 12) -> [CGFloat] {
    let minHeight: CGFloat = 8
    let maxHeight: CGFloat = 70

    // When no audio, all bars at minimum
    guard audioLevel > 0.01 else {
      return Array(repeating: minHeight, count: barCount)
    }

    // Generate varied heights with pseudo-frequency simulation
    var heights: [CGFloat] = []
    let scaledLevel = CGFloat(audioLevel)

    for i in 0..<barCount {
      // Frequency band simulation weights
      let normalizedPos = Double(i) / Double(barCount - 1) // 0.0 to 1.0

      // Lower frequencies respond more, higher frequencies less
      let frequencyWeight = 1.0 - (normalizedPos * 0.7)

      // Add deterministic variation using sine
      let phaseOffset = Double(i) * 0.8
      let variation = sin(Date().timeIntervalSinceReferenceDate * 3 + phaseOffset) * 0.3 + 0.7

      // Calculate height
      let heightRange = maxHeight - minHeight
      let responseLevel = scaledLevel * CGFloat(frequencyWeight * variation)
      let height = minHeight + (heightRange * responseLevel)

      heights.append(height)
    }

    return heights
  }
}
