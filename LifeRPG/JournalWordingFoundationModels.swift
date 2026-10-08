import Foundation
import LifeRPGCore

#if canImport(FoundationModels)
import FoundationModels

/// The on-device model as `JournalWording`. A fresh session per call keeps it stateless and the
/// context small: everything the model needs is in the prompt, and nothing the user wrote on an
/// earlier turn can reach it. Anything that throws (guardrails, an unsupported language, the model
/// going away mid-call) is a nil, which `JournalAsk.resolve` treats as "use the next fixed prompt";
/// the error is kept for the Debug page (`JournalAskDebug`).
@available(iOS 26.0, *)
struct FoundationModelsWording: JournalWording {
    let language: JournalLanguage

    /// The editor calls this when it opens: a session for this language's instructions is made and
    /// prewarmed, and the next `word` with those instructions uses it, once. Still one session per
    /// question, so nothing carries over between questions.
    func prewarm() {
        let session = LanguageModelSession(instructions: JournalPromptBuilder.instructions(language: language))
        session.prewarm()
        WarmSessions.shared.put(session, for: language)
    }

    func word(instructions: String, prompt: String) async -> String? {
        let warm = instructions == JournalPromptBuilder.instructions(language: language)
            ? WarmSessions.shared.take(language) : nil
        let session = warm ?? LanguageModelSession(instructions: instructions)
        do {
            return try await session.respond(to: prompt).content
        } catch {
            JournalAskDebug.noteError(error)
            return nil
        }
    }
}

/// At most one unused prewarmed session per language.
@available(iOS 26.0, *)
private final class WarmSessions: @unchecked Sendable {
    static let shared = WarmSessions()
    private let lock = NSLock()
    private var sessions: [JournalLanguage: LanguageModelSession] = [:]

    func put(_ session: LanguageModelSession, for language: JournalLanguage) {
        lock.withLock { sessions[language] = session }
    }

    func take(_ language: JournalLanguage) -> LanguageModelSession? {
        lock.withLock { sessions.removeValue(forKey: language) }
    }
}
#endif

/// Where the journal gets its model, if the device has one. The app targets iOS 17.6, so every
/// answer below iOS 26 is "none" and "Ask me something" inserts the fixed prompts alone.
enum JournalWordingProvider {
    static func current(language: JournalLanguage = .system) -> (any JournalWording)? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        let model = SystemLanguageModel.default
        guard model.availability == .available,
              model.supportsLocale(Locale(identifier: language.rawValue))
        else { return nil }
        return FoundationModelsWording(language: language)
        #else
        return nil
        #endif
    }

    /// Why `current` is nil, for the Debug page: a missing model otherwise looks like a model that
    /// was asked and rejected.
    static func status(language: JournalLanguage = .system) -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return "iOS 26 or later is needed" }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale(Locale(identifier: language.rawValue))
                ? "available" : "available, but not for \(language.rawValue)"
        case .unavailable(.deviceNotEligible): return "device not eligible"
        case .unavailable(.appleIntelligenceNotEnabled): return "Apple Intelligence is off"
        case .unavailable(.modelNotReady): return "model not ready"
        case .unavailable: return "unavailable"
        }
        #else
        return "framework missing"
        #endif
    }
}
