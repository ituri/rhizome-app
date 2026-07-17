import Foundation

/// A button available in the editor's keyboard toolbar. The user chooses which ones appear and
/// in what order (Settings → Editor toolbar); the order is persisted in `AppModel.editorTools`.
enum EditorTool: String, CaseIterable, Identifiable, Codable {
    case outdent, indent, moveUp, moveDown
    case bold, italic, strikethrough, code
    case link, textColor, highlight
    case todo, numbered
    case image, geo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .outdent: "Outdent"
        case .indent: "Indent"
        case .moveUp: "Move up"
        case .moveDown: "Move down"
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .code: "Inline code"
        case .link: "Link"
        case .textColor: "Text colour"
        case .highlight: "Highlight"
        case .todo: "To-do"
        case .numbered: "Numbered list"
        case .image: "Image"
        case .geo: "Location"
        }
    }

    var icon: String {
        switch self {
        case .outdent: "arrow.left.to.line"
        case .indent: "arrow.right.to.line"
        case .moveUp: "arrow.up"
        case .moveDown: "arrow.down"
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .link: "link"
        case .textColor: "paintpalette"
        case .highlight: "highlighter"
        case .todo: "checkmark.circle"
        case .numbered: "list.number"
        case .image: "photo"
        case .geo: "location"
        }
    }

    /// The default toolbar (a lean set); the rest are available to add in Settings.
    static let defaultOrder: [EditorTool] =
        [.outdent, .indent, .bold, .italic, .link, .highlight, .todo, .image, .geo]
}
