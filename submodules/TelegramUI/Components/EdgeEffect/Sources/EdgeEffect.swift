import Foundation
import UIKit
import Display
import ComponentFlow
import ComponentDisplayAdapters

/// 11.15-styled edge fade. Replaces 12.9 Liquid Glass `EdgeEffectView` (iOS 26 APIs).
public class EdgeEffectView: UIView {
    public enum Edge {
        case top
        case bottom
    }

    private let contentView = UIView()
    private let contentMaskView = UIImageView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.mask = self.contentMaskView
        self.addSubview(self.contentView)
        self.isUserInteractionEnabled = false
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func updateColor(color: UIColor, transition: ComponentTransition) {
        transition.setBackgroundColor(view: self.contentView, color: color)
    }

    public func update(content: UIColor?, blur: Bool = false, alpha: CGFloat = 0.75, rect: CGRect, edge: Edge, edgeSize: CGFloat, transition: ComponentTransition) {
        if let content {
            transition.setBackgroundColor(view: self.contentView, color: content)
        }
        transition.setAlpha(view: self.contentView, alpha: alpha)
        let bounds = CGRect(origin: .zero, size: rect.size)
        transition.setFrame(view: self.contentView, frame: bounds)
        transition.setFrame(view: self.contentMaskView, frame: bounds)
        if self.contentMaskView.image?.size.height != edgeSize, edgeSize > 0.0 {
            self.contentMaskView.image = EdgeEffectView.generateEdgeGradient(baseHeight: edgeSize, isInverted: edge == .bottom)
        }
    }

    static func generateEdgeGradient(baseHeight: CGFloat, isInverted: Bool) -> UIImage? {
        let height = max(1.0, baseHeight)
        let size = CGSize(width: 1.0, height: height)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        let colors = isInverted
            ? [UIColor.white.withAlphaComponent(0.0).cgColor, UIColor.white.cgColor]
            : [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.0).cgColor]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 1.0]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: height), options: [])
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}

public final class EdgeEffectComponent: Component {
    public let content: UIColor?
    public let blur: Bool
    public let alpha: CGFloat
    public let edge: EdgeEffectView.Edge
    public let edgeSize: CGFloat

    public init(content: UIColor?, blur: Bool = false, alpha: CGFloat = 0.75, edge: EdgeEffectView.Edge, edgeSize: CGFloat) {
        self.content = content
        self.blur = blur
        self.alpha = alpha
        self.edge = edge
        self.edgeSize = edgeSize
    }

    public static func ==(lhs: EdgeEffectComponent, rhs: EdgeEffectComponent) -> Bool {
        return lhs.content == rhs.content && lhs.blur == rhs.blur && lhs.alpha == rhs.alpha && lhs.edge == rhs.edge && lhs.edgeSize == rhs.edgeSize
    }

    public final class View: EdgeEffectView {
        func update(component: EdgeEffectComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.update(content: component.content, blur: component.blur, alpha: component.alpha, rect: CGRect(origin: .zero, size: availableSize), edge: component.edge, edgeSize: component.edgeSize, transition: transition)
            return availableSize
        }
    }

    public func makeView() -> View {
        return View()
    }

    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
