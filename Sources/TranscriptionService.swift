import Foundation

final class TranscriptionService {
    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini-transcribe"

    private let apiKey: String
    private let baseURL: String
    private let transcriptionTimeoutSeconds: TimeInterval = 20

    init(apiKey: String, baseURL: String = defaultBaseURL) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    struct ValidationResult {
        let isValid: Bool
        let message: String?
    }

    static func validateAPIKey(_ key: String, baseURL: String = defaultBaseURL) async -> ValidationResult {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ValidationResult(isValid: false, message: "API key is empty.")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let body = multipartBody(
            fields: [
                "model": defaultModel
            ],
            fileFieldName: "file",
            fileName: "validation.wav",
            mimeType: "audio/wav",
            fileData: silenceWAVData(),
            boundary: boundary
        )

        do {
            let request = makeMultipartRequest(
                apiKey: trimmed,
                baseURL: baseURL,
                path: "/audio/transcriptions",
                boundary: boundary,
                body: body,
                timeoutInterval: 10
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                return ValidationResult(isValid: true, message: nil)
            }

            return ValidationResult(
                isValid: false,
                message: apiErrorMessage(
                    statusCode: status,
                    responseData: data,
                    fallback: "Validation failed with status \(status)."
                )
            )
        } catch {
            return ValidationResult(isValid: false, message: error.localizedDescription)
        }
    }

    func transcribe(fileURL: URL) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { [weak self] in
                guard let self else {
                    throw TranscriptionError.submissionFailed("Service deallocated")
                }
                return try await self.transcribeAudio(fileURL: fileURL)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.transcriptionTimeoutSeconds * 1_000_000_000))
                throw TranscriptionError.transcriptionTimedOut(self.transcriptionTimeoutSeconds)
            }

            guard let result = try await group.next() else {
                throw TranscriptionError.submissionFailed("No transcription result")
            }
            group.cancelAll()
            return result
        }
    }

    private func transcribeAudio(fileURL: URL) async throws -> String {
        let audioData = try Data(contentsOf: fileURL)
        let mimeType = audioContentType(for: fileURL.lastPathComponent)
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = Self.multipartBody(
            fields: [
                "model": Self.defaultModel
            ],
            fileFieldName: "file",
            fileName: fileURL.lastPathComponent,
            mimeType: mimeType,
            fileData: audioData,
            boundary: boundary
        )

        let request = Self.makeMultipartRequest(
            apiKey: apiKey,
            baseURL: baseURL,
            path: "/audio/transcriptions",
            boundary: boundary,
            body: body,
            timeoutInterval: transcriptionTimeoutSeconds
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.submissionFailed("No response from server")
        }

        guard httpResponse.statusCode == 200 else {
            throw TranscriptionError.submissionFailed(
                Self.apiErrorMessage(
                    statusCode: httpResponse.statusCode,
                    responseData: data,
                    fallback: "Transcription failed with status \(httpResponse.statusCode)."
                )
            )
        }

        return try parseTranscript(from: data)
    }

    private func audioContentType(for fileName: String) -> String {
        if fileName.lowercased().hasSuffix(".wav") {
            return "audio/wav"
        }
        if fileName.lowercased().hasSuffix(".mp3") {
            return "audio/mpeg"
        }
        if fileName.lowercased().hasSuffix(".m4a") {
            return "audio/mp4"
        }
        return "application/octet-stream"
    }

    private func parseTranscript(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriptionError.pollFailed("Invalid JSON response")
        }

        if let text = json["text"] as? String {
            return sanitizeTranscript(text)
        }

        let responseBody = String(data: data, encoding: .utf8) ?? ""
        throw TranscriptionError.pollFailed("Missing transcript text in response: \(responseBody)")
    }

    private func sanitizeTranscript(_ value: String) -> String {
        var transcript = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if transcript.hasPrefix("\""), transcript.hasSuffix("\""), transcript.count > 1 {
            transcript.removeFirst()
            transcript.removeLast()
            transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return transcript
    }

    private static func makeMultipartRequest(
        apiKey: String,
        baseURL: String,
        path: String,
        boundary: String,
        body: Data,
        timeoutInterval: TimeInterval
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval
        request.httpBody = body
        return request
    }

    private static func multipartBody(
        fields: [String: String],
        fileFieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        boundary: String
    ) -> Data {
        var body = Data()

        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            body.appendASCII("--\(boundary)\r\n")
            body.appendASCII("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendUTF8("\(value)\r\n")
        }

        body.appendASCII("--\(boundary)\r\n")
        body.appendASCII("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n")
        body.appendASCII("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.appendASCII("\r\n")
        body.appendASCII("--\(boundary)--\r\n")

        return body
    }

    private static func apiErrorMessage(statusCode: Int, responseData: Data, fallback: String) -> String {
        guard let payload = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            let body = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return body.isEmpty ? fallback : "\(fallback) \(body)"
        }

        if let error = payload["error"] as? [String: Any] {
            let message = error["message"] as? String ?? fallback
            let code = error["code"] as? String
            if let code, !code.isEmpty {
                return "\(message) (\(code))"
            }
            return message
        }

        return fallback
    }

    private static func silenceWAVData(sampleRate: Int = 16_000, durationMillis: Int = 100) -> Data {
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleCount = max(1, sampleRate * durationMillis / 1000)
        let blockAlign = UInt16(Int(channelCount) * Int(bitsPerSample / 8))
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(sampleCount) * UInt32(blockAlign)

        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36) + dataSize)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(channelCount)
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.appendASCII("data")
        data.appendLittleEndian(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }
}

enum TranscriptionError: LocalizedError {
    case uploadFailed(String)
    case submissionFailed(String)
    case transcriptionFailed(String)
    case transcriptionTimedOut(TimeInterval)
    case pollFailed(String)

    var errorDescription: String? {
        switch self {
        case .uploadFailed(let msg): return "Upload failed: \(msg)"
        case .submissionFailed(let msg): return "Submission failed: \(msg)"
        case .transcriptionTimedOut(let seconds): return "Transcription timed out after \(Int(seconds))s"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        case .pollFailed(let msg): return "Polling failed: \(msg)"
        }
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        if let data = string.data(using: .ascii) {
            append(data)
        }
    }

    mutating func appendUTF8(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { buffer in
            append(buffer.bindMemory(to: UInt8.self))
        }
    }
}
