import ApplicationServices
import AppKit

public protocol AXProvider {
    func copyAttributeValue(_ element: AXUIElement, _ attribute: String, _ value: UnsafeMutablePointer<CFTypeRef?>) -> AXError
    func setAttributeValue(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError
    func copyActionNames(_ element: AXUIElement, _ names: UnsafeMutablePointer<CFArray?>) -> AXError
    func performAction(_ element: AXUIElement, _ action: String) -> AXError
}

public class DefaultAXProvider: AXProvider {
    public init() {}

    public func copyAttributeValue(_ element: AXUIElement, _ attribute: String, _ value: UnsafeMutablePointer<CFTypeRef?>) -> AXError {
        AXUIElementCopyAttributeValue(element, attribute as CFString, value)
    }
    public func setAttributeValue(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }
    public func copyActionNames(_ element: AXUIElement, _ names: UnsafeMutablePointer<CFArray?>) -> AXError {
        AXUIElementCopyActionNames(element, names)
    }
    public func performAction(_ element: AXUIElement, _ action: String) -> AXError {
        AXUIElementPerformAction(element, action as CFString)
    }
}

/// Swift wrapper around AXUIElement for convenient window manipulation.
public class AccessibilityElement {
    public let element: AXUIElement
    internal var provider: AXProvider = DefaultAXProvider()

    /// The longest any request through this element may block, in seconds.
    public static let messagingTimeout: Float = 1.0

    public init(_ element: AXUIElement) {
        self.element = element
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
    }

    /// Create an application-level element from a PID
    public convenience init(pid: pid_t) {
        self.init(AXUIElementCreateApplication(pid))
    }

    // MARK: - Generic Attribute Access

    public func getAttribute<T>(_ attribute: String) -> T? {
        var value: CFTypeRef?
        let result = provider.copyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as? T
    }

    @discardableResult
    public func setAttribute(_ attribute: String, value: AnyObject) -> Bool {
        provider.setAttributeValue(element, attribute, value) == .success
    }

    @discardableResult
    public func performAction(_ action: String) -> Bool {
        provider.performAction(element, action) == .success
    }

    // MARK: - Convenience Properties

    public var position: CGPoint? {
        get {
            guard let value: AXValue = getAttribute(kAXPositionAttribute) else { return nil }
            var point = CGPoint.zero
            if AXValueGetValue(value, .cgPoint, &point) {
                return point
            }
            return nil
        }
        set {
            guard var point = newValue else { return }
            guard let value = AXValueCreate(.cgPoint, &point) else { return }
            setAttribute(kAXPositionAttribute, value: value)
        }
    }

    public var size: CGSize? {
        get {
            guard let value: AXValue = getAttribute(kAXSizeAttribute) else { return nil }
            var size = CGSize.zero
            if AXValueGetValue(value, .cgSize, &size) {
                return size
            }
            return nil
        }
        set {
            guard var size = newValue else { return }
            guard let value = AXValueCreate(.cgSize, &size) else { return }
            setAttribute(kAXSizeAttribute, value: value)
        }
    }

    public var frame: CGRect? {
        guard let pos = position, let sz = size else { return nil }
        return CGRect(origin: pos, size: sz)
    }

    public var isMinimized: Bool? {
        get { getAttribute(kAXMinimizedAttribute) }
        set {
            guard let val = newValue else { return }
            setAttribute(kAXMinimizedAttribute, value: val as AnyObject)
        }
    }

    public var isFullScreen: Bool {
        if let val: AnyObject = getAttribute("AXFullScreen") {
            if let boolVal = val as? Bool {
                return boolVal
            }
            if CFGetTypeID(val) == CFBooleanGetTypeID() {
                return CFBooleanGetValue((val as! CFBoolean))
            }
        }
        return false
    }

    public var title: String? {
        getAttribute(kAXTitleAttribute)
    }

    public var role: String? {
        getAttribute(kAXRoleAttribute)
    }

    public var windows: [AccessibilityElement]? {
        guard let windowRefs: [AXUIElement] = getAttribute(kAXWindowsAttribute) else { return nil }
        return windowRefs.map { AccessibilityElement($0) }
    }

    @discardableResult
    public func raise() -> Bool {
        performAction(kAXRaiseAction)
    }

    public var minSize: CGSize? {
        if let val: AXValue = getAttribute("AXMinValue") {
            var size = CGSize.zero
            if AXValueGetValue(val, .cgSize, &size) {
                return size
            }
        }
        return nil
    }

    /// Set frame using the size-position-size dance (handles macOS display constraints)
    public func setFrame(_ frame: CGRect) {
        var targetSize = frame.size
        if let min = minSize {
            targetSize.width = max(targetSize.width, min.width)
            targetSize.height = max(targetSize.height, min.height)
        }
        self.size = targetSize
        self.position = frame.origin
        self.size = targetSize
        self.position = frame.origin
    }
}
