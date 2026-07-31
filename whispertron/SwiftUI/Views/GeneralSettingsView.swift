import SwiftUI
import KeyboardShortcuts

struct GeneralSettingsView: View {
  @ObservedObject var settings: AppSettings
  let onIconVisibilityChange: (IconVisibilityMode) -> Void

  @State private var showResetConfirmation = false
  @State private var accessibilityTrusted: Bool = AXIsProcessTrusted()
  private let accessibilityTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

  var body: some View {
    Form {
      Section("Shortcuts") {
        LabeledContent {
          KeyboardShortcuts.Recorder(for: .toggleRecording)
        } label: {
          Label("Hold to record", systemImage: "mic.fill")
            .symbolRenderingMode(.hierarchical)
        }

        LabeledContent {
          KeyboardShortcuts.Recorder(for: .toggleRecordingButton)
        } label: {
          Label("Toggle recording", systemImage: "record.circle")
            .symbolRenderingMode(.hierarchical)
        }
      }

      Section {
        LabeledContent {
          HStack(spacing: 8) {
            Text("\(settings.config.maxHistoryEntries)")
              .monospacedDigit()
              .frame(minWidth: 56, alignment: .trailing)
            Stepper("", value: $settings.config.maxHistoryEntries, in: 0...10000, step: 50)
              .labelsHidden()
          }
        } label: {
          Label("Entries kept", systemImage: "tray.full")
            .symbolRenderingMode(.hierarchical)
        }
      } header: {
        Text("History")
      } footer: {
        Text("Maximum number of transcriptions kept in memory. Set to 0 to disable history.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section {
        LabeledContent {
          Picker("", selection: $settings.config.iconVisibility) {
            ForEach(IconVisibilityMode.allCases, id: \.self) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 180)
        } label: {
          Label("App icon", systemImage: "macwindow.on.rectangle")
            .symbolRenderingMode(.hierarchical)
        }
      } header: {
        Text("Appearance")
      } footer: {
        Text("Menubar shows a status icon in the menu bar. Dock shows a regular app icon in the Dock.")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .onChange(of: settings.config.iconVisibility) { newValue in
        settings.save()
        onIconVisibilityChange(newValue)
      }

      Section {
        LabeledContent {
          HStack(spacing: 10) {
            Circle()
              .fill(accessibilityTrusted ? Color.green : Color.orange)
              .frame(width: 8, height: 8)
            Text(accessibilityTrusted ? "Enabled" : "Not enabled")
              .font(.callout)
              .foregroundColor(accessibilityTrusted ? .secondary : .primary)
            if !accessibilityTrusted {
              Button("Open System Settings") {
                openAccessibilitySettings()
              }
              .controlSize(.small)
            }
          }
        } label: {
          Label("Accessibility", systemImage: "hand.raised")
            .symbolRenderingMode(.hierarchical)
        }
      } header: {
        Text("Permissions")
      } footer: {
        Text("Whispertron needs Accessibility permission to insert transcribed text at your cursor.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section {
        HStack {
          Spacer()
          Button(role: .destructive) {
            showResetConfirmation = true
          } label: {
            Text("Reset to Defaults")
          }
          Spacer()
        }
        .listRowBackground(Color.clear)
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .onChange(of: settings.config.maxHistoryEntries) { _ in settings.save() }
    .onReceive(accessibilityTimer) { _ in
      let trusted = AXIsProcessTrusted()
      if trusted != accessibilityTrusted {
        accessibilityTrusted = trusted
      }
    }
    .confirmationDialog(
      "Reset all settings to defaults?",
      isPresented: $showResetConfirmation,
      titleVisibility: .visible
    ) {
      Button("Reset", role: .destructive) {
        Task { @MainActor in
          let previousMode = settings.config.iconVisibility
          await settings.resetToDefaults()
          if settings.config.iconVisibility != previousMode {
            onIconVisibilityChange(settings.config.iconVisibility)
          }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will revert all settings — shortcuts, models, history limit, and appearance — to their default values.")
    }
  }

  private func openAccessibilitySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }
}
