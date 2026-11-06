import Foundation
#if os(iOS)
import Combine
import SwiftUI
import UIKit
#endif

// MARK: - The command menu
// ⌘K, from a hardware keyboard: type a few letters and go somewhere. One version of the behaviour Pippin, Quire,
// MiniOffice and BestShot each have their own copy of, for the apps that came after. An app gives it a `CommandList`
// (what's on the menu), says what each action does, and draws the panel in its own design: this file has the rules
// and the keys, and nothing that shows.
//
// The rules:
//   - Esc closes it, in one press, from anywhere in it. So does ⌘K.
//   - Its keys go to it and nowhere else. It has a window of its own above sheets and the page, and `CommandKeys.chords`
//     holds the shortcuts an app binds underneath as well as the menu's own.
//   - Esc gives the keyboard back to whatever had it, so a composer gets its cursor back.
//   - It never does anything destructive itself. A row that would is marked `confirms`, and its action goes through the
//     app's usual question; `CommandSafety` is what an app's tests hold its list to.
//   - It doesn't open over a question. Chosen over a sheet, a row leaves the sheet the way Esc does, so a draft is asked
//     about or kept as usual, and it only runs once the sheet has gone (`CommandGate`).
//
// The part above `#if os(iOS)` further down is plain Foundation, so it can be tested without an app:
// tests/command_palette_selftest.swift.

/// The letters of `query` in order within `text`, as MiniOffice's palette matches them.
enum CommandMatch {
    /// Runs and word starts score higher, long titles a little lower. Nil when the letters aren't all there.
    static func score(_ query: String, _ text: String) -> Int? {
        let t = Array(text.lowercased())
        var score = 0, at = 0, run = 0
        for ch in query.lowercased() where ch != " " {
            var found = false
            while at < t.count {
                let here = at
                at += 1
                if t[here] == ch {
                    run += 1
                    score += 1 + run * 2 + (here == 0 || t[here - 1] == " " ? 6 : 0)
                    found = true
                    break
                }
                run = 0
            }
            if !found { return nil }
        }
        return score - t.count / 8
    }

    /// What matches, best first; equal scores keep the order they came in.
    static func rank<Item>(_ items: [Item], _ query: String, by text: (Item) -> String) -> [Item] {
        let scored = items.enumerated().compactMap { i, item in score(query, text(item)).map { (item, $0, i) } }
        return scored.sorted { ($0.1, $1.2) > ($1.1, $0.2) }.map(\.0)
    }
}

/// One key prompt: the glyph and what it does.
struct CommandHint: Identifiable, Equatable {
    let key: String
    let label: String
    var id: String { key + label }
}

/// One line of the menu.
struct CommandRow<Action: Equatable>: Equatable, Identifiable {
    enum Step: Equatable {
        case run(Action)
        /// A shorter list to choose from, in the same menu, by the name the app knows it by.
        case open(String)
    }

    var id: String
    var title: String
    var detail: String?
    var symbol: String
    var step: Step
    /// What typing is matched against, when it isn't just the title.
    var search: String
    /// The action goes through the app's own confirmation before it destroys anything.
    var confirms: Bool

    init(_ id: String, _ title: String, detail: String? = nil, symbol: String, step: Step, search: String? = nil,
         confirms: Bool = false) {
        self.id = id; self.title = title; self.detail = detail; self.symbol = symbol; self.step = step
        self.search = search ?? title
        self.confirms = confirms
    }
}

/// What's on an app's menu, as a value: the app builds one from what it has just now.
protocol CommandList: Equatable {
    associatedtype Action: Equatable
    /// `stage` is nil at the top, or the name from `.open`. `typing` is false for the list before anything's typed,
    /// which can be shorter than all that typing can find.
    func rows(stage: String?, typing: Bool) -> [CommandRow<Action>]
    /// The grey words in the box.
    func prompt(stage: String?) -> String
    /// Said in place of the list when nothing matches.
    func nothing(stage: String?) -> String
}

extension CommandList {
    func nothing(stage: String?) -> String { "Nothing here by that name." }
}

enum CommandPaletteLimit {
    /// The most it ever lists: past this, typing is quicker than looking.
    static let rows = 10
}

enum CommandKey: Equatable, CaseIterable { case esc, enter, up, down, tab, backTab, toggle }

struct CommandPalette<List: CommandList>: Equatable {
    typealias Key = CommandKey
    typealias Row = CommandRow<List.Action>

    enum Outcome: Equatable {
        case stay, close
        /// Closed, with this to do.
        case run(List.Action)
    }

    private(set) var stage: String?
    private(set) var query = ""
    private(set) var rows: [Row] = []
    /// The row the keys are on, by id, so the highlight follows the row and not a position: something arriving at the
    /// top can't slide a different row under it.
    private(set) var selected: String?
    private var list: List

    init(_ list: List) {
        self.list = list
        relist()
    }

    var lit: Row? { rows.first { $0.id == selected } }
    var prompt: String { list.prompt(stage: stage) }
    var nothing: String { list.nothing(stage: stage) }

    // MARK: typing

    mutating func type(_ text: String) {
        let clean = text.filter { !$0.isNewline && !($0.asciiValue.map { $0 < 32 || $0 == 127 } ?? false) }
        guard !clean.isEmpty else { return }
        query = String((query + clean).prefix(60))
        relist()
    }

    /// One letter back. With none left, back out of a shorter list.
    mutating func backspace() {
        if query.isEmpty {
            guard stage != nil else { return }
            stage = nil
        } else {
            query.removeLast()
        }
        relist()
    }

    // MARK: following the app

    /// What's there changed while the menu is open. A highlight whose row has gone is dropped rather than moved on, so
    /// a stray Return does nothing.
    mutating func refresh(_ list: List) {
        self.list = list
        rows = listed()
        if !rows.contains(where: { $0.id == selected }) { selected = nil }
    }

    // MARK: keys

    mutating func press(_ key: Key) -> Outcome {
        switch key {
        case .esc, .toggle: return .close
        case .up, .backTab: move(-1)
        case .down, .tab: move(1)
        case .enter:
            guard let row = lit else { return .stay }
            switch row.step {
            case .run(let action): return .run(action)
            case .open(let next):
                stage = next
                query = ""
                relist()
            }
        }
        return .stay
    }

    /// Down the list as it's drawn, wrapping round. With nothing lit, the first row.
    private mutating func move(_ by: Int) {
        guard !rows.isEmpty else { return }
        guard let i = rows.firstIndex(where: { $0.id == selected }) else {
            selected = rows[0].id
            return
        }
        selected = rows[(i + by + rows.count) % rows.count].id
    }

    /// Exactly the keys that do something right now.
    var hints: [CommandHint] {
        var out: [CommandHint] = []
        if rows.count > 1 { out.append(.init(key: "↑↓ ⇥", label: "Move")) }
        if lit != nil { out.append(.init(key: "↩", label: "Go")) }
        out.append(.init(key: "Type", label: "To find"))
        if !query.isEmpty { out.append(.init(key: "⌫", label: "A letter")) }
        else if stage != nil { out.append(.init(key: "⌫", label: "Back")) }
        out.append(.init(key: "⎋ ⌘K", label: "Close"))
        return out
    }

    // MARK: the list

    private mutating func relist() {
        rows = listed()
        selected = rows.first?.id
    }

    private func listed() -> [Row] {
        let blank = query.allSatisfy { $0 == " " }
        let pool = list.rows(stage: stage, typing: !blank)
        return Array((blank ? pool : CommandMatch.rank(pool, query, by: \.search)).prefix(CommandPaletteLimit.rows))
    }
}

// MARK: - The keys, as values

struct CommandMods: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let command = CommandMods(rawValue: 1)
    static let alternate = CommandMods(rawValue: 2)
    static let shift = CommandMods(rawValue: 4)
    static let control = CommandMods(rawValue: 8)
}

enum CommandInput: Hashable, Sendable {
    case esc, up, down, left, right, pageUp, pageDown, home, end
    case text(String)
}

struct CommandChord: Hashable, Sendable {
    var input: CommandInput
    var mods: CommandMods
    init(_ input: CommandInput, _ mods: CommandMods = []) { self.input = input; self.mods = mods }
}

enum CommandKeys {
    /// What a key means to the menu, if anything.
    static func meaning(_ chord: CommandChord) -> CommandKey? {
        switch (chord.input, chord.mods) {
        case (.esc, []): return .esc
        case (.up, []): return .up
        case (.down, []): return .down
        case (.text("\r"), []): return .enter
        case (.text("\t"), []): return .tab
        case (.text("\t"), [.shift]): return .backTab
        case (.text("k"), [.command]): return .toggle
        default: return nil
        }
    }

    /// Everything the menu takes for itself while it's up: its own keys, and any shortcut the page behind could be
    /// listening for. Plain letters aren't here, because they're the typing.
    static let chords: [CommandChord] = {
        var out: [CommandChord] = [.init(.esc), .init(.text("\r")), .init(.text("\t")), .init(.text("\t"), .shift)]
        for arrow: CommandInput in [.up, .down, .left, .right] {
            out += [.init(arrow), .init(arrow, .alternate), .init(arrow, .command)]
        }
        out += [.init(.pageUp), .init(.pageDown), .init(.home), .init(.end)]
        let sets: [CommandMods] = [.command, [.command, .shift], [.command, .alternate], [.command, .alternate, .shift],
                                   [.command, .control], .control]
        for mods in sets {
            for ch in "abcdefghijklmnopqrstuvwxyz0123456789,./;'[]\\-=`" { out.append(.init(.text(String(ch)), mods)) }
        }
        return out
    }()
}

// MARK: - Choosing something over a sheet

enum CommandGate {
    enum Step: Equatable {
        case run
        /// Close the sheet the way Esc does.
        case leave
        case wait
        /// The sheet stayed: it's asking about a draft, and that comes first.
        case drop
    }

    /// How long a sheet gets to go, in seconds.
    static let patience = 1.2

    static func step(sheetUp: Bool, waited: Double) -> Step {
        guard sheetUp else { return .run }
        if waited == 0 { return .leave }
        return waited < patience ? .wait : .drop
    }
}

// MARK: - Destructive rows

enum CommandSafety {
    private static let words: Set<String> = ["delete", "remove", "clear", "erase", "wipe", "reset", "discard", "trash",
                                             "unsubscribe", "empty", "sign", "log", "overwrite", "replace", "forget",
                                             "destroy", "purge", "drop", "disconnect"]

    private static func sounds(_ text: String) -> Bool {
        let parts = text.lowercased().split { !$0.isLetter }.map(String.init)
        for (i, part) in parts.enumerated() where words.contains(part) {
            // "Log" and "Sign" alone are ordinary words; "log out" and "sign out" aren't.
            if part == "log" || part == "sign" {
                if i + 1 < parts.count, parts[i + 1] == "out" { return true }
                continue
            }
            return true
        }
        return false
    }

    /// Rows whose words say they destroy something, and which don't say the app will ask first.
    static func unguarded<Action>(_ rows: [CommandRow<Action>]) -> [CommandRow<Action>] {
        rows.filter { !$0.confirms && (sounds($0.title) || sounds($0.search)) }
    }
}

#if os(iOS)

// MARK: - The host
// Quire's arrangement, without Quire in it. The keys go to a text view nobody sees, in a window of its own above sheets
// and the page, so nothing beneath hears them. With the monitor showing things the app draws the menu there, and this
// window only takes the keys.

@MainActor
final class CommandHost<List: CommandList>: ObservableObject {
    @Published private(set) var menu: CommandPalette<List>?
    /// Drawn on the monitor rather than over the phone. Decided when it opens.
    @Published private(set) var onMonitor = false

    /// What's on the menu just now. Nil keeps it shut, as before the app has loaded.
    var list: () -> List? = { nil }
    /// Whether the monitor is showing things, rather than absent, paused or blank.
    var monitorShows: () -> Bool = { false }
    /// Not behind a lock, a monitor question or a system picker. Alerts are already covered.
    var blocked: () -> Bool = { false }
    /// Does what was chosen.
    var perform: (List.Action) -> Void = { _ in }
    /// Closes the sheet on top the way Esc does, asking about a draft as usual.
    var leaveSheet: () -> Void = {}
    /// What the menu's window draws: the dimmed page and the panel, or just a way to tap out with the monitor showing.
    var overlay: () -> AnyView = { AnyView(EmptyView()) }

    private var window: UIWindow?
    private weak var previousKey: UIWindow?
    /// Whatever had the keyboard when the menu came up, given it back by Esc.
    private weak var wasTyping: UIResponder?

    init() {
        CommandRoute.toggle = { [weak self] in self?.toggle() }
    }

    /// ⌘K, from whichever key command heard it.
    func toggle() {
        if menu != nil { close(); return }
        guard !blocked(), !CommandScreen.questionIsUp, let list = list(), let scene = CommandScreen.scene else { return }
        onMonitor = monitorShows()
        menu = CommandPalette(list)
        wasTyping = CommandScreen.firstResponder
        previousKey = scene.windows.first(where: \.isKeyWindow)

        let host = UIHostingController(rootView: overlay())
        host.view.backgroundColor = .clear
        let top = UIWindow(windowScene: scene)
        top.rootViewController = host
        top.backgroundColor = .clear
        // A new window follows the system, not the light or dark the app has chosen.
        top.overrideUserInterfaceStyle = previousKey?.traitCollection.userInterfaceStyle ?? .unspecified
        // Above sheets; an app's lock screen sits higher still.
        top.windowLevel = .alert
        top.makeKeyAndVisible()
        let field = CommandField()
        field.typed = { [weak self] in self?.menu?.type($0) }
        field.deleted = { [weak self] in self?.menu?.backspace() }
        top.addSubview(field)
        window = top
        CommandRoute.heard = { [weak self] in self?.press($0) }
    }

    func close() {
        guard menu != nil else { return }
        menu = nil
        CommandRoute.heard = nil
        window?.isHidden = true
        window = nil
        previousKey?.makeKey()
        let field = wasTyping
        wasTyping = nil
        DispatchQueue.main.async { field?.becomeFirstResponder() }
    }

    func press(_ key: CommandKey) {
        guard let outcome = menu?.press(key) else { return }
        switch outcome {
        case .stay: break
        case .close: close()
        case .run(let action):
            // It's going somewhere: the keyboard isn't handed back to what's being left.
            wasTyping = nil
            close()
            // On the next turn, not inside the key's own handling: changing things from there is what hung Quire.
            DispatchQueue.main.async { [weak self] in self?.settle(action, waited: 0) }
        }
    }

    private func settle(_ action: List.Action, waited: Double) {
        let again = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.settle(action, waited: waited + 0.15) }
        }
        switch CommandGate.step(sheetUp: CommandScreen.sheetIsUp, waited: waited) {
        case .run: perform(action)
        case .leave: leaveSheet(); again()
        case .wait: again()
        case .drop: break
        }
    }

    /// What's on the menu changed while it's open.
    func refresh() {
        guard menu != nil, let list = list() else { return }
        menu?.refresh(list)
    }
}

/// Where the keys go. One menu per app, so one route.
@MainActor
enum CommandRoute {
    fileprivate(set) static var toggle: (() -> Void)?
    fileprivate(set) static var heard: ((CommandKey) -> Void)?

    static func pressToggle() { toggle?() }
}

/// Reading the screen, for the host.
@MainActor
enum CommandScreen {
    private static var windows: [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }.flatMap(\.windows)
    }

    static var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// What's on top of the window with the keyboard, if anything is presented over it.
    private static var top: UIViewController? {
        guard var top = windows.first(where: \.isKeyWindow)?.rootViewController?.presentedViewController else { return nil }
        while let next = top.presentedViewController { top = next }
        return top
    }

    static var sheetIsUp: Bool { top != nil }
    /// An alert or a confirmation dialog: both are this underneath.
    static var questionIsUp: Bool { top is UIAlertController }

    private static weak var captured: UIResponder?

    static var firstResponder: UIResponder? {
        captured = nil
        UIApplication.shared.sendAction(#selector(UIResponder.kitCaptureFirstResponder), to: nil, from: nil, for: nil)
        return captured
    }

    fileprivate static func capture(_ responder: UIResponder) { captured = responder }
}

// MARK: - Keys, on the responder chain

@MainActor
enum CommandResponders {
    private typealias Getter = @convention(c) (AnyObject, Selector) -> NSArray?

    private static func uiInput(_ input: CommandInput) -> String {
        switch input {
        case .esc: return UIKeyCommand.inputEscape
        case .up: return UIKeyCommand.inputUpArrow
        case .down: return UIKeyCommand.inputDownArrow
        case .left: return UIKeyCommand.inputLeftArrow
        case .right: return UIKeyCommand.inputRightArrow
        case .pageUp: return UIKeyCommand.inputPageUp
        case .pageDown: return UIKeyCommand.inputPageDown
        case .home: return UIKeyCommand.inputHome
        case .end: return UIKeyCommand.inputEnd
        case .text(let text): return text
        }
    }

    private static func command(_ chord: CommandChord) -> UIKeyCommand {
        var flags: UIKeyModifierFlags = []
        if chord.mods.contains(.command) { flags.insert(.command) }
        if chord.mods.contains(.alternate) { flags.insert(.alternate) }
        if chord.mods.contains(.shift) { flags.insert(.shift) }
        if chord.mods.contains(.control) { flags.insert(.control) }
        let c = UIKeyCommand(input: uiInput(chord.input), modifierFlags: flags,
                             action: #selector(UIResponder.kitCommandKey(_:)))
        // Otherwise a text view takes them for itself.
        c.wantsPriorityOverSystemBehavior = true
        // These are the characters printed on the keys.
        c.allowsAutomaticLocalization = false
        c.allowsAutomaticMirroring = false
        return c
    }

    static let toggle = command(CommandChord(.text("k"), .command))
    /// Everything the menu takes while it's up, declared on its own field.
    static let held = CommandKeys.chords.map { command($0) }

    static func key(for command: UIKeyCommand) -> CommandKey? {
        let flags = command.modifierFlags
        var mods: CommandMods = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.alternate) { mods.insert(.alternate) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.control) { mods.insert(.control) }
        let input: CommandInput
        switch command.input {
        case UIKeyCommand.inputEscape: input = .esc
        case UIKeyCommand.inputUpArrow: input = .up
        case UIKeyCommand.inputDownArrow: input = .down
        case let text?: input = .text(text)
        case nil: return nil
        }
        return CommandKeys.meaning(CommandChord(input, mods))
    }

    /// Once, at launch: ⌘K on every text field and text view, SwiftUI's included, ahead of the text system, and on every
    /// window, which is the end of the responder chain wherever the keyboard is. `keyCommands` is wrapped in place,
    /// keeping whatever the class declared, as the apps' own Esc is.
    static func install() {
        wrap(UITextField.self)
        wrap(UITextView.self)
        wrap(UIWindow.self)
    }

    private static func wrap(_ type: AnyClass) {
        let selector = #selector(getter: UIResponder.keyCommands)
        guard let method = class_getInstanceMethod(type, selector) else { return }
        // The class's own if it has one, or else what it inherits.
        let original = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        let block: @convention(block) (AnyObject) -> NSArray? = { responder in
            let own = original(responder, selector) as? [UIKeyCommand] ?? []
            // Mid-composition the keys belong to the input method.
            let composing = MainActor.assumeIsolated { (responder as? UITextInput)?.markedTextRange != nil }
            if composing { return own as NSArray }
            return MainActor.assumeIsolated { own + [toggle] } as NSArray
        }
        let wrapped = imp_implementationWithBlock(block)
        if !class_addMethod(type, selector, wrapped, method_getTypeEncoding(method)) {
            method_setImplementation(method, wrapped)
        }
    }
}

extension UIResponder {
    @objc func kitCommandKey(_ command: UIKeyCommand) {
        MainActor.assumeIsolated {
            let key = CommandResponders.key(for: command)
            if let heard = CommandRoute.heard {
                // Held keys mean nothing, and that's the point of them.
                if let key { heard(key) }
            } else if key == .toggle {
                CommandRoute.pressToggle()
            }
        }
    }

    @objc fileprivate func kitCaptureFirstResponder() {
        MainActor.assumeIsolated { CommandScreen.capture(self) }
    }
}

/// ⌘K for a screen with nothing else holding the keyboard, and the name iPad lists when ⌘ is held. There to be heard,
/// not seen.
struct CommandMenuShortcut: View {
    var body: some View {
        Button("Command Menu") { CommandRoute.pressToggle() }
            .keyboardShortcut("k", modifiers: .command)
            .frame(width: 0, height: 0).opacity(0)
            .accessibilityHidden(true)
    }
}

/// Where typing lands while the menu is up: out of sight, always empty, and the letters go to the menu. No on-screen
/// keyboard: ⌘K means there's a real one.
private final class CommandField: UITextView, UITextViewDelegate {
    var typed: (String) -> Void = { _ in }
    var deleted: () -> Void = {}

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1), textContainer: nil)
        delegate = self
        alpha = 0
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        inputView = UIView()
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        autocorrectionType = .no
        spellCheckingType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
    }

    required init?(coder: NSCoder) { fatalError("Built in code.") }

    override var keyCommands: [UIKeyCommand]? { CommandResponders.held }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { DispatchQueue.main.async { self.becomeFirstResponder() } }
    }

    override func deleteBackward() {
        MainActor.assumeIsolated { deleted() }
    }

    func textView(_ v: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        MainActor.assumeIsolated {
            if text.isEmpty { deleted() } else { typed(text) }
        }
        return false
    }
}

#endif
