import SpriteKit
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var progress: PlayerProgress
    let go: (Screen) -> Void
    @State private var attract: GameScene?
    @State private var titleBob = false
    @State private var showSettings = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let full = CGSize(width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                              height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
            ZStack {
                if let attract {
                    SpriteView(scene: attract, options: [.ignoresSiblingOrder])
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                VStack(spacing: 0) {
                    title
                        .offset(y: titleBob ? -3 : 3)
                        .animation(.easeInOut(duration: 1.1).repeatForever(), value: titleBob)
                        .padding(.top, 8)
                    Spacer()
                    buttons
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

                topBar
                    .padding(.horizontal, 14)
                    .padding(.top, max(6, geo.safeAreaInsets.top - 44))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()

                if showSettings { settings }
            }
            .onAppear {
                titleBob = true
                if attract == nil {
                    // The machine sits between the title and the buttons.
                    let layout = SceneLayout.make(view: full, safeTop: geo.safeAreaInsets.top,
                                                  safeBottom: geo.safeAreaInsets.bottom, displayScale: displayScale,
                                                  reserveTop: 118, reserveBottom: 280, withHUD: false)
                    attract = GameScene(size: layout.sceneSize, area: layout.area, config: ModeConfig.make(.arcade),
                                        skin: progress.skin, theme: progress.theme, outfit: progress.outfit, attract: true)
                    attract?.attractHiScore = progress.data.best[GameMode.arcade.rawValue] ?? 0
                }
            }
        }
    }

    private var topBar: some View {
        // The leaderboard button hangs under the settings button: beside it, it would run into the
        // notch on narrower phones.
        VStack(alignment: .trailing, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    PixelText("🎟", color: Palette.gold, px: 2.5)
                    PixelText("\(progress.data.tickets)", color: Palette.gold, px: 2.5)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.black.opacity(0.75))
                .overlay(Rectangle().strokeBorder(Palette.gold.color, lineWidth: 2))
                Spacer()
                Button { withAnimation { showSettings = true } } label: { PixelText("≡", px: 3) }
                    .buttonStyle(PixelButtonStyle(fill: Palette.grey, px: 2))
                    .frame(width: 50)
            }
            Button { go(.leaderboard) } label: { PixelText("🏆", color: Palette.gold, px: 3) }
                .buttonStyle(PixelButtonStyle(fill: Palette.purple, px: 2))
                .frame(width: 50)
                .accessibilityLabel("Leaderboard")
        }
    }

    private var title: some View {
        VStack(spacing: 6) {
            PixelText("POCKET", color: .white, px: 5, shadow: .black)
            PixelText("HOOPS", color: Palette.led, px: 6, shadow: Palette.red.darker(0.2))
        }
    }

    private var dailyPlayed: Bool { progress.data.lastDailyPlayed == Daily.key(for: Date()) }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button { go(.game(.arcade)) } label: {
                VStack(spacing: 6) {
                    PixelText("▶ PLAY ARCADE", px: 4)
                    PixelText(GameMode.arcade.blurb, color: RGBA(hex: 0xFFE9B0), px: 1.5, shadow: nil)
                }
            }
            .buttonStyle(PixelButtonStyle(fill: Palette.red))

            HStack(spacing: 10) {
                modeButton(.daily, fill: Palette.purple, badge: dailyPlayed ? nil : "NEW",
                           sub: ModeConfig.make(.daily).modifiers.map(\.shortLabel).joined(separator: "+"))
                modeButton(.streak, fill: Palette.blue, badge: nil, sub: "3 LIVES")
            }
            HStack(spacing: 10) {
                modeButton(.versus, fill: Palette.green.darker(0.15), badge: nil, sub: "PASS & PLAY")
                modeButton(.practice, fill: Palette.grey, badge: nil, sub: "AIM COACH")
            }
            HStack(spacing: 10) {
                Button { go(.prizes) } label: { PixelText("PRIZES", px: 2.5) }
                    .buttonStyle(PixelButtonStyle(fill: Palette.gold.darker(0.25)))
                Button { go(.missions) } label: {
                    HStack(spacing: 6) {
                        PixelText("MISSIONS", px: 2.5)
                        let done = progress.data.missions.filter(\.done).count
                        PixelText("\(done)/\(progress.data.missions.count)", color: Palette.led, px: 2)
                    }
                }
                .buttonStyle(PixelButtonStyle(fill: Palette.navy.lighter(0.1)))
            }
        }
    }

    private func modeButton(_ m: GameMode, fill: RGBA, badge: String?, sub: String) -> some View {
        Button { go(.game(m)) } label: {
            VStack(spacing: 5) {
                PixelText(m.title, px: m.title.count > 8 ? 2 : 2.5)
                PixelText(sub, color: RGBA(hex: 0xDDE3F5), px: 1.5, shadow: nil)
            }
            .frame(height: 28)
        }
        .buttonStyle(PixelButtonStyle(fill: fill))
        .overlay(alignment: .topTrailing) {
            if let badge {
                PixelText(badge, color: .white, px: 1.5, shadow: nil)
                    .padding(4)
                    .background(Palette.red.color)
                    .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 2))
                    .offset(x: 6, y: -8)
            }
        }
    }

    private var settings: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { withAnimation { showSettings = false } }
            PixelPanel(fill: Palette.navy, border: Palette.red) {
                VStack(spacing: 14) {
                    PixelText("SETTINGS", color: Palette.led, px: 4)
                    toggle("SOUND", on: progress.data.sound) { progress.update { $0.sound.toggle() } }
                    toggle("HAPTICS", on: progress.data.haptics) { progress.update { $0.haptics.toggle() } }
                    PixelParagraph(text: "SWIPE UP FROM THE BALL. FLICK SPEED = DISTANCE, FLICK DIRECTION = AIM. 3 IN A ROW PUTS YOU ON FIRE FOR DOUBLE POINTS.",
                                   maxChars: 24, color: RGBA(hex: 0xB8C0D8), px: 1.5)
                        .padding(.vertical, 4)
                    Button { withAnimation { showSettings = false } } label: { PixelText("DONE", px: 3) }
                        .buttonStyle(PixelButtonStyle(fill: Palette.green))
                }
                .frame(width: 250)
            }
        }
    }

    private func toggle(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                PixelText(label, px: 2.5)
                Spacer()
                PixelText(on ? "ON" : "OFF", color: on ? Palette.green.lighter(0.3) : RGBA(hex: 0xFF6A6A), px: 2.5)
            }
        }
        .buttonStyle(PixelButtonStyle(fill: Palette.blue))
    }
}
