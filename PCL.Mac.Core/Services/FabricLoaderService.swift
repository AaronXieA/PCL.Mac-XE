//
//  FabricLoaderService.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2026/11/6.
//

import Foundation

public enum FabricLoaderService {
    public struct LoaderVersion {
        public let version: String
        public let stable: Bool
        
        public init(version: String, stable: Bool) {
            self.version = version
            self.stable = stable
        }
    }
    
    public struct ReinstallResult {
        public let oldVersion: String?
        public let newVersion: String
        
        public var isUpdated: Bool {
            guard let oldVersion else { return true }
            return oldVersion != newVersion
        }
    }
    
    public enum ServiceError: LocalizedError {
        case notFabricInstance
        case missingManifest
        case noAvailableVersion
        case noBackup
        
        public var errorDescription: String? {
            switch self {
            case .notFabricInstance: "该实例没有安装 Fabric Loader。"
            case .missingManifest: "找不到实例的版本清单文件。"
            case .noAvailableVersion: "未能获取可用的 Fabric Loader 版本。"
            case .noBackup: "没有可撤回的 Loader 重装记录。"
            }
        }
    }
    
    private struct VersionEntry: Codable {
        struct LoaderInfo: Codable {
            let version: String
            let stable: Bool
        }
        
        let loader: LoaderInfo
    }
    
    private struct BackupInfo: Codable {
        let oldVersion: String?
        let newVersion: String
        let date: Date
    }
    
    private static let backupDirectoryName: String = ".pcl/loader-backups"
    private static let maxBackupCount: Int = 5
    private static let manifestFileName: String = "backup.json"
    private static let backupInfoFileName: String = "info.json"
    private static var versionCaches: [String: [LoaderVersion]] = [:]
    private static var versionCacheTasks: [String: Task<[LoaderVersion], Swift.Error>] = [:]
    
    /// Fabric 相关文件默认走镜像（国内网络访问官方 Maven / Meta 很慢）。
    /// 用户显式选择镜像优先时同样使用镜像。
    private static var mirrorPreference: Bool? {
        let manager: DownloadSourceManager = .shared
        if manager.policy == .mirrorFirst {
            return true
        }
        return LocaleUtils.isSystemLocaleChinese() ? true : nil
    }
    
    // MARK: - 查询
    
    /// 读取实例当前使用的 Fabric Loader 版本。
    public static func currentLoaderVersion(of instance: MinecraftInstance) -> String? {
        guard let data = try? Data(contentsOf: instance.manifestURL),
              let text: String = .init(data: data, encoding: .utf8),
              let range = text.range(of: #"net\.fabricmc:fabric-loader:[^"\s]+"#, options: .regularExpression) else {
            return nil
        }
        return String(text[range]).components(separatedBy: ":").last
    }
    
    /// 获取指定 Minecraft 版本可用的全部 Fabric Loader 版本（新的在前）。
    /// - Note: 结果会缓存在内存中，重复打开版本列表不再请求网络。
    public static func loaderVersions(for minecraftVersion: String) async throws -> [LoaderVersion] {
        if let cached: [LoaderVersion] = versionCaches[minecraftVersion] {
            return cached
        }
        if let task: Task<[LoaderVersion], Swift.Error> = versionCacheTasks[minecraftVersion] {
            return try await task.value
        }
        let task: Task<[LoaderVersion], Swift.Error> = Task {
            guard let url: URL = DownloadSourceManager.shared.fabricVersionListURL(for: minecraftVersion) else {
                throw ServiceError.noAvailableVersion
            }
            let tempURL: URL = URLConstants.tempURL.appending(path: "fabric-loader-versions-\(minecraftVersion).json")
            try await FileDownloader.shared.download(
                .init(url: url, destination: tempURL, checksums: nil),
                preferMirror: mirrorPreference,
                checkDestination: false
            )
            let entries: [VersionEntry] = try JSONDecoder.shared.decode([VersionEntry].self, from: Data(contentsOf: tempURL))
            guard !entries.isEmpty else { throw ServiceError.noAvailableVersion }
            return entries.map { .init(version: $0.loader.version, stable: $0.loader.stable) }
        }
        versionCacheTasks[minecraftVersion] = task
        do {
            let versions: [LoaderVersion] = try await task.value
            versionCaches[minecraftVersion] = versions
            versionCacheTasks[minecraftVersion] = nil
            return versions
        } catch {
            versionCacheTasks[minecraftVersion] = nil
            throw error
        }
    }
    
    /// 获取指定 Minecraft 版本可用的最新稳定 Fabric Loader 版本。
    public static func latestLoaderVersion(for minecraftVersion: String) async throws -> String {
        let versions: [LoaderVersion] = try await loaderVersions(for: minecraftVersion)
        guard let version: String = (versions.first(where: \.stable) ?? versions.first)?.version else {
            throw ServiceError.noAvailableVersion
        }
        return version
    }
    
    // MARK: - 重装
    
    /// 重装（或更新）实例的 Fabric Loader。
    /// - Parameters:
    ///   - loaderVersion: 目标版本，为 `nil` 时使用最新稳定版。
    ///   - progressHandler: 进度回调（0...1）。
    /// - Note: 重装前会备份原清单，失败时自动回滚。
    @discardableResult
    public static func reinstall(
        for instance: MinecraftInstance,
        in repository: MinecraftRepository,
        loaderVersion: String? = nil,
        progressHandler: (@MainActor (Double) -> Void)? = nil
    ) async throws -> ReinstallResult {
        guard instance.modLoader == .fabric else { throw ServiceError.notFabricInstance }
        guard FileManager.default.fileExists(atPath: instance.manifestURL.path) else {
            throw ServiceError.missingManifest
        }
        
        let minecraftVersion: String = instance.version.id
        let oldVersion: String? = currentLoaderVersion(of: instance)
        let newVersion: String
        if let loaderVersion {
            newVersion = loaderVersion
        } else {
            newVersion = try await latestLoaderVersion(for: minecraftVersion)
        }
        await progressHandler?(0)
        let backupURL: URL = try backup(instance: instance, oldVersion: oldVersion, newVersion: newVersion)
        await progressHandler?(0.1)
        
        do {
            let profile: ClientManifest = try await downloadProfile(
                minecraftVersion: minecraftVersion,
                loaderVersion: newVersion,
                destination: instance.manifestURL
            ) { progress in
                progressHandler?(0.1 + progress * 0.1)
            }
            try await downloadLibraries(from: profile, in: repository) { progress in
                progressHandler?(0.2 + progress * 0.75)
            }
            let manifest: ClientManifest = try MinecraftInstanceLoader.loadManifest(at: instance.manifestURL)
            instance.manifest = manifest
            await progressHandler?(1)
        } catch {
            try? restore(instance: instance, from: backupURL)
            await progressHandler?(0)
            throw error
        }
        
        return .init(oldVersion: oldVersion, newVersion: newVersion)
    }
    
    private static func downloadProfile(
        minecraftVersion: String,
        loaderVersion: String,
        destination: URL,
        progressHandler: (@MainActor (Double) -> Void)? = nil
    ) async throws -> ClientManifest {
        let url: URL = .init(string: "https://meta.fabricmc.net/v2/versions/loader/\(minecraftVersion)/\(loaderVersion)/profile/json")!
        // 目标文件此时一定是旧清单，必须强制覆盖下载。
        try await FileDownloader.shared.download(
            .init(url: url, destination: destination, checksums: nil),
            preferMirror: mirrorPreference,
            progressHandler: progressHandler,
            checkDestination: false
        )
        return try JSONDecoder.shared.decode(ClientManifest.self, from: Data(contentsOf: destination))
    }
    
    private static func downloadLibraries(
        from manifest: ClientManifest,
        in repository: MinecraftRepository,
        progressHandler: (@MainActor (Double) -> Void)? = nil
    ) async throws {
        let files: [DownloadItem] = (manifest.getLibraries() + manifest.getNatives())
            .compactMap(\.artifact)
            .compactMap { $0.downloadItem(destinationDirectory: repository.librariesDirectory) }
        try await FileDownloader.shared.download(files: files, preferMirror: mirrorPreference, progressHandler: progressHandler)
    }
    
    // MARK: - 撤回
    
    /// 是否存在可撤回的 Loader 重装记录。
    public static func hasBackup(for instance: MinecraftInstance) -> Bool {
        latestBackup(for: instance) != nil
    }
    
    /// 撤回最近一次 Loader 重装，恢复原有的 Loader。
    /// - Returns: 恢复后的 Loader 版本。
    @discardableResult
    public static func rollbackLatest(for instance: MinecraftInstance) throws -> String? {
        guard let backupURL: URL = latestBackup(for: instance) else {
            throw ServiceError.noBackup
        }
        let backupManifestURL: URL = backupURL.appending(path: manifestFileName)
        guard FileManager.default.fileExists(atPath: backupManifestURL.path) else {
            throw ServiceError.missingManifest
        }
        try restore(instance: instance, from: backupURL)
        let manifest: ClientManifest = try MinecraftInstanceLoader.loadManifest(at: instance.manifestURL)
        instance.manifest = manifest
        try? FileManager.default.removeItem(at: backupURL)
        return currentLoaderVersion(of: instance)
    }
    
    // MARK: - 备份
    
    private static func backupRoot(for instance: MinecraftInstance) -> URL {
        instance.url.appending(path: backupDirectoryName)
    }
    
    private static func latestBackup(for instance: MinecraftInstance) -> URL? {
        let root: URL = backupRoot(for: instance)
        guard let urls: [URL] = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return urls
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: manifestFileName).path) }
            .max { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
    }
    
    @discardableResult
    private static func backup(instance: MinecraftInstance, oldVersion: String?, newVersion: String) throws -> URL {
        let root: URL = backupRoot(for: instance)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        
        let formatter: DateFormatter = .init()
        formatter.locale = .init(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let batchURL: URL = root.appending(path: formatter.string(from: .init()))
        try FileManager.default.createDirectory(at: batchURL, withIntermediateDirectories: true)
        
        try FileManager.default.copyItem(
            at: instance.manifestURL,
            to: batchURL.appending(path: manifestFileName)
        )
        let info: BackupInfo = .init(oldVersion: oldVersion, newVersion: newVersion, date: .init())
        try JSONEncoder.shared.encode(info).write(to: batchURL.appending(path: backupInfoFileName))
        
        let urls: [URL] = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        if urls.count > maxBackupCount {
            urls.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
                .prefix(urls.count - maxBackupCount)
                .forEach { try? FileManager.default.removeItem(at: $0) }
        }
        return batchURL
    }
    
    private static func restore(instance: MinecraftInstance, from backupURL: URL) throws {
        let backupManifestURL: URL = backupURL.appending(path: manifestFileName)
        if FileManager.default.fileExists(atPath: instance.manifestURL.path) {
            try FileManager.default.removeItem(at: instance.manifestURL)
        }
        try FileManager.default.copyItem(at: backupManifestURL, to: instance.manifestURL)
    }
}

private extension URL {
    var creationDate: Date? {
        (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }
}
