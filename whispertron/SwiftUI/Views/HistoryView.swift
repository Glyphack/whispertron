import SwiftUI

struct HistoryView: View {
  @ObservedObject var historyManager: HistoryManager
  @ObservedObject var settings: AppSettings
  @State private var selectedEntry: TranscriptionEntry?
  @State private var showClearAllAlert = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      HSplitView {
        sidebar
          .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
        detail
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .alert("Clear All History?", isPresented: $showClearAllAlert) {
      Button("Clear", role: .destructive) {
        historyManager.clearAll()
        selectedEntry = nil
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will delete all \(historyManager.entries.count) entries. This action cannot be undone.")
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Label("History", systemImage: "clock.arrow.circlepath")
        .labelStyle(.titleAndIcon)
        .font(.headline)
      Spacer()
      Text("\(historyManager.entries.count) / \(settings.config.maxHistoryEntries)")
        .font(.caption)
        .foregroundColor(.secondary)
        .monospacedDigit()
      Button("Clear All") {
        showClearAllAlert = true
      }
      .disabled(historyManager.entries.isEmpty)
      .controlSize(.small)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
  }

  private var sidebar: some View {
    Group {
      if historyManager.entries.isEmpty {
        VStack(spacing: 8) {
          Spacer()
          Image(systemName: "tray")
            .font(.system(size: 28))
            .foregroundColor(.secondary)
          Text("No transcriptions")
            .font(.callout)
            .foregroundColor(.secondary)
          Spacer()
        }
        .frame(maxWidth: .infinity)
      } else {
        List(selection: $selectedEntry) {
          ForEach(historyManager.entries) { entry in
            VStack(alignment: .leading, spacing: 4) {
              Text(truncateText(entry.text))
                .lineLimit(2)
                .font(.system(.body, design: .default))
              Text(entry.timestamp, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .tag(entry)
          }
        }
      }
    }
  }

  private var detail: some View {
    Group {
      if let entry = selectedEntry {
        VStack(alignment: .leading, spacing: 0) {
          ScrollView {
            Text(entry.text)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(20)
          }
          Divider()
          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
              Text(entry.timestamp, formatter: Self.dateFormatter)
                .font(.caption)
                .foregroundColor(.secondary)
              Text("\(entry.text.count) characters")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            Button("Delete") {
              historyManager.deleteEntry(id: entry.id)
              selectedEntry = historyManager.entries.first
            }
            .buttonStyle(.bordered)
            Button("Copy") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(entry.text, forType: .string)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("c", modifiers: [.command])
          }
          .padding(20)
        }
      } else {
        VStack(spacing: 10) {
          Spacer()
          Image(systemName: "text.quote")
            .font(.system(size: 38, weight: .light))
            .foregroundColor(.secondary)
          Text(historyManager.entries.isEmpty ? "No transcriptions yet" : "Select an entry to view")
            .font(.callout)
            .foregroundColor(.secondary)
          Text("History is kept in memory and resets when the app restarts.")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
          Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private func truncateText(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count <= 60 {
      return trimmed
    }
    return String(trimmed.prefix(60)) + "…"
  }

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()
}
