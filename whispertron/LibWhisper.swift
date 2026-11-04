import Foundation
import os
import whisper

private let logger = Logger(subsystem: "com.glyphack.whispertron", category: "WhisperContext")

private let whisperLogCallback: ggml_log_callback = { level, text, _ in
  guard let text else { return }
  fputs(text, stderr)
  let message = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
  guard level == GGML_LOG_LEVEL_ERROR || message.hasPrefix("whisper_full") else { return }
  DiagnosticLog.shared.write("whisper: \(message)")
}

enum WhisperError: Error {
  case couldNotInitializeContext
}

actor WhisperContext {
  private let context: OpaquePointer

  init(context: OpaquePointer) {
    self.context = context
  }

  deinit {
    whisper_free(context)
  }

  func transcribe(samples: [Float], config: AppConfiguration, preview: Bool = false) -> String {
    let padded = samples + [Float](repeating: 0, count: 8000)
    var params = whisper_full_default_params(preview ? WHISPER_SAMPLING_GREEDY : WHISPER_SAMPLING_BEAM_SEARCH)
    params.translate = config.translateToEnglish
    params.carry_initial_prompt = true
    params.suppress_nst = true
    if preview { params.temperature_inc = 0 }
    let started = Date()
    config.language.rawValue.withCString { language in
      config.vocabulary.withCString { prompt in
        params.language = language
        params.initial_prompt = prompt
        padded.withUnsafeBufferPointer { buf in
          if whisper_full(context, params, buf.baseAddress, Int32(buf.count)) != 0 {
            logger.error("Failed to run the model")
            DiagnosticLog.shared.write("whisper_full failed")
          }
        }
      }
    }
    let segments = 0..<whisper_full_n_segments(context)
    let text = segments
      .map { String(cString: whisper_full_get_segment_text(context, $0)) }
      .joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    logResult(text, segments: segments, sampleCount: samples.count, config: config, preview: preview, started: started)
    return text
  }

  private func logResult(
    _ text: String, segments: Range<Int32>, sampleCount: Int, config: AppConfiguration, preview: Bool, started: Date
  ) {
    let log = DiagnosticLog.shared
    let audioSeconds = String(format: "%.2f", Double(sampleCount) / 16000)
    let took = String(format: "%.2f", Date().timeIntervalSince(started))
    if preview {
      log.write("preview audio=\(audioSeconds)s took=\(took)s text=\"\(text)\"")
      return
    }
    let detected = whisper_lang_str(whisper_full_lang_id(context)).map { String(cString: $0) } ?? "?"
    log.write(
      "transcribe model=\(config.currentModel.rawValue) language=\(config.language.rawValue) detected=\(detected) translate=\(config.translateToEnglish) vocabulary=\(config.vocabulary.count)chars audio=\(audioSeconds)s took=\(took)s segments=\(segments.count)"
    )
    for segment in segments {
      let start = Double(whisper_full_get_segment_t0(context, segment)) / 100
      let end = Double(whisper_full_get_segment_t1(context, segment)) / 100
      let tokens = whisper_full_n_tokens(context, segment)
      let probability =
        (0..<tokens).reduce(Float(0)) { $0 + whisper_full_get_token_p(context, segment, $1) } / Float(max(tokens, 1))
      let noSpeech = whisper_full_get_segment_no_speech_prob(context, segment)
      let segmentText = String(cString: whisper_full_get_segment_text(context, segment))
      log.write(
        String(
          format: "  segment %.2f-%.2fs tokens=%d p=%.2f no_speech=%.2f text=\"%@\"",
          start, end, tokens, Double(probability), Double(noSpeech), segmentText))
    }
  }

  nonisolated static func installLogging() {
    whisper_log_set(whisperLogCallback, nil)
  }

  nonisolated static func createContext(path: String) throws -> WhisperContext {
    guard let context = whisper_init_from_file_with_params(path, whisper_context_default_params()) else {
      logger.error("Couldn't load model at \(path)")
      throw WhisperError.couldNotInitializeContext
    }
    return WhisperContext(context: context)
  }
}
