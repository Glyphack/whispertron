import Foundation
import os
import whisper

private let logger = Logger(subsystem: "com.glyphack.whispertron", category: "WhisperContext")

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
    config.language.rawValue.withCString { language in
      config.vocabulary.withCString { prompt in
        params.language = language
        params.initial_prompt = prompt
        padded.withUnsafeBufferPointer { buf in
          if whisper_full(context, params, buf.baseAddress, Int32(buf.count)) != 0 {
            logger.error("Failed to run the model")
          }
        }
      }
    }
    return (0..<whisper_full_n_segments(context))
      .map { String(cString: whisper_full_get_segment_text(context, $0)) }
      .joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  nonisolated static func createContext(path: String) throws -> WhisperContext {
    guard let context = whisper_init_from_file_with_params(path, whisper_context_default_params()) else {
      logger.error("Couldn't load model at \(path)")
      throw WhisperError.couldNotInitializeContext
    }
    return WhisperContext(context: context)
  }
}
