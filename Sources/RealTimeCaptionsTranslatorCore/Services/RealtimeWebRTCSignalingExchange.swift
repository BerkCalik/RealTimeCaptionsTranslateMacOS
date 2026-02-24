import Foundation

enum RealtimeWebRTCSignalingExchange {
    static func exchangeSDP(
        offerSDP: String,
        apiKey: String,
        model: TranslationModelOption,
        callsEndpoint: URL,
        session: URLSession,
        profile: RealtimeWebRTCService.LatencyProfile
    ) async throws -> String {
        var request = URLRequest(url: callsEndpoint)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let sessionJSON = try makeSessionJSON(model: model, profile: profile)
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

    private static func makeSessionJSON(
        model: TranslationModelOption,
        profile: RealtimeWebRTCService.LatencyProfile
    ) throws -> String {
        let payload: [String: Any] = [
            "model": model.rawValue,
            "modalities": ["text"],
            "instructions": RealtimeTranslationInstructionBuilder.buildSessionInstructions(),
            "input_audio_transcription": [
                "model": "gpt-4o-mini-transcribe",
                "language": "en"
            ],
            "turn_detection": [
                "type": "server_vad",
                "threshold": profile.vadThreshold,
                "prefix_padding_ms": profile.vadPrefixMs,
                "silence_duration_ms": profile.vadSilenceMs,
                "create_response": false,
                "interrupt_response": false
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw SubtitleError.translationProtocolError("Unable to encode session JSON")
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

        if let output = object["output"] as? [String: Any],
           let sdp = output["sdp"] as? String,
           sdp.isEmpty == false {
            return sdp
        }

        return nil
    }
}
