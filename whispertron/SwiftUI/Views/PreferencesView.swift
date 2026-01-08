//
//  PreferencesView.swift
//  whispertron
//
//  Created by shayegan hooshyari on 12/15/25.
//

import SwiftUI

struct PreferencesView: View {
  @ObservedObject var settings: AppSettings
  @ObservedObject var historyManager: HistoryManager

  var body: some View {
    TabView {
      TranscriptionSettingsView(settings: settings)
        .tabItem {
          Label("Transcription", systemImage: "waveform")
        }

      CustomPromptsView(settings: settings)
        .tabItem {
          Label("Custom Prompt", systemImage: "wand.and.stars")
        }
      
      HistoryView(historyManager: historyManager, settings: settings)
        .tabItem {
          Label("History", systemImage: "clock.arrow.circlepath")
        }
    }
    .frame(width: 800, height: 550)
  }
}
