import SwiftUI

/// The world leaderboard: everyone's best Arcade score with their name and character, highest first.
/// The player's own place stays pinned at the bottom however far down they are. Joining is opt-in:
/// nothing is sent until they pick a name.
struct LeaderboardView: View {
    @EnvironmentObject var progress: PlayerProgress
    @EnvironmentObject var board: WorldBoard
    let back: () -> Void

    @State private var naming = false
    @State private var draft = ""
    @State private var blink = false
    @FocusState private var typing: Bool

    private let muted = RGBA(hex: 0xB8C0D8)
    private let faint = RGBA(hex: 0x8088A0)

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(title: "LEADERBOARD", back: back) { EmptyView() }
            PixelText(subtitle, color: muted, px: 1.5)
            list
                .frame(maxHeight: .infinity)
            if board.status != .off { footer }
        }
        .padding(.bottom, 10)
        .background(Palette.navy.color.ignoresSafeArea())
        .task { await board.refresh(progress) }
    }

    private var subtitle: String {
        guard board.status != .off, let page = board.page else { return "BEST ARCADE SCORES" }
        return "BEST ARCADE SCORES · \(page.total) PLAYER\(page.total == 1 ? "" : "S")"
    }

    // MARK: The board

    @ViewBuilder private var list: some View {
        if board.status == .off {
            notice("THE WORLD BOARD ISN'T SWITCHED ON YET", sub: "YOUR ARCADE BEST: \(progress.arcadeBest)")
        } else if let page = board.page {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    if page.top.isEmpty {
                        notice("NO SCORES YET", sub: "BE THE FIRST ONE ON THE BOARD").padding(.top, 60)
                    }
                    ForEach(Array(page.top.enumerated()), id: \.offset) { _, e in row(e, rankWidth: 48) }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
            }
            .refreshable { await board.refresh(progress) }
        } else if board.status == .loading {
            notice("LOADING...", sub: "")
        } else {
            VStack(spacing: 16) {
                notice("CAN'T REACH THE WORLD BOARD", sub: "CHECK YOUR CONNECTION")
                    .frame(maxHeight: 120)
                Button { Task { await board.refresh(progress) } } label: { PixelText("TRY AGAIN", px: 2.5) }
                    .buttonStyle(PixelButtonStyle(fill: Palette.blue))
                    .frame(width: 200)
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// One player: rank (gold, silver and bronze for the top three), character, name and score.
    private func row(_ e: BoardEntry, rankWidth: CGFloat?) -> some View {
        HStack(spacing: 8) {
            PixelText("#\(e.rank)", color: rankColour(e.rank), px: 2)
                .frame(minWidth: rankWidth, alignment: .leading)
            KidBadge(outfit: Outfit(code: e.outfit))
            PixelText(e.name, color: .white, px: 2)
            Spacer(minLength: 4)
            PixelText("\(e.score)", color: Palette.gold, px: 2.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background((e.you ? Palette.blue : Palette.navy.lighter(0.1)).color)
        .overlay(Rectangle().strokeBorder(e.you ? Palette.led.color : Color.black, lineWidth: e.you ? 3 : 2))
    }

    private func rankColour(_ rank: Int) -> RGBA {
        switch rank {
        case 1: return Palette.gold
        case 2: return RGBA(hex: 0xD0D6E4)
        case 3: return RGBA(hex: 0xE0915A)
        default: return .white
        }
    }

    private func notice(_ title: String, sub: String) -> some View {
        VStack(spacing: 12) {
            PixelParagraph(text: title, maxChars: 22, color: .white, px: 2)
            if !sub.isEmpty { PixelParagraph(text: sub, maxChars: 30, color: muted, px: 1.5) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
    }

    // MARK: The player

    /// Pinned under the board: the player's own row (or the way to join), and how fresh the board is.
    private var footer: some View {
        VStack(spacing: 8) {
            if naming || progress.boardPlayer == nil {
                namePanel
            } else if let you = board.page?.you {
                row(you, rankWidth: nil)
            } else if let me = progress.boardPlayer {
                PixelPanel(fill: Palette.blue, border: Palette.led) {
                    VStack(spacing: 8) {
                        PixelText(me.name, px: 2.5)
                        PixelText(progress.arcadeBest > 0 ? "YOUR SCORE GOES UP NEXT UPDATE" : "PLAY ARCADE TO GET ON THE BOARD",
                                  color: muted, px: 1.5)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            // Kept short enough to fit beside CHANGE NAME on the narrowest phone (iPhone SE).
            HStack {
                PixelText(statusText, color: faint, px: 1.5)
                Spacer(minLength: 8)
                if progress.boardPlayer != nil && !naming {
                    Button {
                        draft = progress.data.boardName
                        naming = true
                        typing = true
                    } label: { PixelText("CHANGE NAME", color: Palette.led, px: 1.5) }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private var statusText: String {
        switch board.status {
        case .off: return ""
        case .loading: return "UPDATING..."
        case .offline: return board.page == nil ? "" : "OFFLINE · LAST UPDATE"
        case .live:
            guard let t = board.updated else { return "" }
            let minutes = Int(Date().timeIntervalSince(t) / 60)
            return minutes < 1 ? "UPDATED JUST NOW" : "UPDATED \(minutes) MIN AGO"
        }
    }

    private var namePanel: some View {
        let joined = progress.boardPlayer != nil
        return PixelPanel(fill: Palette.navy.lighter(0.08), border: Palette.led) {
            VStack(spacing: 10) {
                PixelText(joined ? "CHANGE YOUR NAME" : "JOIN THE WORLD BOARD", color: Palette.led, px: 2)
                if !joined {
                    PixelText(progress.arcadeBest > 0 ? "YOUR ARCADE BEST \(progress.arcadeBest) GOES ON IT"
                                                      : "THEN PLAY ARCADE TO GET A SCORE", color: muted, px: 1.5)
                }
                nameBox
                HStack(spacing: 10) {
                    if joined {
                        Button { naming = false; typing = false } label: { PixelText("CANCEL", px: 2.5) }
                            .buttonStyle(PixelButtonStyle(fill: Palette.grey))
                    }
                    Button(action: join) { PixelText(joined ? "SAVE" : "JOIN", px: 2.5) }
                        .buttonStyle(PixelButtonStyle(fill: Palette.green))
                        .opacity(BoardName.final(draft) == nil ? 0.5 : 1)
                        .disabled(BoardName.final(draft) == nil)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The name is typed with the keyboard but drawn in the pixel font: the text field underneath
    /// only takes the typing.
    private var nameBox: some View {
        let empty = draft.isEmpty && !typing
        return ZStack {
            Rectangle().fill(Color.black)
            // Cleaned as it's set, so the field never holds anything the name can't.
            TextField("", text: Binding(get: { draft }, set: { draft = BoardName.clean($0) }))
                .focused($typing)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                .onSubmit(join)
                .foregroundStyle(.clear)
                .tint(.clear)
                .opacity(0.02)
            HStack(spacing: 3) {
                PixelText(empty ? "TAP TO TYPE A NAME" : draft, color: empty ? faint : .white, px: empty ? 1.5 : 2.5)
                if typing {
                    Rectangle().fill(Palette.led.color)
                        .frame(width: 2.5, height: 17.5)
                        .opacity(blink ? 1 : 0)
                        .animation(.easeInOut(duration: 0.45).repeatForever(), value: blink)
                        .onAppear { blink = true }
                }
            }
            .allowsHitTesting(false)
        }
        .frame(height: 44)
        .overlay(Rectangle().strokeBorder(Palette.led.color, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { typing = true }
    }

    private func join() {
        guard progress.joinBoard(name: draft) else { return }
        naming = false
        typing = false
        Task { await board.refresh(progress) }
    }
}
