import Foundation
import SwiftData

enum RepositoryWriteError: Error {
    case missingRecord
}

extension Notification.Name {
    static let repositoryDidSave = Notification.Name("OurFitness.repositoryDidSave")
    static let repositoryWriteFailed = Notification.Name("OurFitness.repositoryWriteFailed")
    static let liveSessionDidChange = Notification.Name("OurFitness.liveSessionDidChange")
}

/// All repository mutations use an explicit commit boundary. Failure restores
/// the context, so a later autosave cannot silently commit an operation reported
/// as failed. Callers must check success before dismissing or celebrating.
enum RepositoryWrite {
    @discardableResult
    static func perform(_ context: ModelContext) -> Bool {
        perform(context, mutation: {})
    }

    @discardableResult
    static func perform(_ context: ModelContext, save: (() throws -> Void)? = nil,
                        mutation: () throws -> Void) -> Bool {
        do {
            try mutation()
            guard context.hasChanges else { return true }
            if let save { try save() } else { try context.save() }
            NotificationCenter.default.post(name: .repositoryDidSave, object: context)
            return true
        } catch {
            let inserted = Set(context.insertedModelsArray.map(\.persistentModelID))
            let existing = (context.changedModelsArray + context.deletedModelsArray)
                .filter { !inserted.contains($0.persistentModelID) }
            context.processPendingChanges()
            context.rollback()
            // SwiftData restores the store immediately, but a retained model's
            // observed values can remain stale until fetched again. Rehydrate
            // affected existing rows before the UI handles the failure.
            for model in existing { refresh(model, in: context) }
            // No health values or storage paths in user-facing errors/logs.
            NotificationCenter.default.post(name: .repositoryWriteFailed, object: nil)
            return false
        }
    }

    private static func refresh<Model: PersistentModel>(_ model: Model, in context: ModelContext) {
        let id = model.persistentModelID
        _ = try? context.fetch(FetchDescriptor<Model>(predicate: #Predicate { $0.persistentModelID == id }))
    }
}
