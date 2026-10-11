//
//  InstanceIcon.swift
//  PCL.Mac XE
//
//  Created by AaronXieA on 2026/10/11.
//

import Foundation
import AppKit
import Core

/// 实例图标解析器。
/// 支持预设图标（内置方块/生物图标）、自定义上传图标、以及默认按 ModLoader 回退。
public enum InstanceIcon {
    /// 图标来源。
    public enum Kind: Equatable {
        /// 使用默认逻辑（按 ModLoader 或草方块回退）。
        case `default`
        /// 使用内置预设图标。
        case preset(String)
        /// 使用实例目录下的自定义上传图标。
        case custom
    }

    /// 实例的图标来源。
    public static func kind(of instance: MinecraftInstance) -> Kind {
        guard let name = instance.config.icon, !name.isEmpty else { return .default }
        if name == "custom" { return .custom }
        return .preset(name)
    }

    /// 生成该实例应显示的 `NSImage`。
    /// - 自定义图标：优先从实例目录读取 `PCL-icon.png`，失败时回退默认。
    /// - 预设图标：按名称匹配 `ImageResource`。
    /// - 默认：按 `modLoader` 回退，最终 `iconGrassBlock`。
    public static func nsImage(for instance: MinecraftInstance) -> NSImage? {
        switch kind(of: instance) {
        case .custom:
            if let image = NSImage(contentsOf: instance.customIconURL) { return image }
            return defaultImage(for: instance)
        case .preset(let name):
            if let image = presetImage(named: name) { return image }
            return defaultImage(for: instance)
        case .default:
            return defaultImage(for: instance)
        }
    }

    /// 默认图标（Fabric/Forge/NeoForge 或草方块）。
    public static func defaultImage(for instance: MinecraftInstance) -> NSImage? {
        if let modLoader = instance.modLoader {
            return NSImage(named: NSImage.Name(modLoaderIconName(modLoader)))
        }
        return NSImage(named: "iconGrassBlock")
    }

    private static func modLoaderIconName(_ modLoader: ModLoader) -> String {
        switch modLoader {
        case .fabric: return "iconFabric"
        case .forge: return "iconForge"
        case .neoforge: return "iconNeoforge"
        }
    }

    /// 预设图标名到 `NSImage` 的映射。
    public static func presetImage(named name: String) -> NSImage? {
        NSImage(named: NSImage.Name(name))
    }

    /// 预设图标清单（供设置页展示）。
    public static var presetList: [(id: String, name: String, image: NSImage?)] {
        [
            ("iconGrassBlock", "草方块", presetImage(named: "iconGrassBlock")),
            ("iconGoldBlock", "金块", presetImage(named: "iconGoldBlock")),
            ("iconAnvil", "铁砧", presetImage(named: "iconAnvil")),
            ("iconCloth", "布料", presetImage(named: "iconCloth")),
            ("iconFox", "狐狸", presetImage(named: "iconFox"))
        ]
    }

    /// 将用户选择的图片保存为实例的自定义图标。
    /// - Parameters:
    ///   - instance: 目标实例。
    ///   - sourceURL: 用户选择的图片文件路径。
    /// - Throws: 复制/写入失败时抛出错误。
    public static func saveCustomIcon(to instance: MinecraftInstance, from sourceURL: URL) throws {
        let fileManager = FileManager.default
        let destination = instance.customIconURL
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        instance.config.icon = "custom"
        instance.markDirty()
        instance.iconRevision += 1
    }

    /// 恢复为默认图标。
    public static func resetIcon(of instance: MinecraftInstance) {
        let destination = instance.customIconURL
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        instance.config.icon = nil
        instance.markDirty()
        instance.iconRevision += 1
    }

    /// 使用预设图标。
    public static func setPreset(_ name: String, for instance: MinecraftInstance) {
        instance.config.icon = name
        instance.markDirty()
        instance.iconRevision += 1
    }
}
