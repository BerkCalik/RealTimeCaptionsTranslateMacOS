import Foundation

enum RealtimeQuestionAnswerInstructionBuilder {
    static func buildSessionInstructions(resumeContext: String, usingFallback: Bool) -> String {
        let modeRule: String
        if usingFallback {
            modeRule = "Resume context is unavailable. You may provide general professional interview-style answers, but do not fabricate specific employers, dates, metrics, or credentials."
        } else {
            modeRule = "Use the provided resume context as your primary grounding source. Prefer resume-supported details. If a requested detail is not present, answer generally without inventing specifics."
        }

        return """
        You are answering interview/professional questions as the candidate in first person.
        Respond in English only.
        Output only the answer text (no labels, no preamble) unless the question explicitly asks for a list.
        Never ask follow-up questions.
        Never ask the user to share their resume or additional background details.
        Do not request clarification; provide the best possible direct answer immediately.
        \(modeRule)

        Resume context follows:
        \(resumeContext)
        """
    }

    static func buildAnswerRequestInstructions(
        resumeContext: String,
        usingFallback: Bool,
        englishLevel: QAEnglishLevel
    ) -> String {
        let groundingRule: String
        if usingFallback {
            groundingRule = "Resume context is unavailable. Give a general but credible professional answer, and avoid made-up specific facts."
        } else {
            groundingRule = "Use the resume context below as the primary source for the answer. If a detail is missing, answer generally without inventing specifics and avoid made-up facts."
        }
        let levelRule = cefrGuidance(for: englishLevel)

        return """
        Answer the user's interview/professional question as the candidate in first person (use \"I\").
        Respond in English only.
        Target CEFR English level: \(englishLevel.rawValue).
        \(levelRule)
        Provide a direct answer immediately.
        Never ask follow-up questions.
        Never ask for a resume, more details, or clarification.
        Do not say you need more information before answering.
        Output only the answer text.
        \(groundingRule)

        Resume context:
        \(resumeContext)
        """
    }

    static func buildAnswerRequestInstructions() -> String {
        buildAnswerRequestInstructions(
            resumeContext: "No resume context available.",
            usingFallback: true,
            englishLevel: .b1
        )
    }

    private static func cefrGuidance(for level: QAEnglishLevel) -> String {
        switch level {
        case .a1:
            return "Use very simple words and very short sentences. Keep the answer basic and clear."
        case .a2:
            return "Use simple everyday vocabulary and short sentences. Avoid complex grammar."
        case .b1:
            return "Use clear and practical language with mostly simple sentences and some moderate detail. Avoid advanced vocabulary unless necessary."
        case .b2:
            return "Use clear professional language with moderate detail and some complex sentences, but stay easy to follow."
        case .c1:
            return "Use fluent professional language with precise vocabulary and well-structured explanations."
        case .c2:
            return "Use highly fluent and nuanced professional language with advanced vocabulary when appropriate."
        }
    }
}
