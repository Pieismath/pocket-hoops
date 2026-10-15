import SwiftUI

/// The prize counter: balls, cabinets and the shooter's look (characters and accessories).
/// Everything costs tickets and most things also need some playing first; tap an item to
/// preview it (locked ones too), then buy, equip or take it off from the preview.
struct PrizeCounterView: View {
    @EnvironmentObject var progress: PlayerProgress
    let back: () -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case balls = "BALLS", cabinets = "CABINETS", player = "PLAYER"
        var id: String { rawValue }
    }

    enum Page: Hashable, Identifiable {
        case characters
        case wear(AccessoryCategory)
        var id: String { title }
        var title: String {
            switch self {
            case .characters: return "CHARACTERS"
            case let .wear(c): return c.title
            }
        }
        static let all: [Page] = [.characters] + AccessoryCategory.allCases.map { .wear($0) }
    }

    /// One item as the shop shows it.
    struct Entry: Identifiable {
        enum Kind {
            case ball(BallSkin), cabinet(CabinetTheme), avatar(Avatar), accessory(Accessory)
        }

        let kind: Kind
        let id: String
        let name: String
        let price: Int
        let unlock: Unlock
        let owned: Bool
        let equipped: Bool
    }

    @State private var tab: Tab = .balls
    @State private var page: Page = .characters
    /// The previewed item in each list.
    @State private var selection: [String: String] = [:]
    @State private var flash: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 10) {
            ScreenHeader(title: "PRIZE COUNTER", back: back) {
                HStack(spacing: 6) {
                    PixelText("🎟", color: Palette.gold, px: 2.5)
                    PixelText("\(progress.data.tickets)", color: Palette.gold, px: 2.5)
                }
            }
            HStack(spacing: 10) {
                ForEach(Tab.allCases) { t in
                    Button { tab = t } label: { PixelText(t.rawValue, px: 2) }
                        .buttonStyle(PixelButtonStyle(fill: tab == t ? Palette.red : Palette.grey, px: 2.5))
                }
            }
            .padding(.horizontal, 18)
            if tab == .player { pages }
            if let e = selected { preview(e) }
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(entries) { card($0) }
                }
                // Lists share ids ("classic"), so rebuild the grid per list rather than letting
                // SwiftUI reuse one list's card for another's.
                .id(listKey)
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .background(Palette.navy.color.ignoresSafeArea())
        .overlay {
            if let flash {
                PixelText(flash, color: Palette.gold, px: 4, outline: .black)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var pages: some View {
        let rows = [Array(Page.all.prefix(3)), Array(Page.all.dropFirst(3))]
        return VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(rows[r]) { pg in
                        Button { page = pg } label: { PixelText(pg.title, px: 1.5) }
                            .buttonStyle(PixelButtonStyle(fill: page == pg ? Palette.purple : Palette.navy.lighter(0.15), px: 2))
                    }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    // MARK: Items

    private var listKey: String { tab == .player ? page.id : tab.rawValue }

    private var entries: [Entry] {
        let d = progress.data
        switch tab {
        case .balls:
            return BallSkin.all.map {
                Entry(kind: .ball($0), id: $0.id, name: $0.name, price: $0.price, unlock: $0.unlock,
                      owned: d.ownedSkins.contains($0.id), equipped: d.skin == $0.id)
            }
        case .cabinets:
            return CabinetTheme.all.map {
                Entry(kind: .cabinet($0), id: $0.id, name: $0.name, price: $0.price, unlock: $0.unlock,
                      owned: d.ownedThemes.contains($0.id), equipped: d.theme == $0.id)
            }
        case .player:
            switch page {
            case .characters:
                return Avatar.all.map {
                    Entry(kind: .avatar($0), id: $0.id, name: $0.name, price: $0.price, unlock: $0.unlock,
                          owned: d.ownedAvatars.contains($0.id), equipped: d.avatar == $0.id)
                }
            case let .wear(c):
                return Accessory.of(c).map {
                    Entry(kind: .accessory($0), id: $0.id, name: $0.name, price: $0.price, unlock: $0.unlock,
                          owned: d.ownedAccessories.contains($0.id), equipped: d.outfit[c.rawValue] == $0.id)
                }
            }
        }
    }

    private var selected: Entry? {
        let list = entries
        if let id = selection[listKey], let e = list.first(where: { $0.id == id }) { return e }
        return list.first(where: \.equipped) ?? list.first
    }

    /// The look to show an accessory on: the current character if it can wear it, else the rookie.
    private func dressing(_ a: Accessory) -> Outfit {
        let current = progress.outfit
        return Avatar.byID(current.avatar).wears.contains(a.category) ? current.with(a) : Outfit().with(a)
    }

    // MARK: Preview

    private func preview(_ e: Entry) -> some View {
        let d = progress.data
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                bigPicture(e)
                    .frame(width: 116, height: 146)
                VStack(alignment: .leading, spacing: 9) {
                    PixelText(e.name.uppercased(), px: 2.5)
                    status(e)
                    note(e)
                    action(e)
                }
                Spacer(minLength: 0)
            }
            if !e.owned {
                ForEach(e.unlock.requirements.indices, id: \.self) { i in
                    let r = e.unlock.requirements[i]
                    if d.met(r) {
                        PixelText("✓ " + r.text, color: Palette.green.lighter(0.3), px: 1.5)
                    } else {
                        PixelText(r.text + ": " + d.progress(r), color: RGBA(hex: 0xDDE3F5), px: 1.5)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.navy.lighter(0.08).color)
        .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 3))
        .padding(.horizontal, 18)
    }

    @ViewBuilder private func bigPicture(_ e: Entry) -> some View {
        switch e.kind {
        case let .ball(s): BallPreview(skin: s, size: 96, spinning: true)
        case let .cabinet(t): CabinetPreview(theme: t, scale: 1)
        case let .avatar(v): KidPreview(outfit: progress.outfit.with(avatar: v.id), skin: progress.skin)
        case let .accessory(a): KidPreview(outfit: dressing(a), skin: progress.skin)
        }
    }

    @ViewBuilder private func status(_ e: Entry) -> some View {
        if e.equipped {
            PixelText("✓ EQUIPPED", color: Palette.green.lighter(0.3), px: 1.5)
        } else if e.owned {
            PixelText("OWNED", color: RGBA(hex: 0xB8C0D8), px: 1.5)
        } else {
            PixelText("🎟 \(e.price)", color: progress.data.tickets >= e.price ? Palette.gold : RGBA(hex: 0x8088A0), px: 2)
        }
    }

    @ViewBuilder private func note(_ e: Entry) -> some View {
        switch e.kind {
        case let .avatar(v):
            PixelText(v.wearsNote, color: RGBA(hex: 0x8088A0), px: 1.2)
        case let .accessory(a):
            let current = Avatar.byID(progress.data.avatar)
            if !current.wears.contains(a.category) {
                PixelText("NOT WORN BY " + current.name.uppercased(), color: RGBA(hex: 0x8088A0), px: 1.2)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func action(_ e: Entry) -> some View {
        let d = progress.data
        if e.owned {
            if !e.equipped {
                Button { equip(e) } label: { PixelText("EQUIP", px: 2) }
                    .buttonStyle(PixelButtonStyle(fill: Palette.blue, px: 2))
            } else if case let .accessory(a) = e.kind {
                Button { progress.takeOff(a.category) } label: { PixelText("TAKE OFF", px: 2) }
                    .buttonStyle(PixelButtonStyle(fill: Palette.grey, px: 2))
            }
        } else if !d.met(e.unlock) {
            disabled("🔒 LOCKED")
        } else if d.tickets < e.price {
            disabled("NEED 🎟 \(e.price)")
        } else {
            Button { if buy(e) { celebrate() } } label: { PixelText("BUY 🎟 \(e.price)", px: 2) }
                .buttonStyle(PixelButtonStyle(fill: Palette.green, px: 2))
        }
    }

    private func disabled(_ text: String) -> some View {
        PixelText(text, color: RGBA(hex: 0x8088A0), px: 2)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Palette.navy.darker(0.2).color)
            .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 2))
    }

    private func buy(_ e: Entry) -> Bool {
        switch e.kind {
        case let .ball(s): return progress.buySkin(s)
        case let .cabinet(t): return progress.buyTheme(t)
        case let .avatar(v): return progress.buyAvatar(v)
        case let .accessory(a): return progress.buyAccessory(a)
        }
    }

    private func equip(_ e: Entry) {
        switch e.kind {
        case let .ball(s): progress.update { $0.skin = s.id }
        case let .cabinet(t): progress.update { $0.theme = t.id }
        case let .avatar(v): progress.choose(v)
        case let .accessory(a): progress.wear(a)
        }
    }

    // MARK: Cards

    private func card(_ e: Entry) -> some View {
        let d = progress.data
        let locked = !e.owned && !d.met(e.unlock)
        let chosen = selected?.id == e.id
        return Button { selection[listKey] = e.id } label: {
            VStack(spacing: 7) {
                thumb(e)
                PixelText(e.name.uppercased(), px: 1.8)
                if e.equipped {
                    PixelText("✓ EQUIPPED", color: Palette.green.lighter(0.3), px: 1.4)
                } else if e.owned {
                    PixelText("OWNED", color: RGBA(hex: 0xB8C0D8), px: 1.4)
                } else if locked, let r = e.unlock.requirements.first(where: { !d.met($0) }) {
                    PixelText("🔒 \(d.progress(r)) \(r.unit)", color: RGBA(hex: 0x8088A0), px: 1.3)
                } else {
                    PixelText("🎟 \(e.price)", color: d.tickets >= e.price ? Palette.gold : RGBA(hex: 0x8088A0), px: 1.8)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PixelButtonStyle(fill: chosen ? Palette.blue : Palette.navy.lighter(0.12), px: 3))
        .opacity(locked ? 0.72 : 1)
    }

    @ViewBuilder private func thumb(_ e: Entry) -> some View {
        switch e.kind {
        case let .ball(s):
            BallPreview(skin: s, size: 52, spinning: e.equipped).frame(height: 76)
        case let .cabinet(t):
            CabinetPreview(theme: t, scale: 0.62).frame(height: 92)
        case let .avatar(v):
            KidThumb(outfit: progress.outfit.with(avatar: v.id), skin: progress.skin).frame(height: 76)
        case let .accessory(a):
            KidThumb(outfit: Outfit(avatar: Avatar.byID(progress.data.avatar).wears.contains(a.category)
                                    ? progress.data.avatar : Avatar.rookie.id).with(a), skin: progress.skin)
                .frame(height: 76)
        }
    }

    private func celebrate() {
        Sound.shared.play(.fire)
        Haptics.success()
        withAnimation(.spring(duration: 0.3)) { flash = "UNLOCKED!" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation { flash = nil } }
    }
}

struct ScreenHeader<Trailing: View>: View {
    let title: String
    let back: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Button(action: back) { PixelText("◀", px: 3) }
                .buttonStyle(PixelButtonStyle(fill: Palette.grey, px: 2))
                .frame(width: 50)
            Spacer()
            PixelText(title, color: Palette.led, px: 3)
            Spacer()
            trailing.frame(minWidth: 50)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }
}

struct MissionsView: View {
    @EnvironmentObject var progress: PlayerProgress
    let back: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ScreenHeader(title: "MISSIONS", back: back) { EmptyView() }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    PixelText("TODAY", color: .white, px: 2.5)
                    ForEach(progress.data.missions) { m in missionRow(m) }
                    PixelText("NEW MISSIONS EVERY DAY", color: RGBA(hex: 0x8088A0), px: 1.5)

                    PixelPanel(fill: Palette.purple.darker(0.3), border: Palette.purple) {
                        VStack(spacing: 10) {
                            PixelText("DAILY CHALLENGE", color: Palette.led, px: 2.5)
                            PixelText(ModeConfig.make(.daily).modifiers.map(\.label).joined(separator: " + "), px: 1.5)
                            HStack {
                                stat("DAY STREAK", "\(progress.data.dayStreak)")
                                Spacer()
                                stat("TODAY'S BEST", "\(progress.data.dailyBest)")
                            }
                        }
                    }

                    PixelText("CAREER", color: .white, px: 2.5).padding(.top, 8)
                    PixelPanel(fill: Palette.navy.lighter(0.08), border: Palette.blue) {
                        VStack(spacing: 10) {
                            let d = progress.data
                            let pct = d.totalAttempts == 0 ? 0 : Int(Double(d.totalMakes) / Double(d.totalAttempts) * 100)
                            row("GAMES", "\(d.games)")
                            row("BASKETS", "\(d.totalMakes)")
                            row("ACCURACY", "\(pct)%")
                            row("SWISHES", "\(d.totalSwishes)")
                            row("LONGEST STREAK", "\(d.longestStreak)")
                            ForEach(GameMode.allCases.filter { $0 != .versus && $0 != .practice }) { m in
                                row("BEST \(m.title)", "\(d.best[m.rawValue] ?? 0)")
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .background(Palette.navy.color.ignoresSafeArea())
    }

    private func missionRow(_ m: Mission) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PixelText(m.done ? "✓ " + m.text : m.text, color: m.done ? Palette.green.lighter(0.3) : .white, px: 2)
                Spacer()
                PixelText("🎟\(m.reward)", color: Palette.gold, px: 2)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.black)
                    Rectangle().fill((m.done ? Palette.green : Palette.led).color)
                        .frame(width: max(0, (g.size.width - 6) * CGFloat(m.progress) / CGFloat(max(1, m.target))))
                        .padding(3)
                }
            }
            .frame(height: 14)
            PixelText("\(m.progress)/\(m.target)", color: RGBA(hex: 0xB8C0D8), px: 1.5)
        }
        .padding(12)
        .background(Palette.navy.lighter(0.1).color)
        .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 3))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            PixelText(k, color: RGBA(hex: 0xB8C0D8), px: 2)
            Spacer()
            PixelText(v, px: 2)
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(spacing: 6) {
            PixelText(k, color: RGBA(hex: 0xDDE3F5), px: 1.5)
            PixelText(v, color: .white, px: 3)
        }
    }
}
