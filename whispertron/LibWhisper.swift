import Foundation
import whisper

enum WhisperError: Error {
  case couldNotInitializeContext
}

// Meet Whisper C++ constraint: Don't access from more than one thread at a time.
actor WhisperContext {
  private var context: OpaquePointer

  init(context: OpaquePointer) {
    self.context = context
  }

  deinit {
    whisper_free(context)
  }

  func fullTranscribe(samples: [Float], language: String?, translate: Bool) {
    // Leave 2 processors free (i.e. the high-efficiency cores).
    let maxThreads = max(1, min(8, cpuCount() - 2))
    print("Selecting \(maxThreads) threads")
    var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

    // Adapted from whisper.objc
    params.print_realtime = true
    params.print_progress = false
    params.print_timestamps = false
    params.print_special = false
    params.translate = translate

    params.n_threads = Int32(maxThreads)
    params.offset_ms = 0
    params.no_context = true
    params.single_segment = false

    // Set language: nil for auto-detect, or specific language code
    if let language = language {
      print("Using language: \(language), translate: \(translate)")
      language.withCString { languagePtr in
        params.language = languagePtr

        whisper_reset_timings(context)
        print("About to run whisper_full")
        samples.withUnsafeBufferPointer { samples in
          if whisper_full(context, params, samples.baseAddress, Int32(samples.count)) != 0 {
            print("Failed to run the model")
          } else {
            whisper_print_timings(context)
          }
        }
      }
    } else {
      params.language = nil  // Auto-detect language
      print("Using auto-detect language, translate: \(translate)")

      whisper_reset_timings(context)
      print("About to run whisper_full")
      samples.withUnsafeBufferPointer { samples in
        if whisper_full(context, params, samples.baseAddress, Int32(samples.count)) != 0 {
          print("Failed to run the model")
        } else {
          whisper_print_timings(context)
        }
      }
    }
  }

  func getTranscription() -> String {
    var transcription = ""
    for i in 0..<whisper_full_n_segments(context) {
      transcription += String.init(cString: whisper_full_get_segment_text(context, i))
    }
    return transcription
  }

  static func createContext(path: String) throws -> WhisperContext {
    var params = whisper_context_default_params()
    #if targetEnvironment(simulator)
      params.use_gpu = false
      print("Running on the simulator, using CPU")
    #endif
    let context = whisper_init_from_file_with_params(path, params)
    if let context {
      return WhisperContext(context: context)
    } else {
      print("Couldn't load model at \(path)")
      throw WhisperError.couldNotInitializeContext
    }
  }
}

private func cpuCount() -> Int {
  ProcessInfo.processInfo.processorCount
}
