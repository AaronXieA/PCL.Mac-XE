//
//  MinecraftInstance.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2026/4/15.
//

import Foundation
import AppKit

public class MinecraftInstance: Hashable, Identifiable, Equatable {
    public let id: UUID
    public let url: URL
    public let version: MinecraftVersion
    public let modLoader: ModLoader?
    public let manifest: ClientManifest
    
    public var config: Config
    
    public var dirty: Bool
    
    /// 图标元数据修订号：图标变更时自增以驱动 SwiftUI 刷新。
    @Published public var iconRevision: Int = 0
    
    public var name: String { url.lastPathComponent }
    public var manifestURL: URL { url.appending(path: "\(name).json") }
    /// 实例目录内的自定义图标文件。
    public var customIconURL: URL { url.appending(path: "PCL-icon.png") }
    /// 元数据中保存的图标标识（预设名或 "custom"）。
    public var iconName: String? {
        get { config.icon }
        set { config.icon = newValue; markDirty() }
    }
    
    public init(id: UUID, url: URL, version: MinecraftVersion, modLoader: ModLoader?, manifest: ClientManifest, config: Config, dirty: Bool = false) {
        self.id = id
        self.url = url
        self.version = version
        self.modLoader = modLoader
        self.manifest = manifest
        self.config = config
        self.dirty = dirty
    }
    
    public func markDirty() { self.dirty = true }
    
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: MinecraftInstance, rhs: MinecraftInstance) -> Bool {
        return lhs.id == rhs.id
    }
    
    public struct Config: Codable {
        public var jvmHeapSize: UInt64
        public var javaURL: URL?
        public var jvmArguments: [String]
        public var icon: String?

        public static let `default`: Config = .init(jvmHeapSize: 4096, javaURL: nil)

        public init(jvmHeapSize: UInt64, javaURL: URL?, jvmArguments: [String] = [], icon: String? = nil) {
            self.jvmHeapSize = jvmHeapSize
            self.javaURL = javaURL
            self.jvmArguments = jvmArguments
            self.icon = icon
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.jvmHeapSize = try container.decode(UInt64.self, forKey: .jvmHeapSize)
            self.javaURL = try container.decodeIfPresent(URL.self, forKey: .javaURL)
            self.jvmArguments = try container.decodeIfPresent([String].self, forKey: .jvmArguments) ?? []
            self.icon = try container.decodeIfPresent(String.self, forKey: .icon)
        }
    }
}

public extension JavaSearcher {
    static func pick(for instance: MinecraftInstance) -> JavaRuntime? {
        let systemArch: Architecture = .systemArchitecture()
        let instanceNeedsX64 = instance.version < .init("1.7.2")
        
        func score(of javaRuntime: JavaRuntime) -> Int {
            var score = 0
            if javaRuntime.architecture == (instance.version > .init("1.7.2") ? systemArch : .x64) { score += 3 }
            if javaRuntime.majorVersion == instance.manifest.javaVersion.majorVersion { score += 2 }
            if javaRuntime.type == .jdk { score += 1 }
            return score
        }
        
        let javaRuntimes = JavaManager.shared.javaRuntimes.lazy
            .filter { $0.majorVersion >= instance.manifest.javaVersion.majorVersion && !(systemArch == .x64 && $0.architecture == .arm64) }
            .filter { !(instanceNeedsX64 && $0.architecture != .x64)  }
        
        return javaRuntimes.max(by: { score(of: $0) < score(of: $1) })
    }
}
