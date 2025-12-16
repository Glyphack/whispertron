//
//  PreferencesView.swift
//  whispertron
//
//  Created by shayegan hooshyari on 12/15/25.
//

import SwiftUI

struct PreferencesView: View {
  @ObservedObject var settings: AppSettings

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
    }
    .frame(width: 800, height: 550)
  }
}
