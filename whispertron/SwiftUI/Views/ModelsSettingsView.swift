import SwiftUI

struct ModelsSettingsView: View {
  @ObservedObject var settings: AppSettings
  @State private var isDownloading = false
  @State private var downloadProgress: Double = 0
  @State private var showDownloadAlert = false
  @State private var pendingModel: ModelInfo?

  var body: some View {
    Form {
      Section {
        LabeledContent {
          Picker("", selection: $settings.config.currentModel) {
            ForEach(ModelSize.allCases, id: \.self) { size in
              Section(header: Text(size.rawValue)) {
                ForEach(ModelInfo.allCases.filter { $0.size == size }, id: \.self) { model in
                  Text(modelDisplayTitle(model)).tag(model)
                }
              }
            }
          }
          .labelsHidden()
          .disabled(isDownloading)
          .frame(maxWidth: 280)
          .onChange(of: settings.config.currentModel) { newModel in
            handleModelChange(newModel)
          }
        } label: {
          Label("Whisper model", systemImage: "waveform")
            .symbolRenderingMode(.hierarchical)
        }

        if isDownloading {
          HStack(spacing: 10) {
            ProgressView(value: downloadProgress, total: 1.0)
            Text("\(Int(downloadProgress * 100))%")
              .font(.caption)
              .foregroundColor(.secondary)
              .monospacedDigit()
              .frame(width: 40, alignment: .trailing)
          }
        }
      } header: {
        Text("Model")
      } footer: {
        Text("Larger models are more accurate but slower and use more memory. Quantized variants (Q5/Q8) reduce memory at a small accuracy cost.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section {
        LabeledContent {
          Picker("", selection: $settings.config.language) {
            ForEach(OutputLanguage.allCases, id: \.self) { lang in
              Text(lang.displayName).tag(lang)
            }
          }
          .labelsHidden()
          .frame(width: 160)
        } label: {
          Label("Language", systemImage: "character.bubble")
            .symbolRenderingMode(.hierarchical)
        }

        LabeledContent {
          Toggle("", isOn: $settings.config.translateToEnglish)
            .labelsHidden()
            .toggleStyle(.switch)
        } label: {
          Label("Translate to English", systemImage: "globe")
            .symbolRenderingMode(.hierarchical)
        }
      } header: {
        Text("Transcription")
      }

      Section {
        LabeledContent {
          Toggle("", isOn: $settings.config.autoUnload.enabled)
            .labelsHidden()
            .toggleStyle(.switch)
        } label: {
          Label("Auto-unload model", systemImage: "memorychip")
            .symbolRenderingMode(.hierarchical)
        }

        if settings.config.autoUnload.enabled {
          LabeledContent {
            HStack(spacing: 8) {
              Text("\(settings.config.autoUnload.timeoutMinutes)")
                .monospacedDigit()
                .frame(minWidth: 28, alignment: .trailing)
              Text("min")
                .foregroundColor(.secondary)
              Stepper("", value: $settings.config.autoUnload.timeoutMinutes, in: 1...10)
                .labelsHidden()
            }
          } label: {
            Label("Idle timeout", systemImage: "timer")
              .symbolRenderingMode(.hierarchical)
          }
        }
      } header: {
        Text("Memory")
      } footer: {
        Text("Unload the model from memory after an idle period to reduce RAM usage. The model reloads on the next recording.")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .onChange(of: settings.config.language) { _ in settings.save() }
    .onChange(of: settings.config.translateToEnglish) { _ in settings.save() }
    .onChange(of: settings.config.autoUnload.enabled) { _ in settings.save() }
    .onChange(of: settings.config.autoUnload.timeoutMinutes) { _ in settings.save() }
    .alert(isPresented: $showDownloadAlert) {
      let modelsPath = AppSettings.modelsDir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
      return Alert(
        title: Text("Download Model?"),
        message: Text(pendingModel.map { "This will download \($0.displayName) to \(modelsPath)/. The download may take a few minutes." } ?? ""),
        primaryButton: .default(Text("Download")) {
          Task {
            if let model = pendingModel, #available(macOS 12.0, *) {
              await downloadModel(model)
            }
          }
        },
        secondaryButton: .cancel {
          if let available = settings.availableModels.first {
            settings.config.currentModel = available
          }
        }
      )
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

  private func handleModelChange(_ newModel: ModelInfo) {
    Task {
      let isAvailable = settings.availableModels.contains(newModel)
      if !isAvailable {
        await MainActor.run {
          pendingModel = newModel
          showDownloadAlert = true
        }
      } else {
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
        let alert = NSAlert()
        alert.messageText = "Download Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
        if let available = settings.availableModels.first {
          settings.config.currentModel = available
        }
      }
    }
  }
}
