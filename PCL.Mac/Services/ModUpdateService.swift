//
//  ModUpdateService.swift
//  PCL.Mac XE
//
//  Created by Wunanc on 2026/10/7.
//

import Foundation
import Core

/// 一键更新实例中所有 Mod 的服务。
enum ModUpdateService {
    /// 一个已更新 Mod 的展示信息。
    struct ModUpdateItem {
        let name: String
        let oldVersion: String
        let newVersion: String
    }

    /// 一次更新操作涉及的 Mod 信息。
    private struct UpdateEntry {
        let url: URL
        let name: String
        let oldVersion: String
        let newVersion: String
        let fileName: String
        let downloadURL: URL
        let sha1: String?
        
        /// 替换后的目标路径（保留 `.disabled` 后缀）。
        var targetURL: URL {
            var newURL: URL = url.deletingLastPathComponent().appending(path: fileName)
            if url.pathExtension == "disabled" {
                newURL.appendPathExtension("disabled")
            }
            return newURL
        }
    }
    
    /// 任务模型，用于在子任务间共享待更新列表。
    private class UpdateModel: TaskModel {
        var entries: [UpdateEntry] = []
    }
    
    /// 单次更新的备份记录。
    private struct BackupRecord: Codable {
        /// 旧文件相对实例目录的路径。
        let relativePath: String
        /// 新文件相对实例目录的路径。
        let newRelativePath: String
    }
    
    private struct BackupManifest: Codable {
        let createdAt: Date
        let records: [BackupRecord]
    }
    
    private enum BackupError: LocalizedError {
        case notFound
        
        var errorDescription: String? {
            switch self {
            case .notFound:
                return "未找到可撤回的更新记录"
            }
        }
    }
    
    // MARK: - 更新入口
    
    /// 检查并创建一键更新任务（自动加载实例 mods 目录中的资源）。
    /// - Parameters:
    ///   - instance: 目标实例。
    ///   - completion: 任务完成（无错误）后的回调，参数为实际更新的 Mod 明细。
    @MainActor
    static func requestUpdate(for instance: MinecraftInstance, completion: @escaping ([ModUpdateItem]) -> Void) async {
        let directory: URL = instance.url.appending(path: ResourceType.mod.saveDirectory!)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        let service: ResourceLoadService = .init(
            preferredType: .mod,
            remoteLookupService: .init(curseforgeClient: .init(apiKey: Secrets.shared.curseforgeApiKey ?? "")),
            cache: .shared
        )
        let resources: [(URL, Resource)]
        do {
            resources = try await service.loadResources(in: directory).map { ($0, $1) }
        } catch {
            err("加载模组列表失败：\(error.localizedDescription)")
            return
        }
        requestUpdate(for: instance, resources: resources, completion: completion)
    }
    
    /// 检查并创建一键更新任务。
    /// - Parameters:
    ///   - instance: 目标实例。
    ///   - resources: 已加载的资源列表（`URL` + `Resource`）。
    ///   - completion: 任务完成（无错误）后的回调，参数为实际更新的 Mod 明细，用于刷新资源列表与展示结果。
    @MainActor
    static func requestUpdate(for instance: MinecraftInstance, resources: [(URL, Resource)], completion: @escaping ([ModUpdateItem]) -> Void) {
        let mods: [(URL, Resource)] = resources.filter { $0.1.type == .mod }
        guard !mods.isEmpty else {
            hint("当前实例没有安装任何 Mod！", type: .info)
            return
        }
        
        let model: UpdateModel = .init()
        let instanceURL: URL = instance.url
        Task { @MainActor in
            let entries: [UpdateEntry]
            do {
                entries = try await checkUpdates(for: instance, mods: mods)
            } catch {
                err("检查 Mod 更新失败：\(error.localizedDescription)")
                return
            }
            guard !entries.isEmpty else {
                hint("所有 Mod 都已是最新版本！", type: .finish)
                return
            }
            model.entries = entries
            
            let task: MyTask<UpdateModel> = .init(
                name: "更新 Mod - \(instance.name)",
                model: model,
                .init(0, "下载更新", display: true) { subTask, model in
                    try await downloadUpdates(model.entries, instanceURL: instanceURL, task: subTask)
                }
            ) { error in
                if error.isCancellationError { return }
                err("更新 Mod 失败：\(error.localizedDescription)")
            }
            
            TaskManager.shared.execute(task: task) { error in
                if error == nil {
                    let items: [ModUpdateItem] = model.entries
                        .map { entry in
                            ModUpdateItem(name: entry.name, oldVersion: entry.oldVersion, newVersion: entry.newVersion)
                        }
                        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    completion(items)
                }
            }
        }
    }
    
    // MARK: - 检查更新
    
    private static func checkUpdates(for instance: MinecraftInstance, mods: [(URL, Resource)]) async throws -> [UpdateEntry] {
        let fileManager: FileManager = .default
        
        // 计算所有 Mod 的 SHA-1
        var hashToMod: [String: (URL, Resource)] = [:]
        for (url, resource) in mods {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let hash: String = try FileUtils.sha1(of: url)
            hashToMod[hash] = (url, resource)
        }
        guard !hashToMod.isEmpty else { return [] }
        
        var entries: [UpdateEntry] = []
        
        // MARK: Modrinth
        
        let currentVersions: [String: ModrinthVersion] = (try? await ModrinthAPIClient.shared.versions(ofHashes: Array(hashToMod.keys))) ?? [:]
        var coveredHashes: Set<String> = []
        
        if !currentVersions.isEmpty {
            // 按 projectId 分组
            var projectToHashes: [String: [String]] = [:]
            for (hash, version) in currentVersions {
                projectToHashes[version.projectId, default: []].append(hash)
            }
            
            // 并发获取各项目的版本列表（单个项目失败不影响整体）
            let projectVersions: [String: [ModrinthVersion]] = await withTaskGroup(of: (String, [ModrinthVersion]).self) { group in
                for projectId in projectToHashes.keys {
                    group.addTask {
                        (projectId, (try? await ModrinthAPIClient.shared.versions(ofProject: projectId, revalidate: true)) ?? [])
                    }
                }
                var result: [String: [ModrinthVersion]] = [:]
                for await (projectId, versions) in group {
                    result[projectId] = versions
                }
                return result
            }
            
            // 筛选兼容的最新版本
            let gameVersionId: String = instance.version.id
            let modLoader: ModLoader? = instance.modLoader
            
            for (hash, (url, resource)) in hashToMod {
                guard let currentVersion = currentVersions[hash],
                      let versions = projectVersions[currentVersion.projectId] else {
                    continue
                }
                
                let compatible: [ModrinthVersion] = versions.filter { version in
                    isGameVersionCompatible(declared: version.gameVersions, instance: gameVersionId)
                    && (modLoader == nil || isLoaderCompatible(loaders: version.loaders, modLoader: modLoader))
                }
                
                // 该项目在 Modrinth 上有兼容版本，说明已由 Modrinth 覆盖，不再走 CurseForge 交叉比对
                if !compatible.isEmpty {
                    coveredHashes.insert(hash)
                }
                
                guard let latest = compatible.max(by: { $0.datePublished < $1.datePublished }) else {
                    continue
                }
                
                // 当前版本已是最新
                if latest.id == currentVersion.id { continue }
                // 防止降级：只接受发布时间更晚的版本
                if latest.datePublished <= currentVersion.datePublished { continue }
                
                guard let file = latest.files.first(where: { $0.primary }) ?? latest.files.first else {
                    continue
                }
                
                entries.append(.init(
                    url: url,
                    name: resource.name.isEmpty ? file.name : resource.name,
                    oldVersion: currentVersion.versionNumber,
                    newVersion: latest.versionNumber,
                    fileName: file.name,
                    downloadURL: file.url,
                    sha1: file.sha1
                ))
                coveredHashes.insert(hash)
            }
        }
        
        // MARK: CurseForge
        
        if let apiKey = Secrets.shared.curseforgeApiKey, !apiKey.isEmpty {
            entries.append(contentsOf: await checkCurseForgeUpdates(
                instance: instance,
                hashToMod: hashToMod,
                coveredHashes: coveredHashes,
                client: .init(apiKey: apiKey)
            ))
        }
        
        return entries
    }
    
    /// 判断模组声明的游戏版本是否兼容当前实例。
    private static func isGameVersionCompatible(declared: [String], instance: String) -> Bool {
        declared.contains { version in
            if version == instance { return true }
            // 模组只声明到主版本时（如 1.20），视为兼容该系列的修复版本（如 1.20.1）
            if version.split(separator: ".").count == 2, instance.hasPrefix(version + ".") {
                return true
            }
            return false
        }
    }
    
    /// 判断模组声明的加载器是否兼容当前实例。
    private static func isLoaderCompatible(loaders: [ModLoader], modLoader: ModLoader?) -> Bool {
        guard let modLoader else { return true }
        return loaders.contains(modLoader)
    }
    
    /// 通过 CurseForge 指纹反查并检查更新。
    private static func checkCurseForgeUpdates(
        instance: MinecraftInstance,
        hashToMod: [String: (URL, Resource)],
        coveredHashes: Set<String>,
        client: CurseForgeAPIClient
    ) async -> [UpdateEntry] {
        let fileManager: FileManager = .default
        
        // 计算尚未被 Modrinth 命中的文件的 CurseForge 指纹
        var fingerprintToHash: [UInt32: String] = [:]
        for (hash, (url, _)) in hashToMod where !coveredHashes.contains(hash) {
            guard fileManager.fileExists(atPath: url.path),
                  let fingerprint = try? FileUtils.curseForgeFingerprint(of: url) else {
                continue
            }
            fingerprintToHash[fingerprint] = hash
        }
        guard !fingerprintToHash.isEmpty else { return [] }
        
        guard let matches: [CurseForgeFingerprintMatch] = try? await client.matches(fingerprints: Array(fingerprintToHash.keys)),
              !matches.isEmpty else {
            return []
        }
        
        // 用返回文件的 SHA-1 匹配回本地文件，并按模组分组
        var modIdToCurrent: [Int32: (file: CurseForgeModFile, hash: String)] = [:]
        for match in matches {
            guard let sha1 = match.file.checksums["sha1"],
                  hashToMod[sha1] != nil,
                  !coveredHashes.contains(sha1) else {
                continue
            }
            modIdToCurrent[match.file.modId] = (match.file, sha1)
        }
        guard !modIdToCurrent.isEmpty else { return [] }
        
        // 并发获取每个模组在当前游戏版本与加载器下的文件列表
        let gameVersionId: String = instance.version.id
        let baseGameVersion: String = baseVersion(of: gameVersionId)
        let modLoader: ModLoader? = instance.modLoader
        
        let fileLists: [Int32: [CurseForgeModFile]] = await withTaskGroup(of: (Int32, [CurseForgeModFile]).self) { group in
            for modId in modIdToCurrent.keys {
                group.addTask {
                    var files: [CurseForgeModFile] = ((try? await client.files(ofMod: modId, gameVersion: gameVersionId, modLoader: modLoader)) ?? [])
                        .filter { isCurseForgeCompatible(file: $0, instance: gameVersionId) }
                    // 模组仅声明主版本（如 1.20）时，用去掉修复版本号的方式再查一次
                    if files.isEmpty, baseGameVersion != gameVersionId {
                        files = ((try? await client.files(ofMod: modId, gameVersion: baseGameVersion, modLoader: modLoader)) ?? [])
                            .filter { isCurseForgeCompatible(file: $0, instance: gameVersionId) }
                    }
                    return (modId, files)
                }
            }
            var result: [Int32: [CurseForgeModFile]] = [:]
            for await (modId, files) in group {
                result[modId] = files
            }
            return result
        }
        
        var entries: [UpdateEntry] = []
        for (modId, current) in modIdToCurrent {
            let available: [CurseForgeModFile] = (fileLists[modId] ?? []).filter(\.available)
            guard let latest = available.max(by: { ($0.fileDate ?? .distantPast) < ($1.fileDate ?? .distantPast) }) else {
                continue
            }
            if latest.id == current.file.id { continue }
            if let latestDate = latest.fileDate, let currentDate = current.file.fileDate, latestDate <= currentDate {
                continue
            }
            guard let (url, resource) = hashToMod[current.hash] else { continue }
            
            entries.append(.init(
                url: url,
                name: resource.name.isEmpty ? current.file.fileName : resource.name,
                oldVersion: versionLabel(of: current.file),
                newVersion: versionLabel(of: latest),
                fileName: latest.fileName,
                downloadURL: latest.downloadURL,
                sha1: latest.checksums["sha1"]
            ))
        }
        return entries
    }
    
    /// 判断 CurseForge 文件是否兼容当前实例的游戏版本。
    private static func isCurseForgeCompatible(file: CurseForgeModFile, instance: String) -> Bool {
        guard let gameVersions = file.gameVersions, !gameVersions.isEmpty else { return true }
        return isGameVersionCompatible(declared: gameVersions, instance: instance)
    }
    
    /// 去掉修复版本号，得到主版本（1.20.1 → 1.20）。
    private static func baseVersion(of version: String) -> String {
        let parts: [Substring] = version.split(separator: ".")
        guard parts.count == 3 else { return version }
        return "\(parts[0]).\(parts[1])"
    }
    
    private static func versionLabel(of file: CurseForgeModFile) -> String {
        if let displayName = file.displayName, !displayName.isEmpty {
            return displayName
        }
        return (file.fileName as NSString).deletingPathExtension
    }
    
    // MARK: - 下载并替换
    
    private static func downloadUpdates(_ entries: [UpdateEntry], instanceURL: URL, task: MyTask<UpdateModel>.SubTask) async throws {
        guard !entries.isEmpty else { return }
        
        let fileManager: FileManager = .default
        let tempRoot: URL = URLConstants.tempURL.appending(path: "mod-update-\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempRoot)
        }
        
        // 替换前先备份旧文件，便于撤回
        let batchURL: URL = backupRoot(instanceURL: instanceURL).appending(path: backupDirectoryName())
        let records: [BackupRecord] = try backup(entries, instanceURL: instanceURL, batchURL: batchURL)
        let manifest: BackupManifest = .init(createdAt: .init(), records: records)
        try JSONEncoder().encode(manifest).write(to: batchURL.appending(path: "manifest.json"))
        
        let total: Double = Double(entries.count)
        var completed: Double = 0
        
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for entry in entries {
                    group.addTask {
                        let tempFile: URL = tempRoot.appending(path: "\(UUID().uuidString)-\(entry.fileName)")
                        try await FileDownloader.shared.download(
                            url: entry.downloadURL,
                            destination: tempFile,
                            sha1: entry.sha1,
                            progressHandler: { progress in
                                Task { @MainActor in
                                    let current = await MainActor.run { completed }
                                    task.setProgress((current + progress) / total)
                                }
                            }
                        )
                        
                        let newURL: URL = entry.targetURL
                        if fileManager.fileExists(atPath: newURL.path) {
                            try fileManager.removeItem(at: newURL)
                        }
                        try fileManager.moveItem(at: tempFile, to: newURL)
                        
                        // 删除旧文件（如果文件名不同）
                        if newURL != entry.url, fileManager.fileExists(atPath: entry.url.path) {
                            try fileManager.removeItem(at: entry.url)
                        }
                        
                        await MainActor.run {
                            completed += 1
                        }
                    }
                }
                try await group.waitForAll()
            }
        } catch {
            // 中途失败：立即回滚已替换的文件，避免实例处于半更新状态
            try? restore(batchURL: batchURL, records: records, instanceURL: instanceURL)
            try? fileManager.removeItem(at: batchURL)
            throw error
        }
        
        pruneBackups(instanceURL: instanceURL, keeping: 10)
    }
    
    // MARK: - 备份与撤回
    
    /// 备份目录（位于实例目录下的隐藏文件夹）。
    private static func backupRoot(instanceURL: URL) -> URL {
        instanceURL.appending(path: ".pcl/mod-update-backups")
    }
    
    private static func backupDirectoryName() -> String {
        "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)"
    }
    
    private static func relativePath(of url: URL, instanceURL: URL) -> String {
        let base: String = instanceURL.path.hasSuffix("/") ? instanceURL.path : instanceURL.path + "/"
        return url.path.hasPrefix(base) ? String(url.path.dropFirst(base.count)) : url.lastPathComponent
    }
    
    /// 将待替换的旧文件复制到备份目录，并返回备份记录。
    private static func backup(_ entries: [UpdateEntry], instanceURL: URL, batchURL: URL) throws -> [BackupRecord] {
        let fileManager: FileManager = .default
        try fileManager.createDirectory(at: batchURL, withIntermediateDirectories: true)
        
        var records: [BackupRecord] = []
        for entry in entries {
            guard fileManager.fileExists(atPath: entry.url.path) else { continue }
            let oldRelative: String = relativePath(of: entry.url, instanceURL: instanceURL)
            let newRelative: String = relativePath(of: entry.targetURL, instanceURL: instanceURL)
            let backupURL: URL = batchURL.appending(path: oldRelative)
            try fileManager.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: entry.url, to: backupURL)
            records.append(.init(relativePath: oldRelative, newRelativePath: newRelative))
        }
        return records
    }
    
    /// 从备份恢复文件。
    private static func restore(batchURL: URL, records: [BackupRecord], instanceURL: URL) throws {
        let fileManager: FileManager = .default
        for record in records {
            let newURL: URL = instanceURL.appending(path: record.newRelativePath)
            let oldURL: URL = instanceURL.appending(path: record.relativePath)
            let backupURL: URL = batchURL.appending(path: record.relativePath)
            guard fileManager.fileExists(atPath: backupURL.path) else { continue }
            
            // 删除已被替换的新文件（同名文件则直接覆盖）
            if newURL != oldURL, fileManager.fileExists(atPath: newURL.path) {
                try fileManager.removeItem(at: newURL)
            }
            try fileManager.createDirectory(at: oldURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: oldURL.path) {
                try fileManager.removeItem(at: oldURL)
            }
            try fileManager.copyItem(at: backupURL, to: oldURL)
        }
    }
    
    /// 是否存在可撤回的更新记录。
    static func hasBackup(for instance: MinecraftInstance) -> Bool {
        latestBackupBatch(instanceURL: instance.url) != nil
    }
    
    /// 撤回最近一次更新，返回恢复的文件数量。
    @discardableResult
    static func rollbackLatest(for instance: MinecraftInstance) throws -> Int {
        guard let batchURL = latestBackupBatch(instanceURL: instance.url) else {
            throw BackupError.notFound
        }
        let data: Data = try Data(contentsOf: batchURL.appending(path: "manifest.json"))
        let manifest: BackupManifest = try JSONDecoder().decode(BackupManifest.self, from: data)
        try restore(batchURL: batchURL, records: manifest.records, instanceURL: instance.url)
        try? FileManager.default.removeItem(at: batchURL)
        return manifest.records.count
    }
    
    private static func latestBackupBatch(instanceURL: URL) -> URL? {
        let root: URL = backupRoot(instanceURL: instanceURL)
        guard let directories = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }
        for directory in directories.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            if FileManager.default.fileExists(atPath: directory.appending(path: "manifest.json").path) {
                return directory
            }
        }
        return nil
    }
    
    /// 只保留最近若干次备份，避免占用空间。
    private static func pruneBackups(instanceURL: URL, keeping limit: Int) {
        let root: URL = backupRoot(instanceURL: instanceURL)
        guard let directories = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return
        }
        let sorted: [URL] = directories.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for directory in sorted.dropFirst(limit) {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
