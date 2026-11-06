//
//  CommandMenu.swift
//
//  ⌘K. What it lists is `ScratchpadCommands.swift`, and what the keys mean is the kit's. This is the
//  glue and the drawing: the panel on paper, over the phone, or on the monitor when there is one
//  (`MonitorBoard`). `RootView` says what each row does, since it owns the sheet list.
//
//  iOS only: the Mac has its menu bar.
//

#if os(iOS)
import SwiftUI
import UIKit

@MainActor
enum ScratchpadCommandMenu {
    static let host: CommandHost<ScratchpadCommandList> = {
        let host = CommandHost<ScratchpadCommandList>()
        host.list = {
            guard let state = MonitorModel.shared.state else { return nil }
            return ScratchpadCommandList(hasSheet: state.current != nil, canUndo: state.deleted != nil)
        }
        host.monitorShows = { MonitorModel.shared.isConnected }
        // The file picker has the screen and its own way out.
        host.blocked = { MonitorModel.shared.state?.showImport ?? false }
        // The way esc goes.
        host.leaveSheet = { MonitorModel.shared.state?.closeFrontmost() }
        host.overlay = { AnyView(Themed { ScratchpadCommandOverlay() }) }
        return host
    }()

    /// Once, at launch.
    static func install() {
        CommandResponders.install()
        _ = host
    }
}

/// The menu's own window: the panel over the dimmed page, unless the monitor has it. Tapping the phone closes it either
/// way.
private struct ScratchpadCommandOverlay: View {
    @ObservedObject private var host = ScratchpadCommandMenu.host

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(host.onMonitor ? 0.001 : 0.18).ignoresSafeArea()
                .onTapGesture { host.close() }
                .accessibilityLabel("Close the menu")
            if let menu = host.menu, !host.onMonitor {
                ScratchpadCommandPanel(menu: menu, showsKeys: true)
                    .padding(.horizontal, 16).padding(.top, 24)
            }
        }
    }
}

/// The menu itself, the same on the phone and the monitor: `z` scales it, as everything on the monitor.
struct ScratchpadCommandPanel: View {
    @Environment(\.palette) private var p
    let menu: CommandPalette<ScratchpadCommandList>
    var z: CGFloat = 1
    /// The monitor has its hint bar for this.
    var showsKeys = false

    private var rowHeight: CGFloat { 54 * z }

    var body: some View {
        VStack(spacing: 0) {
            field
            hairline
            if menu.rows.isEmpty {
                Text(menu.nothing).font(Fonts.ui(16 * z)).foregroundStyle(p.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18 * z).padding(.vertical, 16 * z)
            } else {
                list
            }
            if showsKeys {
                hairline
                keys
            }
        }
        .frame(maxWidth: 580 * z)
        .background(p.paper, in: RoundedRectangle(cornerRadius: 10 * z, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10 * z, style: .continuous).strokeBorder(p.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 18 * z, y: 6 * z)
    }

    private var hairline: some View { Rectangle().fill(p.hairline).frame(height: 1) }

    private var field: some View {
        HStack(spacing: 10 * z) {
            Image(systemName: "magnifyingglass").font(Fonts.ui(15 * z)).foregroundStyle(p.muted)
            HStack(spacing: 1 * z) {
                if !menu.query.isEmpty {
                    Text(menu.query).font(Fonts.ui(20 * z)).foregroundStyle(p.ink)
                        .lineLimit(1).truncationMode(.head)
                }
                Text("|").font(Fonts.ui(20 * z)).foregroundStyle(p.accent)
                if menu.query.isEmpty {
                    Text(menu.prompt).font(Fonts.ui(20 * z)).foregroundStyle(p.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18 * z).frame(minHeight: 52 * z)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(menu.rows) { row in
                        ScratchpadCommandRow(row: row, lit: row.id == menu.selected, z: z).frame(height: rowHeight).id(row.id)
                    }
                }
            }
            .frame(maxHeight: rowHeight * CGFloat(menu.rows.count))
            .onChange(of: menu.selected) { _, id in if let id { proxy.scrollTo(id) } }
        }
    }

    private var keys: some View {
        HStack(spacing: 14 * z) {
            ForEach(menu.hints) { hint in
                HStack(spacing: 4 * z) {
                    Text(hint.key).font(Fonts.mono(11 * z, .medium)).foregroundStyle(p.ink)
                    Text(hint.label).font(Fonts.ui(11 * z)).foregroundStyle(p.muted)
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18 * z).padding(.vertical, 8 * z)
    }
}

private struct ScratchpadCommandRow: View {
    @Environment(\.palette) private var p
    let row: CommandRow<ScratchpadCommand>
    let lit: Bool
    var z: CGFloat = 1

    var body: some View {
        HStack(spacing: 12 * z) {
            Image(systemName: row.symbol).font(Fonts.ui(16 * z))
                .foregroundStyle(lit ? p.accent : p.muted).frame(width: 22 * z)
            VStack(alignment: .leading, spacing: 1 * z) {
                Text(row.title).font(Fonts.ui(17 * z, .medium)).foregroundStyle(p.ink).lineLimit(1)
                if let detail = row.detail {
                    Text(detail).font(Fonts.ui(12 * z)).foregroundStyle(p.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18 * z)
        .frame(maxHeight: .infinity)
        .background(lit ? p.accent.opacity(0.12) : Color.clear)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

#endif
