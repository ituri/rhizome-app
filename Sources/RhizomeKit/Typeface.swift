#if canImport(SwiftUI)
import SwiftUI

/// Resolves the selected typeface (`RZTheme.font`) into a concrete `Font`. Shared by the app's
/// views and the display text (RichText) so a run of bold/italic inside a bullet uses the same
/// family as the text around it.
public extension Font {
    /// The selected typeface at `size`. `fixed` keeps the size literal (matching the UITextView
    /// editor, which doesn't scale); pass `false` to follow Dynamic Type.
    static func rzFace(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        italic: Bool = false,
        fixed: Bool = true,
        choice: RZFontChoice = RZTheme.font
    ) -> Font {
        let s = size * choice.sizeFactor
        let bold = weight == .bold || weight == .heavy || weight == .black
        let name = italic ? (bold ? choice.boldItalicName : choice.italicName) : choice.regularName
        if let name {
            let base = fixed ? Font.custom(name, fixedSize: s) : Font.custom(name, size: s)
            return base.weight(weight)
        }
        let system = Font.system(size: s, weight: weight, design: choice == .mono ? .monospaced : .default)
        return italic ? system.italic() : system
    }
}
#endif
