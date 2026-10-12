import SwiftUI
import ScratchpadCore

/// The paper: header strip from the pad, dot-grid canvas, and (when wide) the to-do column at its side.
struct PadView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    let compact: Bool

    private var pad: Binding<Pad> {
        Binding(get: { state.current ?? Pad.daily("") }, set: { state.current = $0 })
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                PadHeader(pad: pad, compact: compact)
                CanvasView()
            }
            .padding(compact ? 12 : 20)
            if !compact {
                Divider().overlay(p.hairline)
                TodoColumnView(compact: false).frame(width: 340)
            }
        }
        .background(p.paper)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 0 : 8))
        .overlay(RoundedRectangle(cornerRadius: compact ? 0 : 8).stroke(p.hairline, lineWidth: compact ? 0 : 1))
        .padding(compact ? 0 : 20)
        .background(p.desk)
        .navigationTitle(compact ? compactTitle : "")
    }

    private var compactTitle: String {
        let p = pad.wrappedValue
        guard let key = p.date, let d = DayKey.date(from: key) else { return p.title.isEmpty ? p.id : p.title }
        return Calendar.current.isDateInToday(d) ? "Today" : d.formatted(.dateTime.weekday(.wide))
    }
}

struct PadHeader: View {
    @Environment(\.palette) var p
    @Binding var pad: Pad
    let compact: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("DATE").font(Fonts.ui(10, .semibold)).tracking(1).foregroundStyle(p.muted)
                Text(dateText).font(Fonts.mono(13)).foregroundStyle(p.ink).lineLimit(1)
            }
            .padding(.horizontal, 12).frame(width: compact ? 150 : 220, alignment: .leading)
            Rectangle().fill(p.rule).frame(width: 1)
            TextField("Title", text: $pad.title).textFieldStyle(.plain).font(Fonts.ui(compact ? 15 : 14, .medium)).foregroundStyle(p.ink)
                .padding(.horizontal, 12)
            if !compact {
                Rectangle().fill(p.rule).frame(width: 1)
                HStack(spacing: 0) {
                    Text("#").font(Fonts.mono(12)).foregroundStyle(p.muted)
                    TextField("tag", text: $pad.tag).textFieldStyle(.plain).font(Fonts.mono(12)).foregroundStyle(p.muted)
                }.padding(.horizontal, 10).frame(width: 92)
            }
        }
        .frame(height: compact ? 36 : 34)
        .overlay(Rectangle().stroke(p.rule, lineWidth: 1))
    }

    private var dateText: String {
        guard let key = pad.date, let d = DayKey.date(from: key) else { return "Pinned" }
        return compact ? d.formatted(.dateTime.day().month(.abbreviated)) : d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }
}
