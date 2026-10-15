import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var progress: PlayerProgress
    let result: GameResult
    let payout: PlayerProgress.Payout
    let again: () -> Void
    let quit: () -> Void
    /// Opens the world leaderboard (Arcade games only).
    var leaderboard: (() -> Void)? = nil

    @State private var shownTickets = 0
    @State private var shownScore = 0
    @State private var bestPulse = false

    var body: some View {
        ZStack {
            Palette.navy.darker(0.55).color.opacity(0.94).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Spacer(minLength: 70)
                    header
                    if isVersus { playerCards } else { statsGrid }
                    ticketStrip
                    if payout.bestBonus > 0 || !payout.completedMissions.isEmpty { bonuses }
                    if let s = payout.dailyStreak {
                        PixelText("🔥 DAILY STREAK: \(s) DAY\(s == 1 ? "" : "S")", color: Palette.led, px: 2)
                    }
                    VStack(spacing: 14) {
                        Button(action: again) { PixelText("PLAY AGAIN", px: 3.5) }
                            .buttonStyle(PixelButtonStyle(fill: Palette.green))
                        if let leaderboard {
                            Button(action: leaderboard) { PixelText("🏆 LEADERBOARD", px: 3) }
                                .buttonStyle(PixelButtonStyle(fill: Palette.purple))
                        }
                        Button(action: quit) { PixelText("MENU", px: 3) }
                            .buttonStyle(PixelButtonStyle(fill: Palette.blue))
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 6)
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 18)
            }
        }
        .task { await countUp() }
    }

    private var isVersus: Bool { result.mode == .versus && result.players.count == 2 }

    @ViewBuilder private var header: some View {
        if isVersus {
            // Each player's score heads their own card below.
            let (a, b) = (result.playerScores[0], result.playerScores[1])
            PixelText(a == b ? "TIE GAME!" : (a > b ? "PLAYER 1 WINS!" : "PLAYER 2 WINS!"), color: Palette.led, px: 4)
        } else {
            VStack(spacing: 10) {
                PixelText(result.mode == .streak || result.mode == .practice ? "BASKETS" : "FINAL SCORE",
                          color: Palette.led, px: 3)
                PixelText("\(shownScore)", color: .white, px: 10)
                if payout.newBest {
                    PixelText("★ NEW BEST! ★", color: Palette.gold, px: 3)
                        .scaleEffect(bestPulse ? 1.12 : 0.95)
                        .animation(.easeInOut(duration: 0.4).repeatForever(), value: bestPulse)
                        .onAppear { bestPulse = true }
                } else if payout.previousBest > 0 && result.mode != .practice {
                    PixelText("BEST \(payout.previousBest)", color: RGBA(hex: 0xB8C0D8), px: 2)
                }
                if result.mode == .arcade && result.stage > 1 {
                    PixelText("REACHED STAGE \(result.stage)", color: Palette.green, px: 2)
                }
            }
        }
    }

    struct StatLine: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// What a stats card lists, in order: the same lines for a one-player game and for each player
    /// of a two-player one.
    static func lines(_ s: PlayerStats) -> [StatLine] {
        [StatLine(label: "MADE", value: "\(s.makes)/\(s.attempts)"),
         StatLine(label: "ACCURACY", value: "\(s.accuracyPercent)%"),
         StatLine(label: "SWISHES", value: "\(s.swishes)"),
         StatLine(label: "BANK SHOTS", value: "\(s.banks)"),
         StatLine(label: "BEST STREAK", value: "\(s.bestStreak)"),
         StatLine(label: "ON FIRE", value: "\(s.fires)X")]
    }

    private var statsGrid: some View {
        PixelPanel(fill: Palette.navy, border: Palette.blue) {
            VStack(spacing: 10) {
                ForEach(ResultsView.lines(result.stats)) { row($0.label, $0.value) }
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            PixelText(k, color: RGBA(hex: 0xB8C0D8), px: 2)
            Spacer()
            PixelText(v, color: .white, px: 2)
        }
    }

    /// Two-player games: a card per player, P1 on the left as on the machine's PLAYER: I II strip.
    private var playerCards: some View {
        let top = result.playerScores.max() ?? 0
        return HStack(alignment: .top, spacing: 12) {
            ForEach(Array(result.players.enumerated()), id: \.offset) { i, p in
                playerCard(i + 1, p, winning: p.score == top)
            }
        }
    }

    /// The winner's card (both, on a tie) is edged in the gold its score is drawn in. Half-width
    /// cards use smaller labels so the longest line still fits beside its number on a small phone.
    private func playerCard(_ n: Int, _ p: PlayerStats, winning: Bool) -> some View {
        PixelPanel(fill: Palette.navy, border: winning ? Palette.gold : Palette.blue) {
            VStack(spacing: 10) {
                PixelText("PLAYER \(n)", color: Palette.led, px: 2.5)
                PixelText("\(p.score)", color: winning ? Palette.gold : .white, px: 6)
                VStack(spacing: 9) {
                    ForEach(ResultsView.lines(p)) { l in
                        HStack(spacing: 4) {
                            PixelText(l.label, color: RGBA(hex: 0xB8C0D8), px: 1.5)
                            Spacer(minLength: 0)
                            PixelText(l.value, color: .white, px: 2)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var ticketStrip: some View {
        HStack(spacing: 10) {
            PixelText("🎟", color: Palette.gold, px: 4)
            PixelText("+\(shownTickets) TICKETS", color: Palette.gold, px: 3)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Palette.red.darker(0.3).color)
        .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 3))
    }

    private var bonuses: some View {
        VStack(spacing: 8) {
            if payout.bestBonus > 0 {
                PixelText("✓ NEW BEST +\(payout.bestBonus)", color: Palette.gold, px: 2)
            }
            ForEach(payout.completedMissions) { m in
                PixelText("✓ \(m.text) +\(m.reward)", color: Palette.green, px: 2)
            }
        }
    }

    private func countUp() async {
        let target = result.mode == .streak || result.mode == .practice ? result.makes : result.score
        let steps = min(target, 30)
        for i in 0...max(steps, 0) {
            shownScore = steps == 0 ? target : target * i / steps
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        shownScore = target
        // Tickets spit out like the machine.
        for i in 0...payout.tickets {
            shownTickets = i
            if i % 2 == 0 { Sound.shared.play(.ticket) }
            try? await Task.sleep(nanoseconds: UInt64(max(12_000_000, 700_000_000 / max(payout.tickets, 1))))
        }
        if payout.newBest { Haptics.success(); Sound.shared.play(.fire) }
    }
}
