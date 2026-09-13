//
//  AppWindow.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/29.
//

import SwiftUI
import Core

fileprivate let isMacOS26: Bool = ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26
fileprivate let isMacOS14OrLater: Bool = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 14

class AppWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    init(instanceManager: InstanceManager) {
        super.init(
            contentRect: .init(x: 0, y: 0, width: 1000, height: 550),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        
        self.contentView = NSHostingView(rootView: RootView(instanceManager: instanceManager))
        
        self.setFrameAutosaveName("AppWindow")
        self.center()
        
        // 窗口大小改变后系统会重置标题栏按钮位置，需重新定位
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: self
        )
    }
    
    @objc private func windowDidResize(_ notification: Notification) {
        layoutIfNeeded()
    }
    
    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        if let close = self.standardWindowButton(.closeButton),
           let min = self.standardWindowButton(.miniaturizeButton),
           let zoom = self.standardWindowButton(.zoomButton) {
            if isMacOS14OrLater {
                close.frame.origin = CGPoint(x: isMacOS26 ? 18 : 16, y: isMacOS26 ? 0 : -4)
                min.frame.origin = CGPoint(x: close.frame.maxX + (isMacOS26 ? 8 : 6), y: close.frame.minY)
                zoom.frame.origin = CGPoint(x: min.frame.maxX + (isMacOS26 ? 8 : 6), y: close.frame.minY)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
