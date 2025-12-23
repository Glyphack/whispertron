import AVFoundation
import ApplicationServices
@preconcurrency import AppKit
@preconcurrency import Cocoa
import CoreGraphics
import Foundation
import HotKey
import KeyboardShortcuts
import SwiftUI
import os

enum FeedbackState: Equatable {
  case recording
  case transcribing
  case loading
  case downloading(progress: Double)
}

@MainActor
class FeedbackViewModel: ObservableObject {
  @Published var state: FeedbackState = .recording
  @Published var audioLevel: Float = 0
  @Published var recordingStartTime: Date? = nil
  @Published var recordingDuration: TimeInterval = 0
}

extension NSColor {
  convenience init(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let a, r, g, b: UInt64
    switch hex.count {
    case 3: // RGB (12-bit)
      (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
    case 6: // RGB (24-bit)
      (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
    case 8: // ARGB (32-bit)
      (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
    default:
      (a, r, g, b) = (1, 1, 1, 0)
    }
    
    self.init(
      red: CGFloat(r) / 255,
      green: CGFloat(g) / 255,
      blue: CGFloat(b) / 255,
      alpha: CGFloat(a) / 255
    )
  }
  
  static var isDarkMode: Bool {
    return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
  }
}

// MARK: - Model Auto-Unload

protocol ModelAutoUnloadDelegate: AnyObject {
  var whisperContext: WhisperContext? { get set }
  var recorder: Recorder? { get set }
  func showFeedback(_ state: FeedbackState?)
  func showError(_ message: String)
}

@MainActor
class ModelAutoUnloadManager {
  // MARK: - Properties
  private var timer: Timer?
  private var lastTranscriptionTime: Date?
  private var isReloading = false

  private weak var delegate: ModelAutoUnloadDelegate?
  private let settings: AppSettings
  private let logger: Logger

  private var config: ModelAutoUnloadSettings {
    settings.config.autoUnload
  }

  private var isModelLoaded: Bool {
    delegate?.whisperContext != nil
  }

  // MARK: - Initialization
  init(settings: AppSettings, delegate: ModelAutoUnloadDelegate, logger: Logger) {
    self.settings = settings
    self.delegate = delegate
    self.logger = logger
  }

  // MARK: - Public Methods

  func scheduleUnload() {
    // Cancel any existing timer
    timer?.invalidate()
    timer = nil

    guard config.enabled else { return }
    guard isModelLoaded else { return }

    lastTranscriptionTime = Date()
    let timeoutSeconds = TimeInterval(config.timeoutMinutes * 60)

    logger.info("Scheduling model unload in \(timeoutSeconds) seconds")

    timer = Timer.scheduledTimer(withTimeInterval: timeoutSeconds, repeats: false) { [weak self] _ in
      guard let self = self else { return }
      Task { @MainActor in
        await self.unloadIfIdle()
      }
    }
  }

  func ensureModelLoaded(
    getCurrentModelPath: () -> String,
    createContext: (String) throws -> WhisperContext,
    createRecorder: (WhisperContext) async throws -> Recorder
  ) async throws {
    guard let delegate = delegate else { return }
    guard !isModelLoaded else { return }

    guard !isReloading else {
      throw NSError(
        domain: "ModelAutoUnload",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Model reload already in progress"]
      )
    }

    isReloading = true
    defer { isReloading = false }

    logger.info("Reloading model...")
    delegate.showFeedback(.loading)

    do {
      let modelPath = getCurrentModelPath()
      let context = try createContext(modelPath)
      delegate.whisperContext = context
      delegate.recorder = try await createRecorder(context)

      logger.info("Model reloaded successfully")
      delegate.showFeedback(nil)

      // Automatically schedule unload after model is loaded
      scheduleUnload()
    } catch {
      logger.error("Failed to reload model: \(error.localizedDescription)")
      delegate.showFeedback(nil)
      throw error
    }
  }

  func handleSleep() {
    logger.info("System going to sleep - cancelling model unload timer")
    timer?.invalidate()
    timer = nil
  }

  func handleWake() {
    logger.info("System woke up - rescheduling model unload")
    scheduleUnload()
  }

  // MARK: - Private Methods

  private func unloadIfIdle() async {
    guard let delegate = delegate else { return }
    guard let lastTranscription = lastTranscriptionTime else { return }

    let timeoutSeconds = TimeInterval(config.timeoutMinutes * 60)
    let elapsed = Date().timeIntervalSince(lastTranscription)

    guard elapsed >= timeoutSeconds else {
      logger.info("Model unload cancelled - activity detected")
      return
    }

    // Don't unload if currently recording
    if await delegate.recorder?.getIsRecording() == true {
      logger.info("Model unload skipped - recording in progress")
      scheduleUnload() // Reschedule
      return
    }

    logger.info("Unloading model after \(Int(elapsed)) seconds of inactivity")

    // Unload model - deinit will automatically call whisper_free()
    delegate.whisperContext = nil
    delegate.recorder = nil

    logger.info("Model unloaded successfully")
  }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, ModelAutoUnloadDelegate {
  // MARK: - Properties

  private var statusItem: NSStatusItem!
  private var recordMenuItem: NSMenuItem!
  var whisperContext: WhisperContext?
  var recorder: Recorder?
  private var settingsManager: AppSettings = AppSettings()
  private var openAIClient: OpenAIClient!
  private var preferencesWindow: NSWindow?
  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")
  private let standbyImage: NSImage = {
    let image = NSImage(systemSymbolName: "music.mic", accessibilityDescription: "Standby")!
    image.isTemplate = true
    return image
  }()
  private let recordingImage: NSImage = {
    let image = NSImage(systemSymbolName: "music.mic", accessibilityDescription: "Recording")!
    image.isTemplate = true
    return image
  }()

  private let windowSize: CGFloat = 200.0
  private let darkFg = NSColor(hex: "CCCCCC")
  private let lightFg = NSColor(hex: "333333")

  private var feedbackWindow: NSWindow?
  private var feedbackViewModel: FeedbackViewModel?
  private var lastTranscript = ""
  private let MinimumTranscriptionDuration = 1.0
  private var audioLevelTimer: Timer?
  private var autoUnloadManager: ModelAutoUnloadManager!
  private var historyManager = HistoryManager()
  private var historyWindow: NSWindow?

  // MARK: - Lifecycle

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(refreshMenuBar),
      name: NSNotification.Name("RefreshMenuBar"),
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSystemSleep),
      name: NSWorkspace.willSleepNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSystemWake),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )

    KeyboardShortcuts.onKeyDown(for: .toggleRecording) { [weak self] in
      self?.startRecording()
    }

    KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
      self?.Transcribe()
    }

    KeyboardShortcuts.onKeyDown(for: .toggleRecordingButton) { [weak self] in
      self?.didTapRecord()
    }

    setupFeedbackWindow()

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = standbyImage

    settingsManager = AppSettings()
    openAIClient = OpenAIClient(settingsManager: settingsManager)
    autoUnloadManager = ModelAutoUnloadManager(
      settings: settingsManager,
      delegate: self,
      logger: logger
    )

    setupMenus()
    setupApplicationMenu()

    Task {
      do {
        let modelPath = settingsManager.getCurrentModelPath()

        self.whisperContext = try WhisperContext.createContext(path: modelPath)
        self.recorder = try await Recorder(whisperContext: self.whisperContext!)

        DispatchQueue.main.async {
          if !self.checkAccessibilityPermissions() {
            self.promptForAccessibilityPermissions()
          }
        }
      } catch {
        logger.error("Error creating Whisper context: \(error.localizedDescription)")
      }
    }

      autoUnloadManager.scheduleUnload()
  }

  // MARK: - Accessibility

  private func checkAccessibilityPermissions() -> Bool {
    let trusted = AXIsProcessTrusted()
    if trusted {
      logger.info("Accessibility permissions granted")
    } else {
      logger.warning("Accessibility permissions NOT granted")
    }
    return trusted
  }

  private func promptForAccessibilityPermissions() {
    let alert = NSAlert()
    alert.messageText = "Accessibility Permission Required"
    alert.informativeText = """
    Whispertron needs Accessibility permission to insert transcribed text into other applications.

    To grant permission:
    1. Open System Settings
    2. Go to Privacy & Security > Accessibility
    3. Enable Whispertron
    4. Restart the app

    Would you like to open System Settings now?
    """
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Later")

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
      }
    }
  }

  // MARK: - System Sleep/Wake Handling

  @objc func handleSystemSleep() {
    Task { @MainActor in
      autoUnloadManager.handleSleep()
    }
  }

  @objc func handleSystemWake() {
    Task { @MainActor in
      autoUnloadManager.handleWake()
    }
  }

  // MARK: - Transcription

  func insertStringAtCursor(_ string: String) async -> Bool {
    logger.info("Attempting to insert text: \"\(string)\"")

    if !checkAccessibilityPermissions() {
      return false
    }

    return await MainActor.run {
      // Copy text to clipboard
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(string, forType: .string)

      // Simulate Cmd+V
      let vKeyCode: CGKeyCode = 0x09
      guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
        self.logger.error("Failed to create CGEvent for Cmd+V")
        return false
      }

      keyDown.flags = .maskCommand
      keyUp.flags = .maskCommand

      keyDown.post(tap: .cghidEventTap)
      usleep(1000)
      keyUp.post(tap: .cghidEventTap)

      self.logger.info("Text insertion via clipboard completed")
      return true
    }
  }


  // MARK: - Feedback UI

  @MainActor
  func setupFeedbackWindow() {
    feedbackWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: windowSize, height: windowSize),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false)

    feedbackWindow?.level = .floating
    feedbackWindow?.isOpaque = false
    feedbackWindow?.backgroundColor = NSColor.clear
    feedbackWindow?.hasShadow = false
    feedbackWindow?.ignoresMouseEvents = true

    // Create SwiftUI view with observable state
    feedbackViewModel = FeedbackViewModel()
    let feedbackView = FeedbackView(viewModel: feedbackViewModel!)
    let hostingController = NSHostingController(rootView: feedbackView)
    feedbackWindow?.contentViewController = hostingController
  }

  func showFeedback(_ state: FeedbackState?) {
    Task { @MainActor in
      guard let viewModel = self.feedbackViewModel else { return }

      if let state = state {
        if let screen = NSScreen.main {
          let screenFrame = screen.visibleFrame
          let centerX = screenFrame.midX - (windowSize / 2)
          let centerY: CGFloat = 140.0
          self.feedbackWindow?.setFrameOrigin(NSPoint(x: centerX, y: centerY))
        }

        // Update SwiftUI view model state
        viewModel.state = state

        // Handle audio level pulsing and timer
        switch state {
        case .recording:
          // Initialize timer on first recording
          if viewModel.recordingStartTime == nil {
            viewModel.recordingStartTime = Date()
            viewModel.recordingDuration = 0
          }
          self.startAudioLevelPulsing()

        case .transcribing:
          // Keep timer running but stop audio level updates
          viewModel.audioLevel = 0
          // Timer continues via existing timer (don't stop it)

        case .loading:
          // Stop audio level updates for loading state
          self.stopAudioLevelPulsing()

        case .downloading:
          self.stopAudioLevelPulsing()
        }

        self.feedbackWindow?.makeKeyAndOrderFront(nil)
      } else {
        // Reset timer when closing
        viewModel.recordingStartTime = nil
        viewModel.recordingDuration = 0
        self.stopAudioLevelPulsing()
        self.feedbackWindow?.orderOut(nil)
      }
    }
  }

  private func startAudioLevelPulsing() {
    audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.0333, repeats: true) { [weak self] _ in
      guard let self = self, let recorder = self.recorder else { return }

      Task { @MainActor in
        let audioLevel = await recorder.getAudioLevel()
        self.feedbackViewModel?.audioLevel = audioLevel

        // Update recording duration if timer is running
        if let startTime = self.feedbackViewModel?.recordingStartTime {
          self.feedbackViewModel?.recordingDuration = Date().timeIntervalSince(startTime)
        }
      }
    }
  }

  private func stopAudioLevelPulsing() {
    audioLevelTimer?.invalidate()
    audioLevelTimer = nil
    Task { @MainActor in
      self.feedbackViewModel?.audioLevel = 0
    }
  }

  func showError(_ message: String) {
    logger.error("Error: \(message)")
    Task { @MainActor in
      let alert = NSAlert()
      alert.messageText = "Error"
      alert.informativeText = message
      alert.alertStyle = .critical
      alert.addButton(withTitle: "OK")
      alert.runModal()
    }
  }

  // MARK: - Menu Management

  func setupMenus() {
    let menu = NSMenu()
    menu.delegate = self

    menu.addItem(NSMenuItem.separator())

    // Add Preferences menu item
    let preferences = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
    menu.addItem(preferences)

    menu.addItem(NSMenuItem.separator())

    // Add Transcription Mode submenu
    let transcriptionModeMenuItem = NSMenuItem(title: "Transcription Mode", action: nil, keyEquivalent: "")
    let transcriptionModeSubmenu = NSMenu()
    transcriptionModeMenuItem.submenu = transcriptionModeSubmenu
    menu.addItem(transcriptionModeMenuItem)

    menu.addItem(NSMenuItem.separator())

    // Add Models submenu
    let modelsMenuItem = NSMenuItem(title: "Models", action: nil, keyEquivalent: "")
    let modelsSubmenu = NSMenu()

    for model in ModelInfo.allCases {
      let modelItem = NSMenuItem(
        title: model.displayName,
        action: #selector(didSelectModel(_:)),
        keyEquivalent: ""
      )
      modelItem.representedObject = model
      modelsSubmenu.addItem(modelItem)
    }

    modelsMenuItem.submenu = modelsSubmenu
    menu.addItem(modelsMenuItem)

    menu.addItem(NSMenuItem.separator())

    let languageMenuItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
    let languageSubmenu = NSMenu()

    for language in OutputLanguage.allCases {
      let languageItem = NSMenuItem(
        title: language.displayName,
        action: #selector(didSelectLanguage(_:)),
        keyEquivalent: ""
      )
      languageItem.representedObject = language
      languageSubmenu.addItem(languageItem)
    }

    languageMenuItem.submenu = languageSubmenu
    menu.addItem(languageMenuItem)

    // Add Translate to English toggle
    let translateItem = NSMenuItem(
      title: "Translate to English",
      action: #selector(toggleTranslateToEnglish(_:)),
      keyEquivalent: ""
    )
    let translateSetting = settingsManager.config.translateToEnglish
    translateItem.state = translateSetting ? .on : .off
    menu.addItem(translateItem)

    menu.addItem(NSMenuItem.separator())

    let historyItem = NSMenuItem(title: "History...", action: #selector(openHistory), keyEquivalent: "h")
    menu.addItem(historyItem)

    recordMenuItem = NSMenuItem(title: "Record", action: #selector(didTapRecord), keyEquivalent: "")
    menu.addItem(recordMenuItem)

    menu.addItem(NSMenuItem.separator())

    menu.addItem(
      NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
      
      let about = NSMenuItem(title: "About", action: #selector(openAbout), keyEquivalent: "")
      menu.addItem(about)

    statusItem.menu = menu

    // Update menu to reflect current model, language, and transcription mode
    updateModelMenuSelection()
    updateLanguageMenuSelection()
    updateTranscriptionModeSelection()
  }

  func setupApplicationMenu() {
    let mainMenu = NSMenu()

    // Application Menu
    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(NSMenuItem(title: "About Whispertron", action: #selector(openAbout), keyEquivalent: ""))
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(NSMenuItem(title: "Hide Whispertron", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
    appMenu.addItem(NSMenuItem(title: "Quit Whispertron", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    // Edit Menu with First Responder pattern
    let editMenuItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

    NSApp.mainMenu = mainMenu
  }

  @objc func openAccessibilitySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
      logger.info("Opened Accessibility settings")
    }
  }

  private func updateModelMenuSelection() {
    guard let menu = statusItem.menu,
          let modelsMenuItem = menu.item(withTitle: "Models"),
          let modelsSubmenu = modelsMenuItem.submenu else {
      return
    }

    Task {
        let currentModel = settingsManager.config.currentModel

      DispatchQueue.main.async {
        for item in modelsSubmenu.items {
          if let model = item.representedObject as? ModelInfo {
            item.state = model == currentModel ? .on : .off

            Task {
                let isAvailable = self.settingsManager.getModelPath(for: model) != nil
              DispatchQueue.main.async {
                 if isAvailable == true {
                  item.title = "\(model.displayName)"
                } else {
                  item.title = "\(model.displayName) (download)"
                }
              }
            }
          }
        }
      }
    }
  }

  private func updateLanguageMenuSelection() {
    guard let menu = statusItem.menu,
          let languageMenuItem = menu.item(withTitle: "Language"),
          let languageSubmenu = languageMenuItem.submenu else {
      return
    }

    let currentLanguage = settingsManager.config.language
    for item in languageSubmenu.items {
      if let language = item.representedObject as? OutputLanguage {
        item.state = language == currentLanguage ? .on : .off
      }
    }
  }

  @objc func didSelectLanguage(_ sender: NSMenuItem) {
    guard let language = sender.representedObject as? OutputLanguage else {
      return
    }

    Task {
      await MainActor.run {
        settingsManager.setOutputLanguage(language)
      }
      await MainActor.run {
        self.updateLanguageMenuSelection()
      }
      logger.info("language changed to: \(language.displayName)")
    }
  }

  @objc func toggleTranslateToEnglish(_ sender: NSMenuItem) {
    Task {
      let currentSetting = settingsManager.config.translateToEnglish
      await MainActor.run {
        settingsManager.setTranslateToEnglish(!currentSetting)
      }
      let newSetting = settingsManager.config.translateToEnglish
      sender.state = newSetting ? .on : .off
      logger.info("Translate to English: \(newSetting ? "enabled" : "disabled")")
    }
  }

  @objc func openAbout() {
    if let url = URL(string: "https://github.com/Glyphack/whispertron") {
      NSWorkspace.shared.open(url)
    }
  }

  // MARK: - Model Management

  @objc func didSelectModel(_ sender: NSMenuItem) {
      guard let model = sender.representedObject as? ModelInfo else {
        return
      }

      Task {
        let currentModel = settingsManager.config.currentModel

        // Don't switch if already using this model
        if model == currentModel {
          return
        }

        // Check if model is available
        let isAvailable = settingsManager.isModelAvailable(model)

        if isAvailable == true {
          // Model is available, switch to it
          await switchModel(to: model)
        } else {
          // Model needs to be downloaded
          if #available(macOS 12.0, *) {
            await downloadAndSwitchModel(to: model)
          } else {
            // On older macOS versions, show an error
            await MainActor.run {
              self.showAlert(
                title: "Download Not Available",
                message: "Model downloading requires macOS 12.0 or later. Please upgrade your system or manually download the model."
              )
            }
          }
        }
      }
    }

  private func switchModel(to model: ModelInfo) async {
    do {
      // Stop recording if active
      if await recorder?.getIsRecording() == true {
        await recorder?.stopRecording()
      }

      // Show loading feedback
      showFeedback(.transcribing)

      // Use SettingsManager to switch models
      self.whisperContext = try await settingsManager.switchToModel(model) { path in
        return try WhisperContext.createContext(path: path)
      }

      // Recreate recorder with new context
      self.recorder = try await Recorder(whisperContext: self.whisperContext!)

      // Update menu
      await MainActor.run {
        self.updateModelMenuSelection()
        self.showFeedback(nil)
      }

      logger.info("Successfully switched to model: \(model.displayName)")

      // Schedule auto-unload for new model
      await autoUnloadManager.scheduleUnload()

    } catch {
      logger.error("Error switching model: \(error.localizedDescription)")
      showFeedback(nil)
      showAlert(title: "Model Switch Failed", message: error.localizedDescription)
    }
  }

  @available(macOS 12.0, *)
  private func downloadAndSwitchModel(to model: ModelInfo) async {
    do {
      // Use SettingsManager to download the model
      try await settingsManager.downloadModelIfNeeded(
        model,
        confirmDownload: { await self.confirmDownload(for: model) },
        progressHandler: { @MainActor progress in
          self.showFeedback(.downloading(progress: progress))
          self.logger.info("Download progress: \(Int(progress * 100))%")
        }
      )

      logger.info("Download completed for \(model.displayName)")

      // Switch to the newly downloaded model
      await switchModel(to: model)

    } catch {
      logger.error("Error downloading model: \(error.localizedDescription)")
      showFeedback(nil)
      showAlert(title: "Download Failed", message: error.localizedDescription)
    }
  }

  private func confirmDownload(for model: ModelInfo) async -> Bool {
    return await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        let alert = NSAlert()
        alert.messageText = "Download \(model.displayName)?"
        let modelsPath = AppSettings.modelsDir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        alert.informativeText = "This will download the model to \(modelsPath)/. The download may take a few minutes depending on your internet connection."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        continuation.resume(returning: response == .alertFirstButtonReturn)
      }
    }
  }

  private func showAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  // MARK: - Audio & Recording

  @objc func Transcribe() {
    logger.debug("didTapStandby")
    showFeedback(.transcribing)
    statusItem.button?.image = standbyImage
    statusItem.button?.cell?.isHighlighted = false

    Task {
      // Wait for trailing buffer to capture any remaining audio
      let trailingMs = settingsManager.config.trailingBufferMs
      if trailingMs > 0 {
        try? await Task.sleep(nanoseconds: UInt64(trailingMs) * 1_000_000)
      }

      await recorder!.stopRecording()
      let duration = await recorder!.recordedDurationSeconds()
      logger.info("Recording stopped. Duration: \(String(format: "%.2f", duration))s")

      if duration > MinimumTranscriptionDuration {
        let outputLang = settingsManager.config.language
        let translate = settingsManager.config.translateToEnglish
        let transcript = await recorder!.transcribe(language: outputLang.whisperLanguageCode, translate: translate)
        logger.info("Transcription completed: \"\(transcript)\"")

        let finalText = await processTranscript(transcript)
        historyManager.addItem(finalText)

        logger.info("Inserting text into cursor position: \"\(finalText)\"")
        let insertionSucceeded = await self.insertStringAtCursor(finalText)
        if !insertionSucceeded {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(finalText, forType: .string)
            showError("Could not paste text at cursor. The transcription has been copied to clipboard instead. Please paste it manually (⌘V).")

        }
      } else {
          showError("Recording too short (\(String(format: "%.2f", duration))s), copying previous transcript to clipboard: \"\(self.lastTranscript)\"")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(self.lastTranscript, forType: .string)
      }

      await MainActor.run {
        self.recordMenuItem.title = "Record"
      }
      await autoUnloadManager.scheduleUnload()
      showFeedback(nil)
    }
  }

  @objc func startRecording() {
    statusItem.button?.image = recordingImage
    statusItem.button?.appearsDisabled = false
    statusItem.button?.cell?.isHighlighted = true

    Task {
      do {
        // Ensure model is loaded before starting recording
        // This will show .loading feedback if model needs to be loaded
        try await autoUnloadManager.ensureModelLoaded(
          getCurrentModelPath: { self.settingsManager.getCurrentModelPath() },
          createContext: { path in try WhisperContext.createContext(path: path) },
          createRecorder: { context in try await Recorder(whisperContext: context) }
        )

        // After model is loaded, show recording feedback and start recording
        await MainActor.run {
          showFeedback(.recording)
        }

        try await recorder?.startRecording()
        await MainActor.run {
          recordMenuItem.title = "Stop Recording"
        }
      } catch {
        logger.error("Error starting recording: \(error.localizedDescription)")

        let alert = NSAlert()
        alert.messageText = "Recording Failed"
        alert.informativeText = "Could not start recording: \(error.localizedDescription)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()

        // Reset UI
        statusItem.button?.image = standbyImage
        statusItem.button?.cell?.isHighlighted = false
        showFeedback(nil)
      }
    }
  }

  @objc func didTapRecord() {
    if recordMenuItem.title == "Stop Recording" {
      Transcribe()
    } else {
      startRecording()
    }
  }

  // MARK: - Preferences

  @objc func openPreferences() {
    if preferencesWindow == nil {
      let preferencesView = PreferencesView(settings: settingsManager)
      let hostingController = NSHostingController(rootView: preferencesView)

      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 550),
        styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      window.title = "Preferences"
      window.contentViewController = hostingController
      window.delegate = self
      window.isReleasedWhenClosed = false

      preferencesWindow = window
    }

    // Center window every time it's opened
    preferencesWindow?.center()

    // Activate app and make window key to enable paste operations
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    preferencesWindow?.makeKeyAndOrderFront(nil)
  }

  @objc func openHistory() {
    print("[AppDelegate] openHistory called")
    historyManager.debugPrint()
    if historyWindow == nil {
      print("[AppDelegate] Creating new history window")
      let historyView = HistoryView(historyManager: historyManager)
      let hostingController = NSHostingController(rootView: historyView)

      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false
      )
      window.title = "Transcription History"
      window.contentViewController = hostingController
      window.delegate = self
      window.isReleasedWhenClosed = false

      historyWindow = window
    }

    historyWindow?.center()
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    historyWindow?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }

    if window == preferencesWindow {
      NSApp.setActivationPolicy(.accessory)
      NotificationCenter.default.post(name: NSNotification.Name("RefreshMenuBar"), object: nil)
    } else if window == historyWindow {
      NSApp.setActivationPolicy(.accessory)
    }
  }

  @objc func refreshMenuBar() {
    // Refresh all menu items when preferences change
    updateModelMenuSelection()
    updateLanguageMenuSelection()
    updateTranscriptionModeSelection()
  }

  // MARK: - Transcription Mode

  private func updateTranscriptionModeSelection() {
    guard let menu = statusItem.menu,
          let transcriptionModeMenuItem = menu.item(withTitle: "Transcription Mode"),
          let transcriptionModeSubmenu = transcriptionModeMenuItem.submenu else {
      return
    }

    Task {
      let currentMode = settingsManager.config.transcriptionMode
      let presets = settingsManager.config.presets
      await updateTranscriptionModeMenu(transcriptionModeSubmenu, currentMode: currentMode, presets: presets)
    }
  }

  @MainActor
  private func updateTranscriptionModeMenu(
    _ submenu: NSMenu,
    currentMode: TranscriptionMode,
    presets: [AIPreset]
  ) {
    // Clear existing items
    submenu.removeAllItems()

    // Add "Local Only" option
    let localOnlyItem = NSMenuItem(
      title: "Local Only",
      action: #selector(didSelectTranscriptionMode(_:)),
      keyEquivalent: ""
    )
    localOnlyItem.representedObject = TranscriptionMode.onlyTranscribe
    localOnlyItem.state = currentMode == .onlyTranscribe ? .on : .off
    submenu.addItem(localOnlyItem)

    if !presets.isEmpty {
      submenu.addItem(NSMenuItem.separator())

      // Add AI presets
      for preset in presets {
        let presetItem = NSMenuItem(
          title: preset.name,
          action: #selector(didSelectTranscriptionMode(_:)),
          keyEquivalent: ""
        )
        presetItem.representedObject = TranscriptionMode.aiPreset(preset.id)

        // Check if this preset is the current mode
        if case .aiPreset(let currentPresetId) = currentMode, currentPresetId == preset.id {
          presetItem.state = .on
        } else {
          presetItem.state = .off
        }

        submenu.addItem(presetItem)
      }
    }
  }

  @objc func didSelectTranscriptionMode(_ sender: NSMenuItem) {
    guard let mode = sender.representedObject as? TranscriptionMode else {
      return
    }

    Task {
      do {
        try await MainActor.run {
          try settingsManager.setTranscriptionMode(mode)
        }
        await MainActor.run {
          self.updateTranscriptionModeSelection()
        }
        logger.info("Transcription mode changed to: \(mode)")
      } catch {
        await MainActor.run {
          self.showAlert(
            title: "Error",
            message: "Failed to set transcription mode: \(error.localizedDescription)"
          )
        }
      }
    }
  }

  // MARK: - OpenAI Processing

  private func processTranscript(_ transcript: String) async -> String {
    let currentMode = settingsManager.config.transcriptionMode

    // If local only mode, return transcript as-is
    guard case .aiPreset(let presetId) = currentMode else {
      return transcript
    }

    // Get the preset
    guard let preset = settingsManager.preset(for: presetId) else {
      logger.error("Preset not found: \(presetId)")
      await MainActor.run {
        self.showAlert(
          title: "Preset Not Found",
          message: "The selected AI preset could not be found. Switching to Local Only mode."
        )
      }
      // Fall back to local only
      try? await MainActor.run {
        try settingsManager.setTranscriptionMode(.onlyTranscribe)
      }
      return transcript
    }

    // Check if API key is configured
    guard await settingsManager.hasAPIKey() else {
      logger.error("No API key configured")
      await MainActor.run {
        self.showAlert(
          title: "API Key Required",
          message: "Please configure your OpenAI API key in Preferences to use AI presets."
        )
      }
      return transcript
    }

    // Show processing feedback
    await MainActor.run {
      self.showFeedback(.transcribing)
    }

    do {
      logger.info("Processing transcript with OpenAI preset: \(preset.name)")
      let processedText = try await openAIClient.processText(
        transcript: transcript,
        systemPrompt: preset.systemPrompt,
        model: preset.modelName
      )
      logger.info("OpenAI processing completed successfully")
      return processedText
    } catch {
      logger.error("OpenAI processing failed: \(error.localizedDescription)")
      await MainActor.run {
        self.handleOpenAIError(error)
      }
      // Return original transcript on error
      return transcript
    }
  }

  private func handleOpenAIError(_ error: Error) {
    if let openAIError = error as? OpenAIError {
      showAlert(title: "OpenAI Error", message: openAIError.localizedDescription)
    } else {
      showAlert(title: "Error", message: error.localizedDescription)
    }
  }
}
