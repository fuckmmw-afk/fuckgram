import Foundation
import UIKit
import Display
import ComponentFlow
import ComponentDisplayAdapters

/// 11.15-styled stand-in for Telegram 12.9 `GlassBackgroundComponent`.
/// Avoids iOS 26 `UIGlassEffect` so the article editor builds with Xcode 16.2.
public class GlassBackgroundView: UIView {
    public protocol ContentView: UIView {
        var tintMask: UIView { get }
    }

    public struct TintColor: Equatable {
        public enum CustomStyle {
            case `default`
            case clear
        }

        public enum Kind: Equatable {
            case panel
            case clear
            case custom(style: CustomStyle, color: UIColor)
        }

        public let kind: Kind
        public let innerColor: UIColor?
        public let innerInset: CGFloat

        public init(kind: Kind, innerColor: UIColor? = nil, innerInset: CGFloat = 3.0) {
            self.kind = kind
            self.innerColor = innerColor
            self.innerInset = innerInset
        }
    }

    public struct CornerRadii: Equatable {
        public let topLeft: CGFloat
        public let topRight: CGFloat
        public let bottomLeft: CGFloat
        public let bottomRight: CGFloat

        public init(topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) {
            self.topLeft = topLeft
            self.topRight = topRight
            self.bottomLeft = bottomLeft
            self.bottomRight = bottomRight
        }

        public init(radius: CGFloat) {
            self.init(topLeft: radius, topRight: radius, bottomLeft: radius, bottomRight: radius)
        }
    }

    public enum Shape: Equatable {
        case roundedRect(cornerRadius: CGFloat)
        case roundedRectRadii(CornerRadii)
    }

    public static var useCustomGlassImpl: Bool = true

    public let contentView = SparseContainerView()
    private let blurView: UIVisualEffectView
    private let fillView = UIView()

    public override init(frame: CGRect) {
        self.blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        super.init(frame: frame)
        self.clipsToBounds = true
        self.addSubview(self.blurView)
        self.addSubview(self.fillView)
        self.addSubview(self.contentView)
        self.fillView.isUserInteractionEnabled = false
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(size: CGSize, cornerRadius: CGFloat, isDark: Bool, tintColor: TintColor, isInteractive: Bool = false, isVisible: Bool = true, transition: ComponentTransition) {
        self.update(size: size, shape: .roundedRect(cornerRadius: cornerRadius), isDark: isDark, tintColor: tintColor, isInteractive: isInteractive, isVisible: isVisible, transition: transition)
    }

    public func update(size: CGSize, cornerRadii: CornerRadii, isDark: Bool, tintColor: TintColor, isInteractive: Bool = false, isVisible: Bool = true, transition: ComponentTransition) {
        self.update(size: size, shape: .roundedRectRadii(cornerRadii), isDark: isDark, tintColor: tintColor, isInteractive: isInteractive, isVisible: isVisible, transition: transition)
    }

    public func update(size: CGSize, shape: Shape, isDark: Bool, tintColor: TintColor, isInteractive: Bool = false, isVisible: Bool = true, transition: ComponentTransition) {
        let bounds = CGRect(origin: .zero, size: size)
        transition.setFrame(view: self.blurView, frame: bounds)
        transition.setFrame(view: self.fillView, frame: bounds)
        transition.setFrame(view: self.contentView, frame: bounds)

        switch shape {
        case let .roundedRect(cornerRadius):
            transition.setCornerRadius(layer: self.layer, cornerRadius: cornerRadius)
            self.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case let .roundedRectRadii(radii):
            let radius = max(radii.topLeft, radii.topRight, radii.bottomLeft, radii.bottomRight)
            transition.setCornerRadius(layer: self.layer, cornerRadius: radius)
        }

        let fill: UIColor
        switch tintColor.kind {
        case .panel:
            fill = (isDark ? UIColor(white: 0.18, alpha: 0.72) : UIColor(white: 1.0, alpha: 0.72))
        case .clear:
            fill = .clear
        case let .custom(style, color):
            switch style {
            case .clear:
                fill = color.withAlphaComponent(min(color.alpha, 0.35))
            case .default:
                fill = color
            }
        }
        if let inner = tintColor.innerColor {
            transition.setBackgroundColor(view: self.fillView, color: inner.withAlphaComponent(0.55))
        } else {
            transition.setBackgroundColor(view: self.fillView, color: fill)
        }

        let style: UIBlurEffect.Style = isDark ? .dark : .light
        if (self.blurView.effect as? UIBlurEffect) == nil {
            self.blurView.effect = UIBlurEffect(style: style)
        }
        transition.setAlpha(view: self, alpha: isVisible ? 1.0 : 0.0)
    }

    public static func generateForegroundImage(size: CGSize, isDark: Bool, fillColor: UIColor) -> UIImage? {
        let diameter = max(size.width, size.height)
        return generateFilledCircleImage(diameter: diameter, color: fillColor)
    }

    public static func generateLegacyGlassImage(size: CGSize, inset: CGFloat, borderWidthFactor: CGFloat = 1.0, isDark: Bool, fillColor: UIColor) -> UIImage {
        return generateFilledCircleImage(diameter: max(size.width, size.height), color: fillColor) ?? UIImage()
    }
}

public final class GlassBackgroundContainerView: UIView {
    public let contentView = SparseContainerView()

    public init(spacing: CGFloat = 7.0) {
        super.init(frame: .zero)
        self.addSubview(self.contentView)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(size: CGSize, isDark: Bool, transition: ComponentTransition) {
        transition.setFrame(view: self.contentView, frame: CGRect(origin: .zero, size: size))
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.alpha.isZero || self.isHidden || !self.isUserInteractionEnabled {
            return nil
        }
        for view in self.contentView.subviews.reversed() {
            if let result = view.hitTest(self.convert(point, to: view), with: event), result.isUserInteractionEnabled {
                return result
            }
        }
        return nil
    }
}

public final class GlassBackgroundComponent: Component {
    public let size: CGSize
    public let shape: GlassBackgroundView.Shape
    public let isDark: Bool
    public let tintColor: GlassBackgroundView.TintColor
    public let isInteractive: Bool
    public let isVisible: Bool

    public init(size: CGSize, shape: GlassBackgroundView.Shape, isDark: Bool, tintColor: GlassBackgroundView.TintColor, isInteractive: Bool = false, isVisible: Bool = true) {
        self.size = size
        self.shape = shape
        self.isDark = isDark
        self.tintColor = tintColor
        self.isInteractive = isInteractive
        self.isVisible = isVisible
    }

    public static func ==(lhs: GlassBackgroundComponent, rhs: GlassBackgroundComponent) -> Bool {
        return lhs.size == rhs.size && lhs.shape == rhs.shape && lhs.isDark == rhs.isDark && lhs.tintColor == rhs.tintColor && lhs.isInteractive == rhs.isInteractive && lhs.isVisible == rhs.isVisible
    }

    public final class View: GlassBackgroundView {
        func update(component: GlassBackgroundComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.update(size: component.size, shape: component.shape, isDark: component.isDark, tintColor: component.tintColor, isInteractive: component.isInteractive, isVisible: component.isVisible, transition: transition)
            return component.size
        }
    }

    public func makeView() -> View {
        return View()
    }

    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
