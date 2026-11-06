/// Where the app stands when Esc is pressed.
public struct StepBackContext: Equatable {
    /// A dialog, popover, picker or sheet is up.
    public var hasFrontmost = false
    public var isTyping = false
    public var hasSelectedBlock = false
    /// The iPhone's stack, which has a sheet list to go back to.
    public var isCompact = false
    /// A sheet is pushed over that list.
    public var isSheetOpen = false
    public var isSearching = false
    /// Whether a wide layout's rail is on screen.
    public var isRailShowing = true

    public init(hasFrontmost: Bool = false, isTyping: Bool = false, hasSelectedBlock: Bool = false,
                isCompact: Bool = false, isSheetOpen: Bool = false, isSearching: Bool = false,
                isRailShowing: Bool = true) {
        self.hasFrontmost = hasFrontmost; self.isTyping = isTyping
        self.hasSelectedBlock = hasSelectedBlock; self.isCompact = isCompact
        self.isSheetOpen = isSheetOpen; self.isSearching = isSearching
        self.isRailShowing = isRailShowing
    }
}

/// One press of Esc: a step towards the sheet list, so pressing it again and again always ends
/// there. A wide layout has no list of its own to return to, so its rail comes back instead.
public enum StepBack: Equatable {
    case closeFrontmost, endTyping, letGoOfBlock, closeSheet, clearSearch, showRail
    /// Already home.
    case none

    public static func next(_ c: StepBackContext) -> StepBack {
        if c.hasFrontmost { return .closeFrontmost }
        if c.isTyping { return .endTyping }
        if c.hasSelectedBlock { return .letGoOfBlock }
        if c.isCompact && c.isSheetOpen { return .closeSheet }
        if c.isSearching { return .clearSearch }
        if !c.isCompact && !c.isRailShowing { return .showRail }
        return .none
    }
}
