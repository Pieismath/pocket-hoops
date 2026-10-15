import SpriteKit
import SwiftUI

struct GameView: View {
    @EnvironmentObject var progress: PlayerProgress
    @EnvironmentObject var board: WorldBoard
    let mode: GameMode
    let again: () -> Void
    let quit: () -> Void
    let leaderboard: () -> Void

    @State private var scene: GameScene?
    @State private var paused = false
    @State private var result: GameResult?
    @State private var payout: PlayerProgress.Payout?
    @State private var swapWaiting = false
    @State private var blink = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let full = CGSize(width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                              height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
            ZStack(alignment: .top) {
                if let scene {
                    SpriteView(scene: scene, preferredFramesPerSecond: 120, options: [.ignoresSiblingOrder])
                        .ignoresSafeArea()
                }

                // Pause / end buttons tucked into the corners beside the Dynamic Island.
                if result == nil {
                    HStack {
                        Button { setPaused(true) } label: { PixelText("II", color: .white, px: 2.5) }
                            .buttonStyle(PixelButtonStyle(fill: Palette.grey, px: 2))
                            .frame(width: 54)
                        Spacer()
                        if mode == .practice {
                            Button { scene?.endNow() } label: { PixelText("END", color: .white, px: 2.5) }
                                .buttonStyle(PixelButtonStyle(fill: Palette.red, px: 2))
                                .frame(width: 72)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, max(6, geo.safeAreaInsets.top - 44))
                    .ignoresSafeArea()
                }

                if swapWaiting {
                    PixelPanel(fill: Palette.navy, border: Palette.red) {
                        VStack(spacing: 14) {
                            PixelText("PLAYER 2", color: Palette.led, px: 5)
                            PixelText("PASS THE PHONE", color: .white, px: 3)
                            PixelText("TAP TO START", color: Palette.green.lighter(0.3), px: 2.5)
                                .opacity(blink ? 1 : 0.25)
                                .animation(.easeInOut(duration: 0.5).repeatForever(), value: blink)
                                .onAppear { blink = true }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }

                if paused {
                    PauseMenu(resume: { setPaused(false) }, restart: again, quit: quit)
                }

                if let result, let payout {
                    // The world leaderboard ranks Arcade scores, so Arcade results link to it.
                    ResultsView(result: result, payout: payout, again: again, quit: quit,
                                leaderboard: mode == .arcade ? leaderboard : nil)
                        .transition(.opacity)
                }
            }
            .onAppear { build(full: full, insets: geo.safeAreaInsets) }
        }
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .animation(.easeOut(duration: 0.25), value: result)
    }

    private func build(full: CGSize, insets: EdgeInsets) {
        guard scene == nil, full.width > 0 else { return }
        let layout = SceneLayout.make(view: full, safeTop: insets.top, safeBottom: insets.bottom,
                                      displayScale: displayScale, withHUD: true)
        let s = GameScene(size: layout.sceneSize, area: layout.area, config: ModeConfig.make(mode),
                          skin: progress.skin, theme: progress.theme, outfit: progress.outfit)
        s.onFinish = { r in
            DispatchQueue.main.async {
                let pay = progress.record(r)
                payout = pay
                result = r
                if r.mode == .arcade && pay.newBest { board.report(progress) }
            }
        }
        s.onStateChange = { st in
            DispatchQueue.main.async { swapWaiting = st == .swap }
        }
        scene = s
    }

    private func setPaused(_ p: Bool) {
        paused = p
        scene?.setPaused(p)
    }
}

struct PauseMenu: View {
    let resume: () -> Void
    let restart: () -> Void
    let quit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            PixelPanel(fill: Palette.navy, border: Palette.red) {
                VStack(spacing: 16) {
                    PixelText("PAUSED", color: Palette.led, px: 4)
                    Button(action: resume) { PixelText("RESUME", px: 3) }
                        .buttonStyle(PixelButtonStyle(fill: Palette.green))
                    Button(action: restart) { PixelText("RESTART", px: 3) }
                        .buttonStyle(PixelButtonStyle(fill: Palette.blue))
                    Button(action: quit) { PixelText("QUIT", px: 3) }
                        .buttonStyle(PixelButtonStyle(fill: Palette.red))
                }
                .frame(width: 220)
            }
        }
    }
}
