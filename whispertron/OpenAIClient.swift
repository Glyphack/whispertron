import Foundation
import os

// MARK: - OpenAI Models

/// OpenAI API request for Responses endpoint
struct OpenAIRequest: Codable {
    let model: String
    let input: String

    enum CodingKeys: String, CodingKey {
        case model
        case input
    }
}

/// OpenAI API response
struct OpenAIResponse: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [Choice]?
    let output: [OutputMessage]? // Array of messages for Responses API

    struct OutputMessage: Codable {
        let id: String?
        let type: String?
        let status: String?
        let content: [ContentBlock]?
        let role: String?

        struct ContentBlock: Codable {
            let type: String?
            let text: String?
            let annotations: [String]?
            let logprobs: [String]?
        }
    }

    struct Choice: Codable {
        let index: Int?
        let message: Message?
        let text: String? // Alternative text field
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case message
            case text
            case finishReason = "finish_reason"
        }
    }

    struct Message: Codable {
        let role: String?
        let content: String?
    }
}

/// OpenAI API error response
struct OpenAIErrorResponse: Codable {
    let error: ErrorDetail

    struct ErrorDetail: Codable {
        let message: String
        let type: String?
        let code: String?
    }
}

/// OpenAI API errors
enum OpenAIError: Error, LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse
    case rateLimitExceeded
    case serverError(String)
    case decodingError(Error)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenAI API key configured. Please add your API key in Preferences."
        case .invalidAPIKey:
            return "Invalid OpenAI API key. Please check your API key in Preferences."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from OpenAI API."
        case .rateLimitExceeded:
            return "OpenAI rate limit exceeded. Please try again later."
        case .serverError(let message):
            return "OpenAI server error: \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .emptyResponse:
            return "OpenAI returned an empty response."
        }
    }
}

// MARK: - OpenAI Client

/// Handles communication with OpenAI API
actor OpenAIClient {
    // MARK: - Properties

    private let logger = Logger(subsystem: "com.example.whispertron", category: "OpenAI")
    private let baseURL = "https://api.openai.com/v1"
    private let session: URLSession
    private let settingsManager: AppSettings

    // MARK: - Initialization

    init(settingsManager: AppSettings, session: URLSession = .shared) {
        self.settingsManager = settingsManager
        self.session = session
    }

    // MARK: - Public Methods

    /// Process transcript text through OpenAI with system prompt
    /// - Parameters:
    ///   - transcript: The transcribed text from Whisper
    ///   - systemPrompt: The system prompt for text processing
    ///   - model: The OpenAI model to use (e.g., "gpt-5")
    /// - Returns: Processed text from OpenAI
    /// - Throws: OpenAIError if processing fails
    func processText(transcript: String, systemPrompt: String, model: String) async throws -> String {
        logger.info("Processing text with OpenAI model: \(model)")

        // Get API key
        guard let apiKey = await settingsManager.loadAPIKey() else {
            logger.error("No API key found")
            throw OpenAIError.noAPIKey
        }

        // Combine system prompt with user transcript
        let fullInput = "\(systemPrompt)\n\nText to process: \(transcript)"

        // Create request body
        let requestBody = OpenAIRequest(
            model: model,
            input: fullInput
        )

        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(requestBody)
        } catch {
            logger.error("Failed to encode request: \(error.localizedDescription)")
            throw OpenAIError.decodingError(error)
        }

        // Create URL request
        let request: URLRequest
        do {
            request = try createRequest(endpoint: "/responses", body: bodyData, apiKey: apiKey)
        } catch {
            logger.error("Failed to create request: \(error.localizedDescription)")
            throw error
        }

        // Make API call
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.error("Network error: \(error.localizedDescription)")
            throw OpenAIError.networkError(error)
        }

        // Handle response
        let validatedData: Data
        do {
            validatedData = try handleResponse(data: data, response: response)
        } catch {
            throw error
        }

        // Decode response
        let openAIResponse: OpenAIResponse
        do {
            openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: validatedData)
        } catch {
            logger.error("Failed to decode response: \(error.localizedDescription)")
            // Log the raw response for debugging
            if let rawString = String(data: validatedData, encoding: .utf8) {
                logger.error("Raw response: \(rawString)")
            }
            throw OpenAIError.decodingError(error)
        }

        // Extract text from response
        if let output = openAIResponse.output, !output.isEmpty {
            // Handle Responses API format with output array
            if let firstMessage = output.first,
               let contentBlocks = firstMessage.content,
               !contentBlocks.isEmpty {
                // Find first text content block
                if let textBlock = contentBlocks.first(where: { $0.text != nil }),
                   let text = textBlock.text {
                    logger.info("Successfully processed text via OpenAI Responses API")
                    return text
                }
            }
        } else if let choices = openAIResponse.choices, !choices.isEmpty {
            // Handle Chat Completions API format with choices array
            if let message = choices[0].message, let content = message.content {
                logger.info("Successfully processed text via OpenAI")
                return content
            } else if let text = choices[0].text {
                logger.info("Successfully processed text via OpenAI")
                return text
            }
        }

        logger.error("No text found in OpenAI response")
        throw OpenAIError.emptyResponse
    }

    // MARK: - Private Methods

    /// Create URLRequest for OpenAI API
    private func createRequest(endpoint: String, body: Data, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw OpenAIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 30.0

        return request
    }

    /// Handle HTTP response and check for errors
    private func handleResponse(data: Data, response: URLResponse) throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid response type")
            throw OpenAIError.invalidResponse
        }

        logger.info("OpenAI API response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200...299:
            return data

        case 401:
            logger.error("Invalid API key")
            throw OpenAIError.invalidAPIKey

        case 429:
            logger.error("Rate limit exceeded")
            throw OpenAIError.rateLimitExceeded

        case 400...499, 500...599:
            // Try to parse error response
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                logger.error("OpenAI API error: \(errorResponse.error.message)")
                throw OpenAIError.serverError(errorResponse.error.message)
            } else if let errorString = String(data: data, encoding: .utf8) {
                logger.error("OpenAI API error: \(errorString)")
                throw OpenAIError.serverError(errorString)
            } else {
                logger.error("OpenAI API error with status: \(httpResponse.statusCode)")
                throw OpenAIError.serverError("HTTP \(httpResponse.statusCode)")
            }

        default:
            logger.error("Unexpected HTTP status: \(httpResponse.statusCode)")
            throw OpenAIError.invalidResponse
        }
    }
}
