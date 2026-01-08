//
//  HistoryView.swift
//  whispertron
//
//  Created by shayegan hooshyari on 1/8/26.
//

import SwiftUI

struct HistoryView: View {
  @ObservedObject var historyManager: HistoryManager
  @ObservedObject var settings: AppSettings
  @State private var selectedEntry: TranscriptionEntry?
  @State private var showClearAllAlert = false
  
  var body: some View {
    NavigationSplitView {
      List(selection: $selectedEntry) {
        ForEach(historyManager.entries) { entry in
          VStack(alignment: .leading, spacing: 4) {
            Text(truncateText(entry.text))
              .lineLimit(2)
            Text(entry.timestamp, style: .relative)
              .font(.caption)
              .foregroundColor(.secondary)
          }
          .padding(.vertical, 4)
          .tag(entry)
        }
      }
      .navigationTitle("History")
      .toolbar {
        ToolbarItem(placement: .automatic) {
          Text("\(historyManager.entries.count) / \(settings.config.maxHistoryEntries)")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        ToolbarItem(placement: .automatic) {
          Button("Clear All") {
            showClearAllAlert = true
          }
          .disabled(historyManager.entries.isEmpty)
        }
      }
      .frame(minWidth: 300)
    } detail: {
      if let entry = selectedEntry {
        VStack(alignment: .leading, spacing: 16) {
          ScrollView {
            Text(entry.text)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding()
          }
          
          Divider()
          
          HStack {
            VStack(alignment: .leading) {
              Text("Created: \(entry.timestamp, formatter: dateFormatter)")
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
          }
          .padding()
        }
      } else {
        VStack {
          Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: 48))
            .foregroundColor(.secondary)
          Text(historyManager.entries.isEmpty ? "No transcriptions yet" : "Select an entry to view")
            .foregroundColor(.secondary)
        }
      }
    }
    .alert("Clear All History?", isPresented: $showClearAllAlert) {
      Button("Clear", role: .destructive) {
        historyManager.clearAll()
        selectedEntry = nil
      }
      Button("Cancel", role: .cancel) { }
    } message: {
      Text("This will delete all \(historyManager.entries.count) entries. This action cannot be undone.")
    }
  }
  
  private func truncateText(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count <= 60 {
      return trimmed
    }
    return String(trimmed.prefix(60)) + "..."
  }
  
  private var dateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }
}
