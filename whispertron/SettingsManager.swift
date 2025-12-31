import Foundation
import os
import Combine

// MARK: - 1. Definitions (Enums & Structs)

enum ModelInfo: String, CaseIterable, Codable {
    case largeV3Q5 = "ggml-large-v3-q5_0"
    case largeV3 = "ggml-large-v3"
    case mediumQ8 = "ggml-medium-q8_0"
    case mediumEnglish = "ggml-medium.en"
    case mediumEnglishQ8 = "ggml-medium.en-q8_0"
    case smallEnglish = "ggml-small.en"
    case small = "ggml-small"
    case smallQ8 = "ggml-small-q8_0"
    case smallEnglishQ8 = "ggml-small.en-q8_0"
    
    var displayName: String {
        switch self {
        case .largeV3Q5: return "Large V3 (Q5)"
        case .largeV3: return "Large V3"
        case .mediumQ8: return "Medium (Q8)"
        case .mediumEnglish: return "Medium (English)"
        case .mediumEnglishQ8: return "Medium (English, Q8)"
        case .smallEnglish: return "Small (English)"
        case .small: return "Small"
        case .smallQ8: return "Small (Q8)"
        case .smallEnglishQ8: return "Small (English, Q8)"
        }
    }
    
    var isBundled: Bool {
        return self == .smallEnglish
    }
    
    var fileName: String {
        return "\(self.rawValue).bin"
    }
    
    var downloadURL: URL {
        return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)?download=true")!
    }

    func isAvailable(settings: AppSettings) -> Bool {
        return settings.getModelPath(for: self) != nil
    }
}

struct AIPreset: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var systemPrompt: String
    var modelName: String
    var createdAt: Date = Date()
    var lastModified: Date = Date()
}

enum TranscriptionMode: Codable, Equatable, Hashable, CustomStringConvertible {
    case onlyTranscribe
    case aiPreset(UUID) // links to AIPreset.id

    var description: String {
        switch self {
        case .onlyTranscribe:
            return "Only Transcribe"
        case .aiPreset(let id):
            return "AI Preset (\(id))"
        }
    }
}

enum OutputLanguage: String, CaseIterable, Codable {
  case auto = "auto"
  case english = "en"
  case farsi = "fa"
  case dutch = "nl"

  var displayName: String {
    switch self {
    case .auto: return "Auto"
    case .english: return "EN"
    case .farsi: return "FA"
    case .dutch: return "NL"
    }
  }

  var whisperLanguageCode: String? {
    switch self {
    case .auto: return nil
    case .english: return "en"
    case .farsi: return "fa"
    case .dutch: return "nl"
    }
  }
}

// MARK: - 2. Configuration Object (The JSON Structure)

struct ModelAutoUnloadSettings: Codable {
  var enabled: Bool = false
  var timeoutMinutes: Int = 1
}

struct AppConfiguration: Codable {
    var openAIKey: String? = nil
    var currentModel: ModelInfo = .smallEnglish
    var language: OutputLanguage = .auto
    var translateToEnglish: Bool = false
    var transcriptionMode: TranscriptionMode = .onlyTranscribe
    var presets: [AIPreset] = []
    var autoUnload: ModelAutoUnloadSettings = ModelAutoUnloadSettings()

    static let defaults = AppConfiguration(
        openAIKey: nil,
        currentModel: .smallEnglish,
        language: .auto,
        translateToEnglish: false,
        transcriptionMode: .onlyTranscribe,
        presets: [
            AIPreset(
                name: "Grammar Fix",
                systemPrompt: "Fix punctuation and grammar issues. Pay attention to the context of words based on the sentence. Keep the tone casual. Only respond with the fixed punctuation.",
                modelName: "gpt-4.1"
            )
        ],
        autoUnload: ModelAutoUnloadSettings()
    )
}

// MARK: - 3. The Manager Class

class AppSettings: ObservableObject {

    @Published var config: AppConfiguration
    @Published var availableModels: [ModelInfo] = []
    private let logger = Logger(subsystem: "com.glyphack.whispertron", category: "AppSettings")

    init() {
        self.config = AppSettings.loadFromDisk()
        self.updateAvailableModels()
    }

    func updateAvailableModels() {
        availableModels = ModelInfo.allCases.filter { model in
            model.isAvailable(settings: self)
        }
    }
    
    // MARK: - Persistence
    
    private static var appDataDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("whispertron")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    static var modelsDir: URL {
        let dir = appDataDir.appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private static var settingsURL: URL {
        return appDataDir.appendingPathComponent("settings.json")
    }
    
    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: AppSettings.settingsURL)
            logger.info("Settings saved to disk.")
        } catch {
            logger.error("Failed to save settings: \(error.localizedDescription)")
        }
    }
    
    static func loadFromDisk() -> AppConfiguration {
        do {
            let data = try Data(contentsOf: settingsURL)
            return try JSONDecoder().decode(AppConfiguration.self, from: data)
        } catch {
            print("Settings file not found or invalid. Using defaults.")
            return AppConfiguration.defaults
        }
    }
    
    // MARK: - Model Management Logic
    
    /// Returns the absolute filesystem path for a specific model, if it exists.
    func getModelPath(for model: ModelInfo) -> String? {
        if model.isBundled {
            // Check App Bundle
            return Bundle.main.url(forResource: "model", withExtension: "bin", subdirectory: "models")!.path
        } else {
            // Check Application Support
            let fileURL = AppSettings.modelsDir.appendingPathComponent(model.fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL.path
            }
        }
        return nil
    }
    
    /// Returns the absolute filesystem path for the current model.
    /// Falls back to bundled model if current model is not found.
    func getCurrentModelPath() -> String {
        if let path = getModelPath(for: config.currentModel) {
            return path
        }

        // Fallback to bundled model
        logger.warning("Model \(self.config.currentModel.displayName) not found, falling back to bundled model")
        let bundledModel = ModelInfo.smallEnglish
        config.currentModel = bundledModel
        updateAvailableModels()
        save()

        guard let bundledPath = getModelPath(for: bundledModel) else {
            Swift.fatalError("Bundled model not found in app bundle")
        }

        return bundledPath
    }
    
    /// Downloads a model from HuggingFace to the Application Support directory
    @available(macOS 12.0, *)
    func downloadModel(_ model: ModelInfo, progressHandler: @escaping @MainActor (Double) -> Void) async throws {
        guard !model.isBundled else { return }

        let destinationURL = AppSettings.modelsDir.appendingPathComponent(model.fileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            logger.info("Model \(model.displayName) already exists.")
            return
        }

        logger.info("Starting download: \(model.displayName)")

        try await downloadWithProgress(url: model.downloadURL, destination: destinationURL, progressHandler: progressHandler)

        await MainActor.run {
            updateAvailableModels()
        }

        logger.info("Successfully installed model: \(model.displayName)")
    }
    
    /// Internal helper to handle download with progress
    private func downloadWithProgress(url: URL, destination: URL, progressHandler: @escaping @MainActor (Double) -> Void) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            var observation: NSKeyValueObservation?

            let task = URLSession.shared.downloadTask(with: url) { localURL, _, error in
                observation?.invalidate()

                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let localURL = localURL else {
                    continuation.resume(throwing: NSError(domain: "DownloadError", code: -1))
                    return
                }

                do {
                    // Remove existing if needed
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: localURL, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            // Observe progress - keep observation alive
            observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                Task { @MainActor in
                    progressHandler(progress.fractionCompleted)
                }
            }

            task.resume()
        }
    }

    // MARK: - Model Management Methods

    /// Returns all available models (both bundled and downloaded)
    func availableModels() async -> [ModelInfo] {
        return ModelInfo.allCases.filter { model in
            model.isAvailable(settings: self)
        }
    }

    /// Returns the current model from configuration
    func getCurrentModel() async -> ModelInfo {
        return config.currentModel
    }

    /// Sets the current model and saves configuration
    @MainActor
    func setCurrentModel(_ model: ModelInfo) async {
        config.currentModel = model
        save()
        logger.info("Current model set to: \(model.displayName)")
    }

    /// Checks if a model file exists and is available
    func isModelAvailable(_ model: ModelInfo) -> Bool {
        return model.isAvailable(settings: self)
    }

    // MARK: - Model Switching

    /// Switches to a new model by loading its context
    /// - Parameter model: The model to switch to
    /// - Parameter createContext: Callback to create WhisperContext with model path
    /// - Returns: The new WhisperContext
    func switchToModel(
        _ model: ModelInfo,
        createContext: (String) throws -> WhisperContext
    ) async throws -> WhisperContext {
        logger.info("Switching to model: \(model.displayName)")

        guard let modelPath = getModelPath(for: model) else {
            logger.error("Model path not found for \(model.displayName)")
            throw NSError(
                domain: "AppSettings",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Could not find model file for \(model.displayName)"]
            )
        }

        let newContext = try createContext(modelPath)
        await setCurrentModel(model)

        logger.info("Successfully switched to model: \(model.displayName)")
        return newContext
    }

    /// Downloads a model if needed and confirms with user
    /// - Parameter model: The model to download
    /// - Parameter confirmDownload: Callback to show confirmation dialog
    /// - Parameter progressHandler: Progress callback for download
    @available(macOS 12.0, *)
    func downloadModelIfNeeded(
        _ model: ModelInfo,
        confirmDownload: () async -> Bool,
        progressHandler: @escaping @MainActor (Double) -> Void
    ) async throws {
        // Check if already available
        if isModelAvailable(model) {
            return
        }

        logger.info("Model not available, requesting download: \(model.displayName)")

        // Confirm with user
        let shouldDownload = await confirmDownload()
        guard shouldDownload else {
            throw NSError(
                domain: "AppSettings",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Download cancelled by user"]
            )
        }

        // Download the model
        try await downloadModel(model, progressHandler: progressHandler)
        logger.info("Model download completed: \(model.displayName)")
    }

    // MARK: - Settings Management Methods

    /// Sets the transcription mode with validation
    @MainActor
    func setTranscriptionMode(_ mode: TranscriptionMode) throws {
        // Validate that preset exists if using aiPreset mode
        if case .aiPreset(let presetId) = mode {
            guard config.presets.contains(where: { $0.id == presetId }) else {
                throw NSError(
                    domain: "AppSettings",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Preset with ID \(presetId) not found"]
                )
            }
        }
        config.transcriptionMode = mode
        save()
        logger.info("Transcription mode updated")
    }

    /// Returns a preset by ID
    func preset(for id: UUID) -> AIPreset? {
        return config.presets.first(where: { $0.id == id })
    }

    /// Adds a new preset
    @MainActor
    func addPreset(_ preset: AIPreset) {
        config.presets.append(preset)
        save()
        logger.info("Preset added: \(preset.name)")
    }

    /// Updates an existing preset
    @MainActor
    func updatePreset(_ preset: AIPreset) {
        if let index = config.presets.firstIndex(where: { $0.id == preset.id }) {
            config.presets[index] = preset
            save()
            logger.info("Preset updated: \(preset.name)")
        }
    }

    /// Deletes a preset by ID
    @MainActor
    func deletePreset(id: UUID) {
        config.presets.removeAll(where: { $0.id == id })

        // If the deleted preset was active, switch to local only
        if case .aiPreset(let presetId) = config.transcriptionMode, presetId == id {
            config.transcriptionMode = .onlyTranscribe
            logger.info("Active preset deleted, switching to local only mode")
        }

        save()
        logger.info("Preset deleted")
    }

    @MainActor
    func setOutputLanguage(_ language: OutputLanguage) {
        config.language = language
        save()
        logger.info("language set to: \(language.displayName)")
    }

    @MainActor
    func setTranslateToEnglish(_ translate: Bool) {
        config.translateToEnglish = translate
        save()
        logger.info("Translate to English: \(translate)")
    }

    // MARK: - Keychain Methods for API Key

    private static let keychainService = "com.glyphack.whispertron"
    private static let keychainAccount = "openai-api-key"

    /// Checks if an API key exists in the Keychain
    func hasAPIKey() async -> Bool {
        return await loadAPIKey() != nil
    }

    /// Loads the API key from the Keychain
    func loadAPIKey() async -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppSettings.keychainService,
            kSecAttrAccount as String: AppSettings.keychainAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    /// Saves the API key to the Keychain
    func saveAPIKey(_ key: String) async throws {
        // Delete existing key first
        try? await deleteAPIKey()

        guard let data = key.data(using: .utf8) else {
            throw NSError(
                domain: "AppSettings",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode API key"]
            )
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppSettings.keychainService,
            kSecAttrAccount as String: AppSettings.keychainAccount,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw NSError(
                domain: "AppSettings",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to save API key to Keychain (status: \(status))"]
            )
        }

        logger.info("API key saved to Keychain")
    }

    /// Deletes the API key from the Keychain
    func deleteAPIKey() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppSettings.keychainService,
            kSecAttrAccount as String: AppSettings.keychainAccount
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Success or item not found are both acceptable
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(
                domain: "AppSettings",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to delete API key from Keychain (status: \(status))"]
            )
        }

        logger.info("API key deleted from Keychain")
    }

    // MARK: - Reset Settings

    /// Resets all settings to their default values and saves to disk
    @MainActor
    func resetToDefaults() async {
        objectWillChange.send()
        config = AppConfiguration.defaults
        save()
        logger.info("Settings reset to defaults")
    }
}
