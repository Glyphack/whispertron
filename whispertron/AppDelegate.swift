import ApplicationServices
@preconcurrency import AppKit
@preconcurrency import Cocoa
import CoreGraphics
import Foundation
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
  @Published var liveText = ""
}

// MARK: - History Models

struct TranscriptionEntry: Identifiable, Equatable, Hashable {
  let id = UUID()
  let text: String
  let timestamp = Date()
}

@MainActor
class HistoryManager: ObservableObject {
  @Published var entries: [TranscriptionEntry] = []
  private let settings: AppSettings
  
  init(settings: AppSettings) {
    self.settings = settings
  }
  
  func addEntry(text: String) {
    let maxEntries = settings.config.maxHistoryEntries
    
    guard maxEntries > 0 else { return }
    
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else { return }
    
    entries.insert(TranscriptionEntry(text: text), at: 0)
    
    if entries.count > maxEntries {
      entries.removeLast(entries.count - maxEntries)
    }
  }
  
  func deleteEntry(id: UUID) {
    entries.removeAll { $0.id == id }
  }
  
  func clearAll() {
    entries.removeAll()
  }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  // MARK: - Properties

  private var statusItem: NSStatusItem?
  private var recordMenuItem: NSMenuItem?
  private var whisperContext: WhisperContext?
  private var recorder: Recorder?
  private var modelLoad: Task<WhisperContext, Error>?
  private var unloadTimer: Timer?
  private var previewTask: Task<Void, Never>?
  private var settingsManager: AppSettings = AppSettings()
  private var mainWindow: NSWindow?
  let windowState = WindowState()
  private var isRecording: Bool = false
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

  private var feedbackWindow: NSWindow?
  private var welcomeWindow: NSPanel?
  private var feedbackViewModel: FeedbackViewModel?
  private var audioLevelTimer: Timer?
  private var historyManager: HistoryManager!

  // MARK: - Lifecycle

  func applicationWillFinishLaunching(_ notification: Notification) {
    // Apply icon visibility before Dock decides what to show — avoids first-frame flash.
    applyIconVisibility(settingsManager.config.iconVisibility, isInitialLaunch: true)
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(refreshMenuBar),
      name: NSNotification.Name("RefreshMenuBar"),
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

    historyManager = HistoryManager(settings: settingsManager)

    setupApplicationMenu()

    if !UserDefaults.standard.bool(forKey: "hasShownWelcome") {
      showWelcome()
      UserDefaults.standard.set(true, forKey: "hasShownWelcome")
    }

    Task { @MainActor in
      do {
        _ = try await ensureModelLoaded()
        scheduleUnload()
      } catch {
        logger.error("Error loading model: \(error.localizedDescription)")
      }
    }

    Task { @MainActor in
      do {
        recorder = try await Recorder()
        if !checkAccessibilityPermissions() {
          promptForAccessibilityPermissions()
        }
      } catch {
        logger.error("Error creating recorder: \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Icon Visibility

  func applyIconVisibility(_ mode: IconVisibilityMode, isInitialLaunch: Bool = false) {
    switch mode {
    case .menubar:
      if statusItem == nil {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = isRecording ? recordingImage : standbyImage
        statusItem = item
        setupMenus()
      }
      NSApp.setActivationPolicy(.accessory)

    case .dock:
      if let item = statusItem {
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
        recordMenuItem = nil
      }
      NSApp.setActivationPolicy(.regular)
      if !isInitialLaunch {
        DispatchQueue.main.async {
          NSApp.activate(ignoringOtherApps: true)
        }
      }
    }
  }

  // MARK: - Dock Integration

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      openMainWindow(initialTab: windowState.selectedTab)
    }
    return true
  }

  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "Show Window", action: #selector(showMainWindowFromDock), keyEquivalent: ""))
    return menu
  }

  @objc private func showMainWindowFromDock() {
    openMainWindow(initialTab: windowState.selectedTab)
  }

  @objc func showWelcome() {
    if welcomeWindow == nil {
      let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      panel.title = "Welcome to Whispertron"
      panel.isFloatingPanel = true
      panel.level = .floating
      panel.isReleasedWhenClosed = false

      let view = WelcomeView {
        panel.close()
      }
      panel.contentViewController = NSHostingController(rootView: view)
      welcomeWindow = panel
    }
    welcomeWindow?.center()
    welcomeWindow?.makeKeyAndOrderFront(nil)
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

  // MARK: - Transcription

  // Translated from espanso's injectString function
  func insertStringAtCursor(_ string: String) async -> Bool {
    logger.info("Attempting to insert text: \"\(string)\"")

    // Check permissions before attempting insertion
    if !checkAccessibilityPermissions() {
      return false
    }

    let udelay = UInt32(1000)

    return await MainActor.run {
      let buffer = Array(string.utf16)

      // Because of a bug ( or undocumented limit ) of the CGEventKeyboardSetUnicodeString method
      // the string gets truncated after 20 characters, so we need to send multiple events.
      var i = 0
      let chunkSize = 20
      let totalChunks = (buffer.count + chunkSize - 1) / chunkSize
      var failedChunks = 0

      while i < buffer.count {
        let currentChunkSize = min(chunkSize, buffer.count - i)
        let offsetBuffer = Array(buffer[i..<(i + currentChunkSize)])

        if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: false) {
          keyDown.flags = []
          keyDown.keyboardSetUnicodeString(stringLength: currentChunkSize, unicodeString: offsetBuffer)
          keyDown.post(tap: .cghidEventTap)
          usleep(udelay)
          keyUp.flags = []
          keyUp.post(tap: .cghidEventTap)
          self.logger.debug("Posted CGEvent chunk \((i/chunkSize) + 1)/\(totalChunks)")
        } else {
          self.logger.error("Failed to create CGEvent for chunk \((i/chunkSize) + 1)")
          failedChunks += 1
        }

        usleep(udelay)

        i += currentChunkSize
      }

      let success = failedChunks == 0
      if success {
        self.logger.info("Text insertion completed (\(totalChunks) chunks)")
      } else {
        self.logger.error("Text insertion failed: \(failedChunks)/\(totalChunks) chunks failed")
      }
      return success
    }
  }


  // MARK: - Feedback UI

  @MainActor
  func setupFeedbackWindow() {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: windowSize, height: windowSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)

    panel.isFloatingPanel = true
    panel.level = .statusBar
    panel.isOpaque = false
    panel.backgroundColor = NSColor.clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.canHide = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

    feedbackWindow = panel

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
        if let screen = NSScreen.main ?? NSScreen.screens.first {
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

        self.feedbackWindow?.orderFrontRegardless()
      } else {
        // Reset timer when closing
        viewModel.recordingStartTime = nil
        viewModel.recordingDuration = 0
        viewModel.liveText = ""
        self.stopAudioLevelPulsing()
        self.feedbackWindow?.orderOut(nil)
      }
    }
  }

  private func startAudioLevelPulsing() {
    audioLevelTimer?.invalidate()
    audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.0333, repeats: true) { [weak self] _ in
      guard let self = self, let recorder = self.recorder else { return }

      Task { @MainActor in
        self.feedbackViewModel?.audioLevel = recorder.audioLevel

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
    guard let statusItem = statusItem else { return }

    let menu = NSMenu()

    menu.addItem(NSMenuItem.separator())

    let preferences = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
    menu.addItem(preferences)

    let gettingStarted = NSMenuItem(title: "Getting Started", action: #selector(showWelcome), keyEquivalent: "")
    menu.addItem(gettingStarted)

    menu.addItem(NSMenuItem.separator())

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

    let translateItem = NSMenuItem(
      title: "Translate to English",
      action: #selector(toggleTranslateToEnglish(_:)),
      keyEquivalent: ""
    )
    translateItem.state = settingsManager.config.translateToEnglish ? .on : .off
    menu.addItem(translateItem)

    menu.addItem(NSMenuItem.separator())

    let historyItem = NSMenuItem(title: "History", action: #selector(openHistory), keyEquivalent: "")
    menu.addItem(historyItem)

    menu.addItem(NSMenuItem.separator())

    let record = NSMenuItem(title: isRecording ? "Stop Recording" : "Record", action: #selector(didTapRecord), keyEquivalent: "")
    recordMenuItem = record
    menu.addItem(record)

    menu.addItem(NSMenuItem.separator())

    menu.addItem(
      NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

    let about = NSMenuItem(title: "About", action: #selector(openAbout), keyEquivalent: "")
    menu.addItem(about)

    statusItem.menu = menu

    updateModelMenuSelection()
    updateLanguageMenuSelection()
  }

  func setupApplicationMenu() {
    let mainMenu = NSMenu()

    // Application Menu
    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(NSMenuItem(title: "About Whispertron", action: #selector(openAbout), keyEquivalent: ""))
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(NSMenuItem(title: "Settings...", action: #selector(openPreferences), keyEquivalent: ","))
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(NSMenuItem(title: "Hide Whispertron", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
    let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(hideOthers)
    appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(NSMenuItem(title: "Quit Whispertron", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    // Edit Menu with First Responder pattern
    let editMenuItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
    let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(redo)
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

    // View Menu (Recording shortcut for dock mode discoverability)
    let viewMenuItem = NSMenuItem()
    let viewMenu = NSMenu(title: "View")
    viewMenu.addItem(NSMenuItem(title: "Record", action: #selector(didTapRecord), keyEquivalent: ""))
    viewMenuItem.submenu = viewMenu
    mainMenu.addItem(viewMenuItem)

    // Window Menu
    let windowMenuItem = NSMenuItem()
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
    windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
    windowMenu.addItem(NSMenuItem.separator())
    windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
    windowMenuItem.submenu = windowMenu
    NSApp.windowsMenu = windowMenu
    mainMenu.addItem(windowMenuItem)

    NSApp.mainMenu = mainMenu
  }

  private func updateModelMenuSelection() {
    guard let menu = statusItem?.menu,
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
    guard let menu = statusItem?.menu,
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

  @MainActor
  private func ensureModelLoaded() async throws -> WhisperContext {
    if let whisperContext { return whisperContext }
    let load = modelLoad ?? Task.detached { [path = settingsManager.getCurrentModelPath()] in
      try WhisperContext.createContext(path: path)
    }
    modelLoad = load
    defer {
      if modelLoad == load { modelLoad = nil }
    }
    let context = try await load.value
    if modelLoad == load {
      whisperContext = context
      logger.info("Model loaded")
    }
    return whisperContext ?? context
  }

  @MainActor
  private func scheduleUnload() {
    unloadTimer?.invalidate()
    let autoUnload = settingsManager.config.autoUnload
    guard autoUnload.enabled, whisperContext != nil, !isRecording else { return }
    let timeout = TimeInterval(autoUnload.timeoutMinutes * 60)
    logger.info("Scheduling model unload in \(timeout) seconds")
    unloadTimer = Timer.scheduledTimer(
      timeInterval: timeout, target: self, selector: #selector(unloadModel), userInfo: nil, repeats: false)
  }

  @MainActor
  @objc private func unloadModel() {
    whisperContext = nil
    logger.info("Model unloaded")
  }

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

        if settingsManager.isModelAvailable(model) {
          await switchModel(to: model)
        } else {
          await downloadAndSwitchModel(to: model)
        }
      }
    }

  @MainActor
  private func switchModel(to model: ModelInfo) async {
    do {
      if isRecording {
        await recorder?.stopRecording()
      }

      // Show loading feedback
      showFeedback(.transcribing)

      let context = try await settingsManager.switchToModel(model) { path in
        try WhisperContext.createContext(path: path)
      }
      modelLoad = nil
      whisperContext = context

      updateModelMenuSelection()
      showFeedback(nil)

      logger.info("Successfully switched to model: \(model.displayName)")

      scheduleUnload()
    } catch {
      logger.error("Error switching model: \(error.localizedDescription)")
      showFeedback(nil)
      showAlert(title: "Model Switch Failed", message: error.localizedDescription)
    }
  }

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

  @MainActor
  private func setRecordingState(_ recording: Bool) {
    isRecording = recording
    statusItem?.button?.image = recording ? recordingImage : standbyImage
    statusItem?.button?.appearsDisabled = false
    statusItem?.button?.cell?.isHighlighted = recording
    recordMenuItem?.title = recording ? "Stop Recording" : "Record"
  }

  @MainActor
  private func startPreview() {
    previewTask?.cancel()
    previewTask = Task { @MainActor in
      while true {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard !Task.isCancelled, isRecording, let recorder else { return }
        guard let context = whisperContext else { continue }
        let text = await context.transcribe(
          samples: recorder.snapshot(seconds: 10), config: settingsManager.config, preview: true)
        guard !Task.isCancelled else { return }
        feedbackViewModel?.liveText = text
      }
    }
  }

  @objc func Transcribe() {
    logger.debug("didTapStandby")

    Task { @MainActor in
      previewTask?.cancel()
      previewTask = nil
      setRecordingState(false)

      guard let recorder else {
        showFeedback(nil)
        return
      }
      let samples = await recorder.stopRecording()
      let duration = Double(samples.count) / 16000
      logger.info("Recording stopped. Duration: \(String(format: "%.2f", duration))s")

      guard samples.count > 16000 else {
        logger.info("Recording too short (\(String(format: "%.2f", duration))s), ignoring")
        showFeedback(nil)
        scheduleUnload()
        return
      }

      do {
        if whisperContext == nil {
          showFeedback(.loading)
        }
        let context = try await ensureModelLoaded()
        showFeedback(.transcribing)
        let text = await context.transcribe(samples: samples, config: settingsManager.config)
        logger.info("Transcription completed: \"\(text)\"")

        let insertionSucceeded = await insertStringAtCursor(text)
        if !insertionSucceeded {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
          showError("Could not paste text at cursor. The transcription has been copied to clipboard instead. Please paste it manually (⌘V).")
        }

        historyManager.addEntry(text: text)
      } catch {
        logger.error("Error loading model: \(error.localizedDescription)")
        showError("Could not load the model: \(error.localizedDescription)")
      }

      showFeedback(nil)
      scheduleUnload()
    }
  }

  @objc func startRecording() {
    Task { @MainActor in
      unloadTimer?.invalidate()
      setRecordingState(true)
      showFeedback(.recording)

      do {
        if recorder == nil {
          recorder = try await Recorder()
        }
        try await recorder?.startRecording()
      } catch {
        logger.error("Error starting recording: \(error.localizedDescription)")
        await recorder?.stopRecording()
        setRecordingState(false)
        scheduleUnload()
        showFeedback(nil)

        let alert = NSAlert()
        alert.messageText = "Recording Failed"
        alert.informativeText = "Could not start recording: \(error.localizedDescription)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
        return
      }

      guard isRecording else {
        await recorder?.stopRecording()
        scheduleUnload()
        return
      }
      startPreview()
      Task {
        if (try? await ensureModelLoaded()) != nil {
          scheduleUnload()
        }
      }
    }
  }

  @objc func didTapRecord() {
    if isRecording {
      Transcribe()
    } else {
      startRecording()
    }
  }

  // MARK: - Main Window

  @objc func openHistory() {
    openMainWindow(initialTab: .history)
  }

  @objc func openPreferences() {
    openMainWindow(initialTab: .general)
  }

  func openMainWindow(initialTab: MainTab) {
    if mainWindow == nil {
      let view = MainView(
        state: windowState,
        settings: settingsManager,
        historyManager: historyManager,
        onIconVisibilityChange: { [weak self] mode in
          self?.applyIconVisibility(mode)
        }
      )
      let hostingController = NSHostingController(rootView: view)

      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 620),
        styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      window.title = "Whispertron"
      window.contentViewController = hostingController
      window.delegate = self
      window.isReleasedWhenClosed = false
      window.contentMinSize = NSSize(width: 720, height: 560)
      window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
      window.setContentSize(NSSize(width: 800, height: 620))
      window.center()

      mainWindow = window
    }

    windowState.selectedTab = initialTab

    if settingsManager.config.iconVisibility == .menubar {
      NSApp.setActivationPolicy(.regular)
    }
    NSApp.activate(ignoringOtherApps: true)
    mainWindow?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window == mainWindow else { return }

    if settingsManager.config.iconVisibility == .menubar {
      NSApp.setActivationPolicy(.accessory)
    }
    NotificationCenter.default.post(name: NSNotification.Name("RefreshMenuBar"), object: nil)
  }

  @objc func refreshMenuBar() {
    // Refresh all menu items when preferences change
    updateModelMenuSelection()
    updateLanguageMenuSelection()
  }

}
