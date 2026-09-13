import Foundation
import UIKit

public enum InstantPageMathMode {
    case inline
    case block
}

public struct InstantPageMathRenderResult {
    public let image: UIImage
    public let size: CGSize
    public let width: CGFloat
    public let ascent: CGFloat
    public let descent: CGFloat
}

public final class InstantPageMathAttachment: NSObject {
    public let latex: String
    public let fontSize: CGFloat
    public let textColor: UIColor
    public let mode: InstantPageMathMode
    public let rendered: InstantPageMathRenderResult

    public init(latex: String, fontSize: CGFloat, textColor: UIColor, mode: InstantPageMathMode, rendered: InstantPageMathRenderResult) {
        self.latex = latex
        self.fontSize = fontSize
        self.textColor = textColor
        self.mode = mode
        self.rendered = rendered
    }

    func isEqual(to other: InstantPageMathAttachment) -> Bool {
        return self.latex == other.latex
            && self.fontSize == other.fontSize
            && self.mode == other.mode
            && self.textColor.isEqual(other.textColor)
            && self.rendered.size == other.rendered.size
            && self.rendered.ascent == other.rendered.ascent
            && self.rendered.descent == other.rendered.descent
    }
}

public func instantPageMathAttachment(latex: String, fontSize: CGFloat, textColor: UIColor, mode: InstantPageMathMode) -> InstantPageMathAttachment? {
    guard let rendered = instantPageRenderMath(latex: latex, fontSize: fontSize, textColor: textColor, mode: mode) else {
        return nil
    }
    return InstantPageMathAttachment(latex: latex, fontSize: fontSize, textColor: textColor, mode: mode, rendered: rendered)
}

/// UIKit fallback: 11.15 has no SwiftMath. Formulas render as monospaced LaTeX source.
private func instantPageRenderMath(latex: String, fontSize: CGFloat, textColor: UIColor, mode: InstantPageMathMode) -> InstantPageMathRenderResult? {
    let font = UIFont.monospacedSystemFont(ofSize: max(10.0, fontSize * 0.9), weight: .regular)
    let text = latex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
        return nil
    }
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: textColor
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let maxWidth: CGFloat = mode == .block ? 320.0 : 240.0
    let bounds = attributed.boundingRect(with: CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    let size = CGSize(width: ceil(bounds.width) + 4.0, height: ceil(bounds.height) + 2.0)
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    attributed.draw(in: CGRect(origin: CGPoint(x: 2.0, y: 1.0), size: CGSize(width: size.width - 4.0, height: size.height - 2.0)))
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    guard let image else {
        return nil
    }
    return InstantPageMathRenderResult(image: image, size: size, width: size.width, ascent: size.height * 0.8, descent: size.height * 0.2)
}
