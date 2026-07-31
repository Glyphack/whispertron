import Foundation
import os
import Combine

// MARK: - 1. Definitions (Enums & Structs)

enum ModelSize: String, CaseIterable {
    case tiny = "Tiny"
    case base = "Base"
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
}

enum ModelInfo: String, CaseIterable, Codable {
    // Tiny
    case tiny = "ggml-tiny"
    case tinyEn = "ggml-tiny.en"
    case tinyQ5 = "ggml-tiny-q5_1"
    case tinyEnQ5 = "ggml-tiny.en-q5_1"
    case tinyQ8 = "ggml-tiny-q8_0"
    case tinyEnQ8 = "ggml-tiny.en-q8_0"
    // Base
    case base = "ggml-base"
    case baseEn = "ggml-base.en"
    case baseQ5 = "ggml-base-q5_1"
    case baseEnQ5 = "ggml-base.en-q5_1"
    case baseQ8 = "ggml-base-q8_0"
    case baseEnQ8 = "ggml-base.en-q8_0"
    // Small
    case small = "ggml-small"
    case smallEnglish = "ggml-small.en"
    case smallQ5 = "ggml-small-q5_1"
    case smallEnQ5 = "ggml-small.en-q5_1"
    case smallQ8 = "ggml-small-q8_0"
    case smallEnglishQ8 = "ggml-small.en-q8_0"
    // Medium
    case medium = "ggml-medium"
    case mediumEnglish = "ggml-medium.en"
    case mediumQ5 = "ggml-medium-q5_0"
    case mediumEnQ5 = "ggml-medium.en-q5_0"
    case mediumQ8 = "ggml-medium-q8_0"
    case mediumEnglishQ8 = "ggml-medium.en-q8_0"
    // Large
    case largeV1 = "ggml-large-v1"
    case largeV2 = "ggml-large-v2"
    case largeV2Q5 = "ggml-large-v2-q5_0"
    case largeV2Q8 = "ggml-large-v2-q8_0"
    case largeV3 = "ggml-large-v3"
    case largeV3Q5 = "ggml-large-v3-q5_0"
    case largeV3Turbo = "ggml-large-v3-turbo"
    case largeV3TurboQ5 = "ggml-large-v3-turbo-q5_0"
    case largeV3TurboQ8 = "ggml-large-v3-turbo-q8_0"

    var displayName: String {
        switch self {
        case .tiny: return "Tiny"
        case .tinyEn: return "Tiny (English)"
        case .tinyQ5: return "Tiny (Q5)"
        case .tinyEnQ5: return "Tiny (English, Q5)"
        case .tinyQ8: return "Tiny (Q8)"
        case .tinyEnQ8: return "Tiny (English, Q8)"
        case .base: return "Base"
        case .baseEn: return "Base (English)"
        case .baseQ5: return "Base (Q5)"
        case .baseEnQ5: return "Base (English, Q5)"
        case .baseQ8: return "Base (Q8)"
        case .baseEnQ8: return "Base (English, Q8)"
        case .small: return "Small"
        case .smallEnglish: return "Small (English)"
        case .smallQ5: return "Small (Q5)"
        case .smallEnQ5: return "Small (English, Q5)"
        case .smallQ8: return "Small (Q8)"
        case .smallEnglishQ8: return "Small (English, Q8)"
        case .medium: return "Medium"
        case .mediumEnglish: return "Medium (English)"
        case .mediumQ5: return "Medium (Q5)"
        case .mediumEnQ5: return "Medium (English, Q5)"
        case .mediumQ8: return "Medium (Q8)"
        case .mediumEnglishQ8: return "Medium (English, Q8)"
        case .largeV1: return "Large V1"
        case .largeV2: return "Large V2"
        case .largeV2Q5: return "Large V2 (Q5)"
        case .largeV2Q8: return "Large V2 (Q8)"
        case .largeV3: return "Large V3"
        case .largeV3Q5: return "Large V3 (Q5)"
        case .largeV3Turbo: return "Large V3 Turbo"
        case .largeV3TurboQ5: return "Large V3 Turbo (Q5)"
        case .largeV3TurboQ8: return "Large V3 Turbo (Q8)"
        }
    }

    var size: ModelSize {
        switch self {
        case .tiny, .tinyEn, .tinyQ5, .tinyEnQ5, .tinyQ8, .tinyEnQ8: return .tiny
        case .base, .baseEn, .baseQ5, .baseEnQ5, .baseQ8, .baseEnQ8: return .base
        case .small, .smallEnglish, .smallQ5, .smallEnQ5, .smallQ8, .smallEnglishQ8: return .small
        case .medium, .mediumEnglish, .mediumQ5, .mediumEnQ5, .mediumQ8, .mediumEnglishQ8: return .medium
        case .largeV1, .largeV2, .largeV2Q5, .largeV2Q8, .largeV3, .largeV3Q5,
             .largeV3Turbo, .largeV3TurboQ5, .largeV3TurboQ8: return .large
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

enum IconVisibilityMode: String, Codable, CaseIterable {
  case menubar
  case dock

  var displayName: String {
    switch self {
    case .menubar: return "Menubar"
    case .dock: return "Dock"
    }
  }
}

// MARK: - 2. Configuration Object (The JSON Structure)

struct ModelAutoUnloadSettings: Codable {
  var enabled: Bool = false
  var timeoutMinutes: Int = 1
}

struct AppConfiguration: Codable {
    var currentModel: ModelInfo = .smallEnglish
    var language: OutputLanguage = .auto
    var translateToEnglish: Bool = false
    var autoUnload: ModelAutoUnloadSettings = ModelAutoUnloadSettings()
    var maxHistoryEntries: Int = 500
    var iconVisibility: IconVisibilityMode = .menubar
    static let defaults = AppConfiguration()

    enum CodingKeys: String, CodingKey {
        case currentModel, language, translateToEnglish, autoUnload, maxHistoryEntries, iconVisibility
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.currentModel = try c.decodeIfPresent(ModelInfo.self, forKey: .currentModel) ?? .smallEnglish
        self.language = try c.decodeIfPresent(OutputLanguage.self, forKey: .language) ?? .auto
        self.translateToEnglish = try c.decodeIfPresent(Bool.self, forKey: .translateToEnglish) ?? false
        self.autoUnload = try c.decodeIfPresent(ModelAutoUnloadSettings.self, forKey: .autoUnload) ?? ModelAutoUnloadSettings()
        self.maxHistoryEntries = try c.decodeIfPresent(Int.self, forKey: .maxHistoryEntries) ?? 500
        self.iconVisibility = try c.decodeIfPresent(IconVisibilityMode.self, forKey: .iconVisibility) ?? .menubar
    }
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
