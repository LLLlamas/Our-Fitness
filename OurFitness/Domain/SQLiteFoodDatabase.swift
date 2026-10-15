// Offline USDA-backed food database — SQLite/FTS5 edition.
//
// Production replacement for the in-memory `FoodDatabase`: the bundled
// `usda-foods.db` (USDA FoodData Central, CC0 / public domain) is queried on
// disk via FTS5, so RAM stays low even at ~270k entries and search stays <50ms.
// Built by `scripts/build-food-db.py --format sqlite`. NO runtime network.
//
// Domain layer: imports only Foundation + SQLite3 (iOS's built-in libsqlite3,
// NO added dependency). Never imports SwiftData or SwiftUI.
//
// Returns the SAME `FoodDatabaseEntry` value type the JSON loader produced, so
// `FoodParser` / `asCommonFood` callers stay uniform. Degrades gracefully to an
// EMPTY (non-crashing) database when the resource is absent — e.g. the hostless
// test target ships no bundle (those tests inject the in-memory `FoodDatabase`).
//
// Resolution authority is unchanged: curated `CommonFoods` always wins; this DB
// is the broader-coverage fallback (see `FoodParser`). Numbers are never
// invented — only real USDA per-serving values are stored.

import Foundation
import SQLite3

public final class SQLiteFoodDatabase: @unchecked Sendable {

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.ourfitness.sqlitefooddb", qos: .userInitiated)

    public private(set) var isEmpty: Bool

    public static let shared: SQLiteFoodDatabase = loadBundled()

    private init(db: OpaquePointer?) {
        self.db = db
        self.isEmpty = db == nil
    }

    deinit { if let db { sqlite3_close(db) } }

    /// Opens `usda-foods.db` from `bundle`. Returns empty (non-crashing) if absent.
    public static func loadBundled(bundle: Bundle = .main) -> SQLiteFoodDatabase {
        guard let url = bundle.url(forResource: "usda-foods", withExtension: "db") else {
            return SQLiteFoodDatabase(db: nil)
        }
        return open(path: url.path)
    }

    /// Opens a food database file read-only (the bundled one, or a fixture in
    /// tests). Returns empty (non-crashing) if it can't be opened.
    public static func open(path: String) -> SQLiteFoodDatabase {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return SQLiteFoodDatabase(db: nil)
        }
        return SQLiteFoodDatabase(db: db)
    }

    /// Every restaurant chain + menu item (`restaurant_chains` / `restaurant_items`,
    /// written by `scripts/build-food-db.py`). Small — a few hundred rows per
    /// chain — so `RestaurantCatalog` reads it ONCE into memory. Returns empty
    /// arrays when the database is empty or predates the restaurant tables.
    public func restaurantData() -> (chains: [RestaurantChain], items: [RestaurantMenuItem]) {
        queue.sync { (_restaurantChains(), _restaurantItems()) }
    }

    /// Best-match for a natural-language meal chunk. Returns the top FTS5 result,
    /// or nil if the database is empty or no row matches.
    public func bestMatch(in chunk: String) -> FoodDatabaseEntry? {
        queue.sync { _bestMatch(in: chunk) }
    }

    /// Full-text search for the food library picker. Returns up to `limit` results.
    /// Synchronous — safe to call from a background thread. Do not call in SwiftUI body.
    public func search(query: String, limit: Int = 20) -> [FoodDatabaseEntry] {
        queue.sync { _search(query: query, limit: limit) }
    }

    /// Async variant: suspends the caller (freeing the main actor) while the FTS5 query
    /// runs on the background queue. Use this from `.task(id:)` in SwiftUI views.
    public func searchAsync(query: String, limit: Int = 20) async -> [FoodDatabaseEntry] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self._search(query: query, limit: limit))
            }
        }
    }

    // MARK: - Private (called on `queue`)

    private func _bestMatch(in chunk: String) -> FoodDatabaseEntry? {
        let tokens = chunk.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 2 }
        guard !tokens.isEmpty, db != nil else { return nil }
        let ftsQuery = tokens.map { "\(escapeFTS($0))*" }.joined(separator: " OR ")
        return _query(ftsQuery: ftsQuery, limit: 1).first
    }

    private func _search(query: String, limit: Int) -> [FoodDatabaseEntry] {
        let clean = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, db != nil else { return [] }
        // Prefix match on each token for library search UX.
        let tokens = clean.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let ftsQuery = tokens.map { "\(escapeFTS($0))*" }.joined(separator: " ")
        return _query(ftsQuery: ftsQuery, limit: limit)
    }

    private func _restaurantChains() -> [RestaurantChain] {
        rows(sql: "SELECT slug, name, aliases, kind, item_count FROM restaurant_chains ORDER BY name") { stmt in
            RestaurantChain(
                slug: Self.text(stmt, 0),
                name: Self.text(stmt, 1),
                aliases: Self.text(stmt, 2).split(separator: "|").map(String.init),
                kind: Self.text(stmt, 3),
                itemCount: Int(sqlite3_column_int(stmt, 4))
            )
        }
    }

    private func _restaurantItems() -> [RestaurantMenuItem] {
        let sql = """
            SELECT id, chain_slug, category, sort_order, item_name, name, serving_label,
                   calories, protein_g, carbs_g, fat_g, fiber_g
            FROM restaurant_items ORDER BY chain_slug, sort_order
            """
        return rows(sql: sql) { stmt in
            RestaurantMenuItem(
                chainSlug: Self.text(stmt, 1),
                category: Self.text(stmt, 2),
                sortOrder: Int(sqlite3_column_int(stmt, 3)),
                itemName: Self.text(stmt, 4),
                food: FoodDatabaseEntry(
                    id: Self.text(stmt, 0), name: Self.text(stmt, 5), aliases: [],
                    servingLabel: Self.text(stmt, 6),
                    calories: Int(sqlite3_column_int(stmt, 7)),
                    proteinG: Int(sqlite3_column_int(stmt, 8)),
                    carbsG: Int(sqlite3_column_int(stmt, 9)),
                    fatG: Int(sqlite3_column_int(stmt, 10)),
                    fiberG: Int(sqlite3_column_int(stmt, 11))
                )
            )
        }
    }

    /// Runs a parameterless SELECT. A prepare failure (e.g. the table doesn't
    /// exist in an older database) yields no rows rather than an error.
    private func rows<T>(sql: String, _ map: (OpaquePointer?) -> T) -> [T] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(map(stmt)) }
        return out
    }

    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: c)
    }

    /// Wrap a token in double quotes (an FTS5 string literal) so punctuation and
    /// reserved words ("and"/"or"/"near"/"-") are matched literally, not parsed as
    /// query syntax. Embedded quotes are doubled per FTS5 escaping rules.
    private func escapeFTS(_ token: String) -> String {
        "\"" + token.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func _query(ftsQuery: String, limit: Int) -> [FoodDatabaseEntry] {
        guard let db else { return [] }
        let sql = """
            SELECT f.id, f.name, f.aliases, f.serving_label,
                   f.calories, f.protein_g, f.carbs_g, f.fat_g, f.fiber_g
            FROM foods_fts
            JOIN foods f ON f.rowid = foods_fts.rowid
            WHERE foods_fts MATCH ?
            ORDER BY rank
            LIMIT ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        // SQLITE_TRANSIENT: tell SQLite to copy the bound string (it outlives the call).
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, ftsQuery, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [FoodDatabaseEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id       = String(cString: sqlite3_column_text(stmt, 0))
            let name     = String(cString: sqlite3_column_text(stmt, 1))
            let aliasStr = String(cString: sqlite3_column_text(stmt, 2))
            let aliases  = aliasStr.split(separator: "|").map(String.init)
            let label    = String(cString: sqlite3_column_text(stmt, 3))
            let cal      = Int(sqlite3_column_int(stmt, 4))
            let prot     = Int(sqlite3_column_int(stmt, 5))
            let carb     = Int(sqlite3_column_int(stmt, 6))
            let fat      = Int(sqlite3_column_int(stmt, 7))
            let fib      = Int(sqlite3_column_int(stmt, 8))
            results.append(FoodDatabaseEntry(
                id: id, name: name, aliases: aliases,
                servingLabel: label,
                calories: cal, proteinG: prot,
                carbsG: carb, fatG: fat, fiberG: fib
            ))
        }
        return results
    }
}
