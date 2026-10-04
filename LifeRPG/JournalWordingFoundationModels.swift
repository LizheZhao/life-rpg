import Foundation
import LifeRPGCore

#if canImport(FoundationModels)
import FoundationModels

/// The structure a follow-up is generated into: the two parts `JournalTextCheck.accept` looks at.
@available(iOS 26.0, *)
@Generable
private struct FollowUpDraft {
    @Guide(description: "One short sentence that repeats a few of the user's own words exactly.")
    var reflection: String
    @Guide(description: "One short question about what the user wrote.")
    var question: String
}

/// The on-device model as `JournalWording`. A fresh session per call keeps it stateless and the
/// context small: everything the model needs is in the prompt, and nothing the user wrote on an
/// earlier turn can reach it. Anything that throws (guardrails, an unsupported language, the model
/// going away mid-call) is a nil, which `JournalConversation` treats as "show the pool row".
@available(iOS 26.0, *)
struct FoundationModelsWording: JournalWording {
    func word(instructions: String, prompt: String) async -> String? {
        do {
            let session = LanguageModelSession(instructions: instructions)
            return try await session.respond(to: prompt).content
        } catch {
            return nil
        }
    }

    func wordFollowUp(instructions: String, prompt: String) async -> (reflection: String, question: String)? {
        do {
            let session = LanguageModelSession(instructions: instructions)
            let draft = try await session.respond(to: prompt, generating: FollowUpDraft.self).content
            return (draft.reflection, draft.question)
        } catch {
            return nil
        }
    }
}
#endif

/// Where the journal gets its model, if the device has one. The app targets iOS 17.6, so every
/// answer below iOS 26 is "none" and the journal runs on the pool rows alone.
enum JournalWordingProvider {
    static func current(language: JournalLanguage = .resolve(preferred: Locale.preferredLanguages))
        -> (any JournalWording)? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        let model = SystemLanguageModel.default
        guard model.availability == .available,
              model.supportsLocale(Locale(identifier: language.rawValue))
        else { return nil }
        return FoundationModelsWording()
        #else
        return nil
        #endif
    }

    /// Why `current` is nil, for the Debug page: a missing model otherwise looks like a model that
    /// was asked and rejected.
    static func status(language: JournalLanguage = .resolve(preferred: Locale.preferredLanguages)) -> String {
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
