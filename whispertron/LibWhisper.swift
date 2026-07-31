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
    // Pad short audio to at least 1s to prevent crashes
    var paddedSamples = samples
    if paddedSamples.count < 16000 {
      paddedSamples.append(contentsOf: [Float](repeating: 0, count: 16000 - paddedSamples.count))
    }
    // Append 0.5s silence to avoid trimming the tail
    paddedSamples.append(contentsOf: [Float](repeating: 0, count: 8000))

    let maxThreads = max(1, min(8, cpuCount() - 2))
    print("Selecting \(maxThreads) threads")
    var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
    params.beam_search.beam_size = 5

    params.print_realtime = true
    params.print_progress = false
    params.print_timestamps = false
    params.print_special = false
    params.translate = translate

    params.n_threads = Int32(maxThreads)
    params.offset_ms = 0
    params.no_context = true
    params.single_segment = true
    params.max_tokens = 0
    params.entropy_thold = 3.0
    params.suppress_blank = true
    params.suppress_nst = true
    params.no_speech_thold = 0.6

    let runWhisper = { [context] in
      whisper_reset_timings(context)
      print("About to run whisper_full")
      paddedSamples.withUnsafeBufferPointer { buf in
        if whisper_full(context, params, buf.baseAddress, Int32(buf.count)) != 0 {
          print("Failed to run the model")
        } else {
          whisper_print_timings(context)
        }
      }
    }

    if let language = language {
      print("Using language: \(language), translate: \(translate)")
      language.withCString { languagePtr in
        params.language = languagePtr
        runWhisper()
      }
    } else {
      params.language = nil
      print("Using auto-detect language, translate: \(translate)")
      runWhisper()
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
