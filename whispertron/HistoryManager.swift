//
//  HistoryManager.swift
//  whispertron
//
//  Created by shayegan hooshyari on 12/18/25.
//

import Foundation
import SwiftUI

struct HistoryItem: Identifiable, Equatable {
  let id = UUID()
  let timestamp = Date()
  let text: String

  var previewText: String {
    text.count <= 50 ? text : String(text.prefix(50)) + "..."
  }

  var formattedTimestamp: String {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .medium
    return f.string(from: timestamp)
  }
}

class HistoryManager: ObservableObject {
  @Published private(set) var items: [HistoryItem] = []
  @Published var selectedItemID: UUID?

  var selectedItem: HistoryItem? {
    guard let id = selectedItemID else { return nil }
    return items.first { $0.id == id }
  }

  func addItem(_ text: String) {
    print("[HistoryManager] addItem called with text: \(text.prefix(50))...")
    print("[HistoryManager] Current thread: \(Thread.current)")
    DispatchQueue.main.async {
      self.items.insert(HistoryItem(text: text), at: 0)
      print("[HistoryManager] Item inserted. Total items: \(self.items.count)")
    }
  }

  func debugPrint() {
    print("[HistoryManager] debugPrint - Total items: \(items.count)")
    for (i, item) in items.enumerated() {
      print("[HistoryManager]   [\(i)] \(item.formattedTimestamp): \(item.text.prefix(30))...")
    }
  }

  func clearAll() {
    items.removeAll()
    selectedItemID = nil
  }

  func copySelected() {
    guard let item = selectedItem else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(item.text, forType: .string)
  }
}
