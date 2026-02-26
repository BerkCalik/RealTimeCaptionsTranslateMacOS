import Foundation

enum RealtimeQuestionAnswerSignalingExchange {
    static func exchangeSDP(
        offerSDP: String,
        apiKey: String,
        callsEndpoint: URL,
        session: URLSession,
        sessionInstructions: String
    ) async throws -> String {
        var request = URLRequest(url: callsEndpoint)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let sessionJSON = try makeSessionJSON(instructions: sessionInstructions)
        request.httpBody = makeMultipartBody(
            boundary: boundary,
            parts: [
                ("sdp", offerSDP),
                ("session", sessionJSON)
            ]
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SubtitleError.translationFailed("Invalid signaling response")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            throw SubtitleError.translationFailed(
                RealtimeServerEventParser.httpErrorMessage(from: data, statusCode: http.statusCode)
            )
        }

        if let contentType = http.value(forHTTPHeaderField: "Content-Type"),
           contentType.localizedCaseInsensitiveContains("application/json"),
           let parsed = try parseAnswerSDPFromJSON(data) {
            return parsed
        }

        if let raw = String(data: data, encoding: .utf8),
           raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return raw
        }

        throw SubtitleError.translationFailed("Answer SDP is empty")
    }

    private static func makeSessionJSON(instructions: String) throws -> String {
        let payload: [String: Any] = [
            "model": "gpt-realtime",
            "modalities": ["text"],
            "instructions": instructions
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw SubtitleError.translationProtocolError("Unable to encode Q&A session JSON")
        }
        return json
    }

    private static func makeMultipartBody(boundary: String, parts: [(String, String)]) -> Data {
        var data = Data()

        for part in parts {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"\(part.0)\"\r\n\r\n".data(using: .utf8)!)
            data.append(part.1.data(using: .utf8)!)
            data.append("\r\n".data(using: .utf8)!)
        }

        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }

    private static func parseAnswerSDPFromJSON(_ data: Data) throws -> String? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let sdp = object["sdp"] as? String, sdp.isEmpty == false {
            return sdp
        }
        if let answer = object["answer"] as? [String: Any],
           let sdp = answer["sdp"] as? String,
           sdp.isEmpty == false {
            return sdp
        }
        return nil
    }
}
