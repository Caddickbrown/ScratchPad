import Foundation

/// What a sheet's menus hold, so the phone's and the iPad's stay the same. Adding
/// to the sheet is one menu, doing something to it another; anything that isn't
/// about this sheet, such as bringing in an archive, is in Settings.
public enum SheetAction: Equatable, Sendable { case duplicate, export, delete }

public enum SheetMenus {
    public static let insert: [BlockKind] = [.text, .table, .code, .link, .divider]

    public static func symbol(_ kind: BlockKind) -> String {
        switch kind {
        case .text: return "text.alignleft"
        case .table: return "tablecells"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        case .divider: return "minus"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    public static let more: [SheetAction] = [.duplicate, .export, .delete]
}

/// Where the sheets are, in plain words. A container's full path means nothing to
/// anyone reading Settings.
public enum StoreWords {
    public static func place(usingICloud: Bool) -> String { usingICloud ? "iCloud Drive" : "This device" }

    public static func meaning(usingICloud: Bool) -> String {
        usingICloud ? "Your sheets sync across your devices." : "Your sheets stay here and don't sync."
    }

    public static func folder(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }
}
