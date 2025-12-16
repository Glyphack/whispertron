//
//  PresetEditorView.swift
//  whispertron
//
//  Created by shayegan hooshyari on 12/15/25.
//

import SwiftUI

struct PresetEditorView: View {
  let mode: PresetEditorMode
  let preset: AIPreset?
  let onSave: (AIPreset) -> Void
  let onCancel: () -> Void

  @State private var name: String
  @State private var systemPrompt: String
  @State private var modelName: String

  init(preset: AIPreset?, mode: PresetEditorMode, onSave: @escaping (AIPreset) -> Void, onCancel: @escaping () -> Void) {
    self.preset = preset
    self.mode = mode
    self.onSave = onSave
    self.onCancel = onCancel

    _name = State(initialValue: preset?.name ?? "")
    _systemPrompt = State(initialValue: preset?.systemPrompt ?? "")
    _modelName = State(initialValue: preset?.modelName ?? "gpt-4.1")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Image(systemName: "wand.and.stars")
          .foregroundColor(.accentColor)
        Text(titleText)
          .font(.headline)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Preset Name")
          .font(.subheadline)
          .foregroundColor(.secondary)
        TextField("Enter preset name", text: $name)
          .textFieldStyle(.roundedBorder)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("OpenAI Model")
          .font(.subheadline)
          .foregroundColor(.secondary)
        Picker("", selection: $modelName) {
          Text("gpt-4.1").tag("gpt-4.1")
          Text("gpt-4o").tag("gpt-4o")
          Text("gpt-4o-mini").tag("gpt-4o-mini")
        }
        .pickerStyle(.segmented)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("System Prompt")
          .font(.subheadline)
          .foregroundColor(.secondary)
        TextEditor(text: $systemPrompt)
          .font(.system(size: 12, design: .monospaced))
          .frame(height: 200)
          .border(Color.gray.opacity(0.3), width: 1)
      }

      HStack {
        Spacer()
        Button("Cancel") {
          onCancel()
        }
        .keyboardShortcut(.cancelAction)

        Button("Save") {
          savePreset()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(name.isEmpty || systemPrompt.isEmpty)
      }
    }
    .padding()
    .frame(width: 550, height: 480)
  }

  private var titleText: String {
    switch mode {
    case .create: return "Create New AI Preset"
    case .edit: return "Edit AI Preset"
    case .duplicate: return "Duplicate AI Preset"
    }
  }

  private func savePreset() {
    let newPreset = AIPreset(
      id: mode == .edit ? (preset?.id ?? UUID()) : UUID(),
      name: name,
      systemPrompt: systemPrompt,
      modelName: modelName
    )
    onSave(newPreset)
  }
}
