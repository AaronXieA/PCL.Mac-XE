//
//  MySelect.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2026/7/8.
//

import SwiftUI

struct MySelect<Entry: Hashable & CustomStringConvertible>: View {
    @State private var hovered: Bool = false
    @State private var presented: Bool = false
    @State private var isPressed: Bool = false
    @State private var panel: SelectPanel?
    @State private var rect: NSRect = .zero
    @State private var selectRect: NSRect = .zero
    @State private var observer: NSObjectProtocol?
    @State private var moveObserver: NSObjectProtocol?
    @State private var mouseMonitor: Any?
    @State private var pulseWorkItem: DispatchWorkItem?
    @State private var hostingWindow: NSWindow?
    @State private var localFrame: NSRect = .zero
    @State private var itemSize: CGSize = .zero
    @State private var retryWorkItem: DispatchWorkItem?
    
    @Binding private var selected: Entry
    
    private let entries: [Entry]
    /// 置灰显示（此时仍可点击，但只回调 onGrayedTap，不展开面板）
    private let grayed: Bool
    private let onGrayedTap: (() -> Void)?
    
    init(_ selected: Binding<Entry>, entries: [Entry], grayed: Bool = false, onGrayedTap: (() -> Void)? = nil) {
        self._selected = selected
        self.entries = entries
        self.grayed = grayed
        self.onGrayedTap = onGrayedTap
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        updateLayout(proxy)
                        recalculateRect()
                    }
                    .onChange(of: proxy.frame(in: .global)) { _ in
                        updateLayout(proxy)
                        close()
                        presented = false
                        recalculateRect()
                    }
            }
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(foregroundColor, lineWidth: 1.5, antialiased: false)
                    .background(backgroundColor)
                    .allowsHitTesting(false)
                
                HStack {
                    MyText(selected.description, color: textColor)
                    
                    Spacer(minLength: 0)
                    
                    Image(.btnFold)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 8)
                        .rotationEffect(.degrees(presented ? -180 : 0), anchor: .center)
                        .animation(.spring(response: 0.35), value: presented)
                        .foregroundStyle(foregroundColor)
                        .padding(.trailing, 2)
                }
                .padding(.horizontal, 6)
            }
            // 仅缩放视觉层，避免缩放引起 GeometryReader 的全局坐标变化而误关面板
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .frame(height: 26)
        .background(
            WindowAccessor { window in
                if let window {
                    hostingWindow = window
                }
            }
            .allowsHitTesting(false)
        )
        .animation(.easeInOut(duration: 0.2), value: isPressed)
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .onHover { hovered = $0 }
        .animation(.linear(duration: 0.1), value: hovered)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                    if grayed {
                        onGrayedTap?()
                    } else {
                        presented.toggle()
                    }
                }
        )
        .onChange(of: presented) { newValue in
            close()
            if newValue, !grayed {
                // 每次展开前按当前窗口位置重新换算，避免移动窗口后面板出现在旧位置
                recalculateRect()
                if rect == .zero {
                    // 布局尚未就绪（例如首次出现），下一帧再试一次
                    let workItem: DispatchWorkItem = .init { [self] in
                        recalculateRect()
                        presentPanel()
                    }
                    retryWorkItem = workItem
                    DispatchQueue.main.async(execute: workItem)
                } else {
                    presentPanel()
                }
            }
        }
        .onDisappear {
            close()
        }
    }
    
    private var foregroundColor: Color {
        if grayed { return .colorGray5 }
        return hovered ? .color4 : .color5
    }
    
    private var backgroundColor: Color {
        if grayed { return .colorGray8 }
        return hovered ? .color7 : .white.opacity(0.5)
    }
    
    private var textColor: Color {
        grayed ? .colorGray4 : .color1
    }
    
    private func presentPanel() {
        guard rect != .zero else { return }
        let hostingView = NSHostingView(rootView: PopupView(entries: entries, selectedEntry: selected) { entry in
            selected = entry
            presented = false
            close()
        })
        
        let panel = SelectPanel(
            contentRect: rect,
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = true
        
        self.observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            self.presented = false
            self.close()
        }
        
        // 面板打开期间窗口被拖动时同步跟随
        if let hostingWindow {
            self.moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: hostingWindow,
                queue: .main
            ) { _ in
                self.recalculateRect()
                self.panel?.setFrame(self.rect, display: true)
            }
        }
        
        panel.makeKeyAndOrderFront(nil)
        
        self.panel = panel
        installMouseMonitor()
    }
    
    private func close() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        if let retryWorkItem {
            retryWorkItem.cancel()
            self.retryWorkItem = nil
        }
        removeMouseMonitor()
        panel?.close()
        panel = nil
    }
    
    /// 监听面板展开期间的鼠标点击，点击下拉框本体时也播放按压缩小动画。
    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if presented, selectRect.contains(NSEvent.mouseLocation) {
                pulsePress()
            }
            return event
        }
    }
    
    private func removeMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }
    
    private func pulsePress() {
        isPressed = true
        pulseWorkItem?.cancel()
        let workItem: DispatchWorkItem = .init {
            isPressed = false
        }
        pulseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }
    
    private func updateLayout(_ proxy: GeometryProxy) {
        localFrame = proxy.frame(in: .global)
        itemSize = proxy.size
    }
    
    /// 把下拉框在窗口内的位置换算成屏幕坐标。
    /// 注意：`.global` 坐标相对窗口内容，窗口移动时不会变化，
    /// 因此展示面板前必须重新计算，不能只在 onAppear 时缓存。
    private func recalculateRect() {
        guard itemSize.height > 0,
              let window = hostingWindow ?? NSApplication.shared.keyWindow,
              let contentView = window.contentView else { return }
        
        let contentHeight = contentView.bounds.height
        let popupHeight = itemSize.height * min(CGFloat(entries.count), 5.5)
        let rectInWindow = NSRect(
            x: localFrame.minX,
            y: contentHeight - (localFrame.minY - 1) - itemSize.height - popupHeight,
            width: localFrame.width,
            height: popupHeight
        )
        rect = window.convertToScreen(rectInWindow)
        selectRect = window.convertToScreen(NSRect(
            x: localFrame.minX,
            y: contentHeight - (localFrame.minY - 1) - itemSize.height,
            width: localFrame.width,
            height: itemSize.height
        ))
    }
}

/// 获取 SwiftUI 视图所在的 NSWindow。
private struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view: NSView = .init()
        DispatchQueue.main.async {
            callback(view.window)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            callback(nsView.window)
        }
    }
}

private struct PopupView<Entry: Hashable & CustomStringConvertible>: View {
    @State private var hoveredEntry: Entry?
    private let entries: [Entry]
    private let selectedEntry: Entry
    private let onSelect: (Entry) -> Void
    
    init(entries: [Entry], selectedEntry: Entry, onSelect: @escaping (Entry) -> Void) {
        self.entries = entries
        self.selectedEntry = selectedEntry
        self.onSelect = onSelect
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(.white)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries, id: \.self) { entry in
                        Group {
                            MyText(entry.description)
                                .padding(.leading, 6)
                        }
                        .frame(height: 26)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                        .background(selectedEntry == entry ? Color.color6 : hoveredEntry == entry ? .color7 : .clear)
                        .onTapGesture {
                            onSelect(entry)
                        }
                        .onHover { hovered in
                            if hovered {
                                hoveredEntry = entry
                            } else if hoveredEntry == entry {
                                hoveredEntry = nil
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.color4, lineWidth: 1.5, antialiased: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: hoveredEntry)
    }
}

private class SelectPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

#Preview {
    MySelect(.constant("entry0"), entries: Array(0..<10).map { "entry\($0)" })
        .padding()
}
