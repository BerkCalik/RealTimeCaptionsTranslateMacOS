import Foundation

enum RealtimeServerEventParser {
    static func parseJSONObject(data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SubtitleError.translationProtocolError("Invalid server event payload")
        }
        return json
    }

    static func parseServerEvents(data: Data) throws -> [RealtimeCaptionEvent] {
        let json = try parseJSONObject(data: data)
        return try parseServerEvents(json: json)
    }

    static func parseServerEvents(json: [String: Any]) throws -> [RealtimeCaptionEvent] {
        guard let type = json["type"] as? String else {
            return []
        }

        switch type {
        case "conversation.item.input_audio_transcription.delta":
            guard let itemID = json["item_id"] as? String,
                  let delta = json["delta"] as? String,
                  delta.isEmpty == false else {
                return []
            }
            return [.englishDelta(itemID: itemID, text: delta)]

        case "conversation.item.input_audio_transcription.completed":
            guard let itemID = json["item_id"] as? String else {
                return []
            }
            let transcript = (json["transcript"] as? String) ?? ""
            return [.englishFinal(itemID: itemID, text: transcript)]

        case "response.output_text.delta":
            guard let delta = json["delta"] as? String,
                  delta.isEmpty == false else {
                return []
            }
            let responseID = (json["response_id"] as? String) ?? responseID(from: json) ?? "unknown-response"
            return [.turkishDelta(responseID: responseID, text: delta)]

        case "response.output_text.done":
            let responseID = (json["response_id"] as? String) ?? responseID(from: json) ?? "unknown-response"
            var events: [RealtimeCaptionEvent] = []
            if let text = json["text"] as? String,
               text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                events.append(.turkishDelta(responseID: responseID, text: text))
            }
            events.append(.turkishFinal(responseID: responseID))
            return events

        case "response.done":
            guard let responseID = responseID(from: json) else {
                return []
            }

            var events: [RealtimeCaptionEvent] = []
            if let text = responseText(from: json),
               text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                events.append(.turkishDelta(responseID: responseID, text: text))
            }
            events.append(.turkishFinal(responseID: responseID))
            return events

        case "input_audio_buffer.speech_started":
            return [.speechStarted]

        case "input_audio_buffer.speech_stopped":
            return [.speechStopped]

        case "error":
            let message: String
            if let error = json["error"] as? [String: Any],
               let value = error["message"] as? String,
               value.isEmpty == false {
                message = value
            } else if let value = json["message"] as? String,
                      value.isEmpty == false {
                message = value
            } else {
                message = "Unknown realtime error"
            }

            if isIgnorableCancellationErrorMessage(message) {
                return []
            }
            throw SubtitleError.translationFailed(message)

        default:
            return []
        }
    }

    static func responseID(from json: [String: Any]) -> String? {
        if let response = json["response"] as? [String: Any],
           let responseID = response["id"] as? String,
           responseID.isEmpty == false {
            return responseID
        }

        if let value = json["response_id"] as? String,
           value.isEmpty == false {
            return value
        }

        return nil
    }

    static func responseText(from json: [String: Any]) -> String? {
        guard let response = json["response"] as? [String: Any],
              let output = response["output"] as? [[String: Any]],
              output.isEmpty == false else {
            return nil
        }

        var collected: [String] = []
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if let text = part["text"] as? String,
                   text.isEmpty == false {
                    collected.append(text)
                }
            }
        }

        if collected.isEmpty {
            return nil
        }
        return collected.joined(separator: "\n")
    }

    static func httpErrorMessage(from data: Data, statusCode: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           message.isEmpty == false {
            return message
        }

        if let text = String(data: data, encoding: .utf8),
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return text
        }

        return "HTTP \(statusCode)"
    }

    static func realtimeErrorMessage(from json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           message.isEmpty == false {
            return message
        }

        if let message = json["message"] as? String,
           message.isEmpty == false {
            return message
        }

        return nil
    }

    static func isIgnorableCancellationErrorMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("cancellation failed") &&
            normalized.contains("no active response found")
    }
}
