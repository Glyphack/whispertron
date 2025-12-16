//
//  TranscriptionSettingsView.swift
//  whispertron
//
//  Created by shayegan hooshyari on 12/15/25.
//

import SwiftUI
import KeyboardShortcuts

struct TranscriptionSettingsView: View {
  @ObservedObject var settings: AppSettings
  @State private var isDownloading = false
  @State private var downloadProgress: Double = 0
  @State private var showDownloadAlert = false
  @State private var pendingModel: ModelInfo?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .top, spacing: 20) {
          primarySettingsCard
            .frame(maxWidth: .infinity)

          advancedSettingsCard
            .frame(maxWidth: .infinity)
        }

        accessibilityCard
          .frame(maxWidth: .infinity)
      }
      .padding(30)
    }
    .alert(isPresented: $showDownloadAlert) {
      let modelsPath = AppSettings.modelsDir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
      return Alert(
        title: Text("Download Model?"),
        message: Text(pendingModel.map { "This will download \($0.displayName) to \(modelsPath)/. The download may take a few minutes." } ?? ""),
        primaryButton: .default(Text("Download")) {
          Task {
            if let model = pendingModel {
              if #available(macOS 12.0, *) {
                await downloadModel(model)
              }
            }
          }
        },
        secondaryButton: .cancel {
          // Revert to previous model
          if let available = settings.availableModels.first {
            settings.config.currentModel = available
          }
        }
      )
    }
  }

  private var primarySettingsCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "slider.horizontal.3")
          .foregroundColor(.accentColor)
        Text("Primary Settings")
          .font(.headline)
      }

      formField(label: "Whisper Model") {
        VStack(alignment: .leading, spacing: 8) {
          Picker("", selection: $settings.config.currentModel) {
            ForEach(ModelInfo.allCases, id: \.self) { model in
              Text(modelDisplayTitle(model)).tag(model)
            }
          }
          .labelsHidden()
          .disabled(isDownloading)
          .onChange(of: settings.config.currentModel) { newModel in
            handleModelChange(newModel)
          }

          if isDownloading {
            HStack(spacing: 8) {
              ProgressView(value: downloadProgress, total: 1.0)
                .frame(height: 8)
              Text("\(Int(downloadProgress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
      }

      formField(label: "AI Post-Processing", helpText: "ℹ Uses AI to improve transcription") {
        Picker("", selection: $settings.config.transcriptionMode) {
          Text("Local Only").tag(TranscriptionMode.onlyTranscribe)
          ForEach(settings.config.presets) { preset in
            Text(preset.name).tag(TranscriptionMode.aiPreset(preset.id))
          }
        }
        .labelsHidden()
      }

      formField(label: "Language") {
        Picker("", selection: $settings.config.language) {
          ForEach(OutputLanguage.allCases, id: \.self) { lang in
            Text(lang.displayName).tag(lang)
          }
        }
        .labelsHidden()
      }

      Toggle("Translate to English", isOn: $settings.config.translateToEnglish)
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color(NSColor.controlBackgroundColor))
        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
    )
    .onChange(of: settings.config.currentModel) { _ in settings.save() }
    .onChange(of: settings.config.transcriptionMode) { _ in settings.save() }
    .onChange(of: settings.config.language) { _ in settings.save() }
    .onChange(of: settings.config.translateToEnglish) { _ in settings.save() }
  }

  private var advancedSettingsCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "gearshape")
          .foregroundColor(.accentColor)
        Text("Advanced Settings")
          .font(.headline)
      }

      formField(label: "Hold to Record") {
        KeyboardShortcuts.Recorder(for: .toggleRecording)
      }

      formField(label: "Toggle Recording") {
        KeyboardShortcuts.Recorder(for: .toggleRecordingButton)
      }

      HStack {
        Spacer()
        Button("Reset to Defaults") {
          Task { @MainActor in
            await settings.resetToDefaults()
          }
        }
        .buttonStyle(.borderless)
      }
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color(NSColor.controlBackgroundColor))
        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
    )
  }

  private var accessibilityCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "hand.raised.fill")
          .foregroundColor(.accentColor)
        Text("Accessibility Permission")
          .font(.headline)
      }

      Text("Whispertron requires Accessibility permission to insert transcribed text at your cursor location.")
        .font(.caption)
        .foregroundColor(.secondary)

      HStack {
        Text(accessibilityStatus)
          .font(.caption)
          .foregroundColor(isAccessibilityEnabled ? .green : .red)

        Spacer()

        if !isAccessibilityEnabled {
          Button("Open System Settings") {
            openAccessibilitySettings()
          }
        }
      }
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color(NSColor.controlBackgroundColor))
        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
    )
  }

  private func formField<Content: View>(label: String, helpText: String? = nil, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label)
        .font(.system(size: 13, weight: .semibold))

      content()

      if let helpText = helpText {
        Text(helpText)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

  private func modelDisplayTitle(_ model: ModelInfo) -> String {
    let isAvailable = settings.availableModels.contains(model)
    if model.isBundled {
      return "\(model.displayName) (bundled)"
    } else if isAvailable {
      return model.displayName
    } else {
      return "\(model.displayName) (download)"
    }
  }

  private var isAccessibilityEnabled: Bool {
    AXIsProcessTrusted()
  }

  private var accessibilityStatus: String {
    isAccessibilityEnabled ? "Status: Enabled" : "Status: Not Enabled"
  }

  private func openAccessibilitySettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
  }

  private func handleModelChange(_ newModel: ModelInfo) {
    Task {
      // Check if model is available
      let isAvailable = settings.availableModels.contains(newModel)

      if !isAvailable {
        // Model needs download
        await MainActor.run {
          pendingModel = newModel
          showDownloadAlert = true
        }
      } else {
        // Model is available, just save
        settings.save()
        NotificationCenter.default.post(name: NSNotification.Name("RefreshMenuBar"), object: nil)
      }
    }
  }

  @available(macOS 12.0, *)
  private func downloadModel(_ model: ModelInfo) async {
    await MainActor.run {
      isDownloading = true
      downloadProgress = 0
    }

    do {
      try await settings.downloadModel(model) { @MainActor progress in
        downloadProgress = progress
      }

      await MainActor.run {
        isDownloading = false
        settings.save()
        NotificationCenter.default.post(name: NSNotification.Name("RefreshMenuBar"), object: nil)
      }
    } catch {
      await MainActor.run {
        isDownloading = false
        // Show error alert
        let alert = NSAlert()
        alert.messageText = "Download Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()

        // Revert to previous available model
        if let available = settings.availableModels.first {
          settings.config.currentModel = available
        }
      }
    }
  }
}
