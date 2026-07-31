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
    TranscriptionSettingsView(settings: settings)
      .frame(width: 800, height: 550)
  }
}
