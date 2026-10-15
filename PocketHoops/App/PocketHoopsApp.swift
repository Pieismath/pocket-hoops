import SwiftUI

@main
struct PocketHoopsApp: App {
    @StateObject private var progress = PlayerProgress()
    @StateObject private var board = WorldBoard()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(progress)
                .environmentObject(board)
                .statusBarHidden()
                .preferredColorScheme(.dark)
        }
    }
}

enum Screen: Equatable {
    case menu
    case game(GameMode)
    case prizes
    case missions
    case leaderboard
}

struct RootView: View {
    @EnvironmentObject var progress: PlayerProgress
    @Environment(\.scenePhase) private var phase
    @State private var screen: Screen = .menu
    /// Bumped to rebuild a game scene for "play again".
    @State private var gameID = 0

    var body: some View {
        ZStack {
            Palette.navy.color.ignoresSafeArea()
            switch screen {
            case .menu:
                MenuView(go: { screen = $0 })
            case let .game(mode):
                GameView(mode: mode, again: { gameID += 1 }, quit: { screen = .menu },
                         leaderboard: { screen = .leaderboard })
                    .id(gameID)
            case .prizes:
                PrizeCounterView(back: { screen = .menu })
            case .missions:
                MissionsView(back: { screen = .menu })
            case .leaderboard:
                LeaderboardView(back: { screen = .menu })
            }
        }
        .onAppear {
            Sound.shared.enabled = progress.data.sound
            Haptics.enabled = progress.data.haptics
            Sound.shared.start()
            #if DEBUG
            // Debug: `-play arcade` jumps straight into a mode, `-screen prizes|missions|leaderboard` opens a screen.
            let args = UserDefaults.standard
            if let m = args.string(forKey: "play").flatMap(GameMode.init(rawValue:)) { screen = .game(m) }
            if args.string(forKey: "screen") == "prizes" { screen = .prizes }
            if args.string(forKey: "screen") == "missions" { screen = .missions }
            if args.string(forKey: "screen") == "leaderboard" { screen = .leaderboard }
            if args.bool(forKey: "rich") { progress.update { $0.tickets = max($0.tickets, 2_000) } }
            #endif
        }
        .onChange(of: phase) { _, p in
            if p == .active { progress.refreshDay(); Sound.shared.start() }
        }
        .onChange(of: progress.data.sound) { _, v in Sound.shared.enabled = v }
        .onChange(of: progress.data.haptics) { _, v in Haptics.enabled = v }
    }
}
