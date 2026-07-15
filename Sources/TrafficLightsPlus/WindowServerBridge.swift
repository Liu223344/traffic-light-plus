import AppKit
import CoreGraphics
import Darwin

final class WindowServerBridge {
    static let shared = WindowServerBridge()

    private typealias MainConnectionFunction = @convention(c) () -> Int32
    private typealias OrderWindowFunction = @convention(c) (
        Int32,
        CGWindowID,
        Int32,
        CGWindowID
    ) -> Int32
    private typealias MoveWindowGroupFunction = @convention(c) (
        Int32,
        CGWindowID,
        UnsafeMutablePointer<CGPoint>
    ) -> Int32

    private let libraryHandle: UnsafeMutableRawPointer?
    private let connectionID: Int32?
    private let orderWindowFunction: OrderWindowFunction?
    private let moveWindowGroupFunction: MoveWindowGroupFunction?

    var isAvailable: Bool {
        connectionID != nil && orderWindowFunction != nil && moveWindowGroupFunction != nil
    }

    private init() {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        libraryHandle = dlopen(path, RTLD_LAZY | RTLD_LOCAL)

        guard let libraryHandle,
              let connectionSymbol = dlsym(libraryHandle, "SLSMainConnectionID"),
              let orderSymbol = dlsym(libraryHandle, "SLSOrderWindow"),
              let moveSymbol = dlsym(libraryHandle, "SLSMoveWindowWithGroup") else {
            connectionID = nil
            orderWindowFunction = nil
            moveWindowGroupFunction = nil
            return
        }

        let mainConnection = unsafeBitCast(connectionSymbol, to: MainConnectionFunction.self)
        connectionID = mainConnection()
        orderWindowFunction = unsafeBitCast(orderSymbol, to: OrderWindowFunction.self)
        moveWindowGroupFunction = unsafeBitCast(moveSymbol, to: MoveWindowGroupFunction.self)
    }

    @discardableResult
    func order(_ window: NSWindow, directlyAbove targetWindowID: CGWindowID) -> Bool {
        guard let connectionID,
              let orderWindowFunction,
              window.windowNumber > 0 else { return false }
        let result = orderWindowFunction(
            connectionID,
            CGWindowID(window.windowNumber),
            Int32(NSWindow.OrderingMode.above.rawValue),
            targetWindowID
        )
        return result == 0
    }

    @discardableResult
    func moveWindowGroup(_ anchorWindow: NSWindow, toCGOrigin origin: CGPoint) -> Bool {
        guard let connectionID,
              let moveWindowGroupFunction,
              anchorWindow.windowNumber > 0 else { return false }
        var origin = origin
        let result = moveWindowGroupFunction(
            connectionID,
            CGWindowID(anchorWindow.windowNumber),
            &origin
        )
        return result == 0
    }
}
