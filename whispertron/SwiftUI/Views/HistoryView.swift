//
//  HistoryView.swift
//  whispertron
//
//  Created by shayegan hooshyari on 12/18/25.
//

import SwiftUI

struct HistoryView: View {
  @ObservedObject var historyManager: HistoryManager
  @State private var selectedID: UUID?

  var body: some View {
    NavigationView {
      // Sidebar list
      List(historyManager.items, id: \.id, selection: $selectedID) { item in
        VStack(alignment: .leading, spacing: 4) {
          Text(item.formattedTimestamp)
            .font(.caption)
            .foregroundColor(.secondary)
          Text(item.previewText)
            .font(.subheadline)
            .lineLimit(2)
        }
        .padding(.vertical, 4)
      }
      .frame(minWidth: 200)
      .toolbar {
        ToolbarItem(placement: .automatic) {
          Button(action: { historyManager.clearAll() }) {
            Image(systemName: "trash")
          }
          .help("Clear History")
          .disabled(historyManager.items.isEmpty)
        }
      }

      // Detail view
      if let id = selectedID, let item = historyManager.items.first(where: { $0.id == id }) {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text(item.formattedTimestamp)
              .font(.headline)
            Spacer()
            Button(action: {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(item.text, forType: .string)
            }) {
              Label("Copy", systemImage: "doc.on.doc")
            }
          }

          ScrollView {
            Text(item.text)
              .font(.body)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding()
        .frame(minWidth: 300)
      } else {
        Text("Select an item to preview")
          .foregroundColor(.secondary)
          .frame(minWidth: 300)
      }
    }
    .frame(minWidth: 600, minHeight: 400)
    .onAppear {
      print("[HistoryView] onAppear - items count: \(historyManager.items.count)")
    }
  }
}
