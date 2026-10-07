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
        let resource: Resource
        let currentVersion: ModrinthVersion
        let targetVersion: ModrinthVersion
        let targetFile: ModrinthVersion.File
    }
    
    /// 任务模型，用于在子任务间共享待更新列表。
    private class UpdateModel: TaskModel {
        var entries: [UpdateEntry] = []
    }
    
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
        let task: MyTask<UpdateModel> = .init(
            name: "更新 Mod - \(instance.name)",
            model: model,
            .init(0, "检查更新", display: false) { subTask, model in
                let entries: [UpdateEntry] = try await checkUpdates(for: instance, mods: mods)
                model.entries = entries
                await subTask.setProgressAsync(1)
            },
            .init(1, "下载更新", display: false) { subTask, model in
                try await downloadUpdates(model.entries, task: subTask)
            }
        ) { error in
            if error.isCancellationError { return }
            err("更新 Mod 失败：\(error.localizedDescription)")
        }
        
        TaskManager.shared.execute(task: task) { error in
            if error == nil {
                let items: [ModUpdateItem] = model.entries
                    .map { entry in
                        let fileURL: URL = entry.url.pathExtension == "disabled"
                            ? entry.url.deletingPathExtension()
                            : entry.url
                        return ModUpdateItem(
                            name: entry.resource.name.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : entry.resource.name,
                            oldVersion: entry.currentVersion.versionNumber,
                            newVersion: entry.targetVersion.versionNumber
                        )
                    }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                completion(items)
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
        
        // 批量反查当前版本
        let currentVersions: [String: ModrinthVersion] = try await ModrinthAPIClient.shared.versions(ofHashes: Array(hashToMod.keys))
        guard !currentVersions.isEmpty else { return [] }
        
        // 按 projectId 分组
        var projectToHashes: [String: [String]] = [:]
        for (hash, version) in currentVersions {
            projectToHashes[version.projectId, default: []].append(hash)
        }
        
        // 并发获取各项目的版本列表
        let projectVersions: [String: [ModrinthVersion]] = try await withThrowingTaskGroup(of: (String, [ModrinthVersion]).self) { group in
            for projectId in projectToHashes.keys {
                group.addTask {
                    (projectId, try await ModrinthAPIClient.shared.versions(ofProject: projectId, revalidate: true))
                }
            }
            var result: [String: [ModrinthVersion]] = [:]
            for try await (projectId, versions) in group {
                result[projectId] = versions
            }
            return result
        }
        
        // 筛选兼容的最新版本
        let gameVersionId: String = instance.version.id
        let modLoader: ModLoader? = instance.modLoader
        var entries: [UpdateEntry] = []
        
        for (hash, (url, resource)) in hashToMod {
            guard let currentVersion = currentVersions[hash],
                  let versions = projectVersions[currentVersion.projectId] else {
                continue
            }
            
            let compatible: [ModrinthVersion] = versions.filter { version in
                version.gameVersions.contains(gameVersionId)
                && (modLoader == nil || version.loaders.contains(modLoader!))
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
            
            entries.append(UpdateEntry(url: url, resource: resource, currentVersion: currentVersion, targetVersion: latest, targetFile: file))
        }
        
        return entries
    }
    
    // MARK: - 下载并替换
    
    private static func downloadUpdates(_ entries: [UpdateEntry], task: MyTask<UpdateModel>.SubTask) async throws {
        guard !entries.isEmpty else { return }
        
        let fileManager: FileManager = .default
        let tempRoot: URL = URLConstants.tempURL.appending(path: "mod-update-\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempRoot)
        }
        
        let total: Double = Double(entries.count)
        var completed: Double = 0
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for entry in entries {
                group.addTask {
                    let tempFile: URL = tempRoot.appending(path: entry.targetFile.name)
                    try await FileDownloader.shared.download(
                        url: entry.targetFile.url,
                        destination: tempFile,
                        sha1: entry.targetFile.sha1,
                        progressHandler: { progress in
                            Task { @MainActor in
                                let current = await MainActor.run { completed }
                                task.setProgress((current + progress) / total)
                            }
                        }
                    )
                    
                    // 替换旧文件（保留 .disabled 后缀）
                    let disabled: Bool = entry.url.pathExtension == "disabled"
                    var newURL: URL = entry.url.deletingLastPathComponent().appending(path: entry.targetFile.name)
                    if disabled {
                        newURL.appendPathExtension("disabled")
                    }
                    
                    // 如果新旧文件名不同，先删除旧文件；若新文件已存在（其他 Mod 同名），先删除
                    if fileManager.fileExists(atPath: newURL.path) {
                        try fileManager.removeItem(at: newURL)
                    }
                    try fileManager.moveItem(at: tempFile, to: newURL)
                    
                    // 删除旧文件（如果文件名不同）
                    if newURL != entry.url {
                        try fileManager.removeItem(at: entry.url)
                    }
                    
                    await MainActor.run {
                        completed += 1
                    }
                }
            }
            try await group.waitForAll()
        }
    }
}
