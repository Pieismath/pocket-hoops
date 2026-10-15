import Foundation

/// The world leaderboard: every player's best Arcade score, the name they picked and the character
/// they play as. It lives on a small Supabase database (see `supabase/migrations`), and the app only
/// talks to it while `BOARD_URL` and `BOARD_KEY` are set in project.yml. Without them the board is
/// off. Joining is opt-in: nothing is sent until the player picks a name.

/// A name on the board: A–Z, 0–9 and single spaces (what the pixel font can draw), up to 10 long.
enum BoardName {
    static let maxLength = 10

    /// What the name box shows while typing: upper-cased, other characters dropped, no double spaces.
    static func clean(_ s: String) -> String {
        var out = ""
        for ch in s.uppercased() where out.count < maxLength {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                out.append(ch)
            } else if ch == " ", let last = out.last, last != " " {
                out.append(ch)
            }
        }
        return out
    }

    /// The name to send, or nil if nothing usable is left.
    static func final(_ s: String) -> String? {
        let name = clean(s).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}

/// One row of the board.
struct BoardEntry: Codable, Equatable {
    let rank: Int
    let name: String
    /// `Outfit.code` of their character.
    let outfit: String
    let score: Int
    /// This row is the player's own.
    let you: Bool
}

/// What the board sends back: the top rows, the player's own row wherever it is, and how many play.
struct BoardPage: Codable, Equatable {
    let total: Int
    let top: [BoardEntry]
    let you: BoardEntry?
}

enum BoardError: Error, Equatable {
    case server(status: Int, body: String)
}

/// Calls the board's two database functions through the REST API Supabase puts in front of them
/// (PostgREST: POST <BOARD_URL>/rpc/<function> with the arguments as JSON).
struct BoardAPI {
    let base: URL
    let key: String
    var session: URLSession = .shared

    /// The board this build talks to: project.yml's BOARD_URL (the project's REST URL, ending in
    /// /rest/v1) and BOARD_KEY (its anon or publishable key). Nil while either is empty.
    static var configured: BoardAPI? {
        var url = Bundle.main.object(forInfoDictionaryKey: "PHBoardURL") as? String ?? ""
        var key = Bundle.main.object(forInfoDictionaryKey: "PHBoardKey") as? String ?? ""
        #if DEBUG
        // Debug `-boardURL <url> -boardKey <key>`: point a build at a test server.
        if let u = UserDefaults.standard.string(forKey: "boardURL") { url = u }
        if let k = UserDefaults.standard.string(forKey: "boardKey") { key = k }
        #endif
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard let base = URL(string: trimmed), base.scheme?.hasPrefix("http") == true, !key.isEmpty else { return nil }
        return BoardAPI(base: base, key: key)
    }

    private struct Submit: Encodable {
        let p_player: String
        let p_name: String
        let p_outfit: String
        let p_score: Int
    }

    private struct Load: Encodable {
        let p_player: String?
        let p_limit: Int
    }

    /// Records a game. The server keeps the best score and the latest name and look.
    func submit(player: UUID, name: String, outfit: String, score: Int) async throws {
        _ = try await call("submit_arcade_score",
                           Submit(p_player: player.uuidString.lowercased(), p_name: name, p_outfit: outfit, p_score: score))
    }

    /// The top `limit` rows, plus the player's own row if they've joined.
    func load(player: UUID?, limit: Int = 50) async throws -> BoardPage {
        let data = try await call("arcade_leaderboard", Load(p_player: player?.uuidString.lowercased(), p_limit: limit))
        return try JSONDecoder().decode(BoardPage.self, from: data)
    }

    func request<Body: Encodable>(_ function: String, _ body: Body) throws -> URLRequest {
        var r = URLRequest(url: base.appendingPathComponent("rpc").appendingPathComponent(function))
        r.httpMethod = "POST"
        r.timeoutInterval = 10
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(key, forHTTPHeaderField: "apikey")
        // Supabase's older anon keys are JWTs and also go in Authorization; the newer publishable
        // keys (sb_publishable_…) only go in apikey.
        if key.split(separator: ".").count == 3 { r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        r.httpBody = try JSONEncoder().encode(body)
        return r
    }

    private func call<Body: Encodable>(_ function: String, _ body: Body) async throws -> Data {
        let (data, response) = try await session.data(for: try request(function, body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw BoardError.server(status: status, body: String(decoding: data.prefix(300), as: UTF8.self))
        }
        return data
    }
}

/// The board as the app shows it: the last page loaded (kept across launches, so it shows at once
/// and while offline) and whether it's up to date.
@MainActor
final class WorldBoard: ObservableObject {
    enum Status: Equatable {
        /// No board is set up in this build.
        case off
        case loading
        case live
        /// The last refresh failed; `page` is whatever was loaded before.
        case offline
    }

    @Published private(set) var page: BoardPage?
    @Published private(set) var updated: Date?
    @Published private(set) var status: Status

    let api: BoardAPI?
    private let defaults: UserDefaults
    private static let cacheKey = "pockethoops.board.v1"

    private struct Cache: Codable {
        let page: BoardPage
        let updated: Date
    }

    init(api: BoardAPI? = .configured, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        status = api == nil ? .off : .offline
        if api != nil, let raw = defaults.data(forKey: WorldBoard.cacheKey),
           let cache = try? JSONDecoder().decode(Cache.self, from: raw) {
            page = cache.page
            updated = cache.updated
        }
    }

    /// Puts the player's Arcade best on the board (if they've joined), then reloads it.
    func refresh(_ progress: PlayerProgress) async {
        guard let api else { status = .off; return }
        status = .loading
        // A failed submit is retried on the next refresh: the server keeps the best, so resending is harmless.
        try? await submitBest(progress, to: api)
        do {
            let fresh = try await api.load(player: progress.boardPlayer?.id)
            page = fresh
            updated = Date()
            status = .live
            if let raw = try? JSONEncoder().encode(Cache(page: fresh, updated: Date())) {
                defaults.set(raw, forKey: WorldBoard.cacheKey)
            }
        } catch {
            status = .offline
        }
    }

    /// After an Arcade game with a new best: sends it in the background.
    func report(_ progress: PlayerProgress) {
        guard let api else { return }
        Task { try? await submitBest(progress, to: api) }
    }

    private func submitBest(_ progress: PlayerProgress, to api: BoardAPI) async throws {
        guard let me = progress.boardPlayer, progress.arcadeBest > 0 else { return }
        try await api.submit(player: me.id, name: me.name, outfit: progress.outfit.code, score: progress.arcadeBest)
    }
}
