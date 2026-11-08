//
//  BackgroundManager.swift
//  PCL.Mac XE
//
//  自定义背景图片的加载、保存与显示方式。
//

import AppKit
import Core
import SwiftUI

final class BackgroundManager: ObservableObject {
    static let shared: BackgroundManager = .init()

    @Published private(set) var image: NSImage?
    @Published private(set) var mode: LauncherConfig.BackgroundDisplayMode
    @Published private(set) var opacity: Double
    @Published private(set) var fileName: String?

    private static let directoryURL: URL = URLConstants.applicationSupportURL.appending(path: "Background")

    enum BackgroundImageError: LocalizedError {
        case unreadable

        var errorDescription: String? {
            "无法读取所选图片"
        }
    }

    private init() {
        let path: String? = LauncherConfig.shared.backgroundImagePath
        self.mode = LauncherConfig.shared.backgroundDisplayMode
        self.opacity = LauncherConfig.shared.backgroundOpacity
        self.image = path.flatMap { NSImage(contentsOfFile: $0) }
        self.fileName = path.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    /// 导入并应用背景图片。
    func importImage(from url: URL) throws {
        guard let loadedImage: NSImage = NSImage(contentsOf: url) else {
            throw BackgroundImageError.unreadable
        }

        let fileManager: FileManager = .default
        try fileManager.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
        try removeStoredBackground()

        let pathExtension: String = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        let destination: URL = Self.directoryURL.appending(path: "background.\(pathExtension)")
        try fileManager.copyItem(at: url, to: destination)

        LauncherConfig.shared.backgroundImagePath = destination.path
        do {
            try LauncherConfig.save()
        } catch {
            err("保存背景图片配置失败：\(error.localizedDescription)")
        }

        image = loadedImage
        fileName = destination.lastPathComponent
    }

    /// 清除背景图片。
    func clear() {
        try? removeStoredBackground()
        image = nil
        fileName = nil
        LauncherConfig.shared.backgroundImagePath = nil
        do {
            try LauncherConfig.save()
        } catch {
            err("清除背景图片配置失败：\(error.localizedDescription)")
        }
    }

    /// 更新背景图片不透明度。
    func setOpacity(_ opacity: Double) {
        self.opacity = min(max(opacity, 0), 1)
        LauncherConfig.shared.backgroundOpacity = self.opacity
        do {
            try LauncherConfig.save()
        } catch {
            err("保存背景不透明度失败：\(error.localizedDescription)")
        }
    }

    /// 更新显示方式。
    func setMode(_ mode: LauncherConfig.BackgroundDisplayMode) {
        self.mode = mode
        LauncherConfig.shared.backgroundDisplayMode = mode
        do {
            try LauncherConfig.save()
        } catch {
            err("保存背景显示方式失败：\(error.localizedDescription)")
        }
    }

    private func removeStoredBackground() throws {
        let fileManager: FileManager = .default
        guard fileManager.fileExists(atPath: Self.directoryURL.path) else { return }
        let contents: [URL] = try fileManager.contentsOfDirectory(at: Self.directoryURL, includingPropertiesForKeys: nil)
        for fileURL in contents where fileURL.lastPathComponent.hasPrefix("background.") {
            try fileManager.removeItem(at: fileURL)
        }
    }
}
