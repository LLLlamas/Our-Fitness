// Shared scaffolding for the on-device AI services.
//
// Five services talk to Apple's on-device model (FoundationModels, iOS 26+):
// ExerciseInsightService, WorkoutSuggestionService, MealParseService,
// MealIdeaService, FoodAlternativeService. Each one used to carry its own copy of
// the same three pieces of boilerplate:
//
//   1. the `isAvailable` check (iOS 26 + SystemLanguageModel availability),
//   2. the `#if canImport(FoundationModels)` + `#available` + `LanguageModelSession`
//      + do/catch envelope around a single `respond(to:generating:)` call,
//   3. a JSON-in-UserDefaults result cache (two of them), and
//   4. a Build/Circuit "mode line" appended to the prompt (three of them).
//
// This file owns all four exactly once. It deliberately owns NO prompt copy and
// NO @Generable shapes — those stay in the service that uses them, because each
// service's instructions and structured output are what make it that service.
//
// Behaviour is unchanged from the per-service copies:
//   • `isAvailable` is false on iOS < 26, when FoundationModels is absent at
//     compile time, and whenever the system model is not `.available`.
//   • `generate` returns nil for every failure mode — unavailable model, thrown
//     error — so callers keep falling back to the deterministic Domain matchers
//     (ExerciseInfo, FoodParser, ExerciseGoalMatcher, MealCravingMatcher).
//
// Only FoundationModels symbols already in use by those services appear here:
// `SystemLanguageModel.default.availability`, `LanguageModelSession { … }`. The
// `respond(to:generating:)` call stays at each call site inside the closure, so
// no generic constraint on FoundationModels' protocols is needed.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public enum OnDeviceModel {

    // MARK: - Availability

    /// True only when the on-device model can actually run right now.
    /// False on iOS < 26, where FoundationModels doesn't exist, and whenever
    /// Apple Intelligence isn't enabled / the model isn't downloaded.
    public static var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            #if canImport(FoundationModels)
            return SystemLanguageModel.default.availability == .available
            #else
            return false
            #endif
        }
        return false
    }

    // MARK: - Request envelope

    #if canImport(FoundationModels)
    /// Run one generation against a fresh session with `instructions`, returning
    /// nil instead of throwing.
    ///
    /// The caller's closure makes the actual `session.respond(to:generating:)`
    /// call with its own `@Generable` draft type — that keeps the drafts private
    /// to their service and keeps this helper free of any FoundationModels
    /// generic constraint.
    ///
    /// Returns nil when the model is unavailable or the request throws, which is
    /// every service's "fall back to the deterministic path" signal.
    @available(iOS 26.0, *)
    static func generate<T>(
        instructions: String,
        _ request: (LanguageModelSession) async throws -> T
    ) async -> T? {
        guard isAvailable else { return nil }
        do {
            let session = LanguageModelSession { instructions }
            return try await request(session)
        } catch {
            return nil
        }
    }
    #endif

    // MARK: - Mode prompt line

    /// Pick the Build / Circuit sentence to splice into a prompt.
    ///
    /// The copy itself stays with the service — an exercise-selection tilt and a
    /// food-swap tilt are different sentences — this only collapses the repeated
    /// `switch mode` around them.
    static func modeLine(_ mode: Mode, build: String, circuit: String) -> String {
        switch mode {
        case .build:   return build
        case .circuit: return circuit
        }
    }

    // MARK: - Result cache

    /// JSON-in-UserDefaults cache for model output, keyed
    /// `<prefix>.<version>.<identity>`.
    ///
    /// Bump `version` to invalidate every entry after changing a prompt or the
    /// stored shape. Values are re-decoded on each read, so a stale shape simply
    /// misses rather than crashing.
    struct Cache<Value: Codable> {
        private let prefix: String
        private let version: String
        private let defaults: UserDefaults

        init(prefix: String, version: String, defaults: UserDefaults = .standard) {
            self.prefix = prefix
            self.version = version
            self.defaults = defaults
        }

        /// The full UserDefaults key for an identity — exposed because callers
        /// sometimes compute the identity once and reuse the key.
        func key(_ identity: String) -> String {
            "\(prefix).\(version).\(identity)"
        }

        func value(forKey key: String) -> Value? {
            guard let data = defaults.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(Value.self, from: data)
        }

        func set(_ value: Value, forKey key: String) {
            guard let data = try? JSONEncoder().encode(value) else { return }
            defaults.set(data, forKey: key)
        }

        func value(for identity: String) -> Value? { value(forKey: key(identity)) }

        func set(_ value: Value, for identity: String) { set(value, forKey: key(identity)) }
    }
}
