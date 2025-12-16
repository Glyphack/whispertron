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
          Text("Recording")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)

        case .transcribing:
          pulsingWaveformView
          Text("Transcribing...")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)

        case .loading:
          spinningIconView
          Text("Loading model...")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)

        case .downloading(let progress):
          VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
              .font(.system(size: 80, weight: .medium))
              .foregroundColor(.primary)

            ProgressView(value: progress, total: 1.0)
              .frame(width: 120)

            Text("Downloading")
              .font(.system(size: 13, weight: .medium))
              .foregroundColor(.secondary)
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

  @ViewBuilder
  private var pulsingWaveformView: some View {
    ZStack {
      ForEach(0..<3, id: \.self) { index in
        Image(systemName: "waveform")
          .font(.system(size: 70, weight: .medium))
          .foregroundColor(.primary.opacity(0.3))
          .scaleEffect(1.0 + CGFloat(index) * 0.15)
          .opacity(pulseOpacity(for: index))
      }

      Image(systemName: "waveform")
        .font(.system(size: 70, weight: .medium))
        .foregroundColor(.primary)
    }
    .frame(height: 80)
  }

  @ViewBuilder
  private var spinningIconView: some View {
    Image(systemName: "brain")
      .font(.system(size: 70, weight: .medium))
      .foregroundColor(.primary)
      .rotationEffect(.degrees(spinRotation))
      .frame(height: 80)
  }

  private var pulseOpacity: Double {
    let time = Date().timeIntervalSinceReferenceDate
    return 0.3 + (sin(time * 3) * 0.2)
  }

  private func pulseOpacity(for index: Int) -> Double {
    let time = Date().timeIntervalSinceReferenceDate
    let offset = Double(index) * 0.3
    return max(0, sin(time * 2 + offset) * 0.5)
  }

  private var spinRotation: Double {
    let time = Date().timeIntervalSinceReferenceDate
    return (time * 60).truncatingRemainder(dividingBy: 360)
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
