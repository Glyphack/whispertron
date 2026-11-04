import Foundation
import os

final class DiagnosticLog: Sendable {
  static let shared = DiagnosticLog()

  let url: URL
  private let maxLines = 400
  private let trimEvery = 50
  private let writesSinceTrim = OSAllocatedUnfairLock(initialState: 0)
  private let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

  private init() {
    let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Logs/Whispertron", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    url = directory.appendingPathComponent("whispertron.log")
  }

  func write(_ message: String) {
    let line = "\(Date().formatted(timestamp)) \(message)\n"
    writesSinceTrim.withLock { writes in
      append(line)
      writes += 1
      guard writes >= trimEvery else { return }
      writes = 0
      trim()
    }
  }

  private func append(_ line: String) {
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: Data(line.utf8))
  }

  private func trim() {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count > maxLines else { return }
    let kept = lines.suffix(maxLines).joined(separator: "\n")
    try? kept.write(to: url, atomically: true, encoding: .utf8)
  }
}
