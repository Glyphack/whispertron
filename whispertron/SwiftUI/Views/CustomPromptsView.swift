//
//  CustomPromptsView.swift
//  whispertron
//
//  Created by shayegan hooshyari on 12/15/25.
//

import SwiftUI

struct CustomPromptsView: View {
  @ObservedObject var settings: AppSettings
  @State private var apiKeyInput = ""
  @State private var apiKeyStatus = "Status: No API key"
  @State private var selectedPresetID: UUID?
  @State private var showingPresetEditor = false
  @State private var editorMode: PresetEditorMode = .create
  @State private var editingPreset: AIPreset?

  var body: some View {
    HStack(alignment: .top, spacing: 20) {
      apiKeyCard
        .frame(maxWidth: .infinity)

      presetsCard
        .frame(maxWidth: .infinity)
    }
    .padding(30)
    .onAppear {
      Task {
        await loadAPIKey()
      }
    }
    .sheet(isPresented: $showingPresetEditor) {
      PresetEditorView(
        preset: editingPreset,
        mode: editorMode,
        onSave: { preset in
          Task { @MainActor in
            if editorMode == .edit {
              settings.updatePreset(preset)
            } else {
              settings.addPreset(preset)
            }
            showingPresetEditor = false
          }
        },
        onCancel: {
          showingPresetEditor = false
        }
      )
    }
  }

  private var apiKeyCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "key.fill")
          .foregroundColor(.accentColor)
        Text("OpenAI API Key")
          .font(.headline)
      }

      TextField("sk-...", text: $apiKeyInput)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12, design: .monospaced))

      Text(apiKeyStatus)
        .font(.caption)
        .foregroundColor(.secondary)

      HStack {
        Button("Save") {
          Task {
            await saveAPIKey()
          }
        }

        Button("Clear") {
          Task {
            await clearAPIKey()
          }
        }
      }

      Spacer()
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color(NSColor.controlBackgroundColor))
        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
    )
  }

  private var presetsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "wand.and.stars")
          .foregroundColor(.accentColor)
        Text("AI Presets")
          .font(.headline)
      }

      List(selection: $selectedPresetID) {
        ForEach(settings.config.presets) { preset in
          VStack(alignment: .leading, spacing: 4) {
            Text(preset.name)
              .font(.subheadline)
            Text(preset.modelName)
              .font(.caption)
              .foregroundColor(.secondary)
          }
          .tag(preset.id)
        }
      }
      .frame(minHeight: 200)

      HStack {
        Button(action: { createPreset() }) {
          Image(systemName: "plus")
        }

        Button(action: { editPreset() }) {
          Image(systemName: "pencil")
        }
        .disabled(selectedPresetID == nil)

        Button(action: { duplicatePreset() }) {
          Image(systemName: "doc.on.doc")
        }
        .disabled(selectedPresetID == nil)

        Button(action: { deletePreset() }) {
          Image(systemName: "trash")
        }
        .disabled(selectedPresetID == nil)
      }
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color(NSColor.controlBackgroundColor))
        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
    )
  }

  private func loadAPIKey() async {
    if let key = await settings.loadAPIKey() {
      await MainActor.run {
        apiKeyInput = key
        apiKeyStatus = "Status: API key saved"
      }
    } else {
      await MainActor.run {
        apiKeyStatus = "Status: No API key"
      }
    }
  }

  private func saveAPIKey() async {
    do {
      try await settings.saveAPIKey(apiKeyInput)
      await MainActor.run {
        apiKeyStatus = "Status: API key saved"
      }
    } catch {
      await MainActor.run {
        apiKeyStatus = "Status: Failed to save"
      }
    }
  }

  private func clearAPIKey() async {
    do {
      try await settings.deleteAPIKey()
      await MainActor.run {
        apiKeyInput = ""
        apiKeyStatus = "Status: No API key"
      }
    } catch {
      await MainActor.run {
        apiKeyStatus = "Status: Failed to clear"
      }
    }
  }

  private func createPreset() {
    editorMode = .create
    editingPreset = nil
    showingPresetEditor = true
  }

  private func editPreset() {
    guard let id = selectedPresetID,
          let preset = settings.config.presets.first(where: { $0.id == id }) else { return }
    editorMode = .edit
    editingPreset = preset
    showingPresetEditor = true
  }

  private func duplicatePreset() {
    guard let id = selectedPresetID,
          let preset = settings.config.presets.first(where: { $0.id == id }) else { return }
    editorMode = PresetEditorMode.duplicate
    editingPreset = preset
    showingPresetEditor = true
  }

  private func deletePreset() {
    guard let id = selectedPresetID else { return }
    Task {
      settings.deletePreset(id: id)
      await MainActor.run {
        selectedPresetID = nil
      }
    }
  }
}
