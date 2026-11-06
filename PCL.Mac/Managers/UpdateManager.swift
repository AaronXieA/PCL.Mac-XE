//
//  UpdateManager.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2026/3/26.
//

import Foundation
import AppKit
import Core
import ZIPFoundation

class UpdateManager {
    public static let shared: UpdateManager = .init(URL(string: "https://api.github.com/repos/AaronXieA/PCL.Mac-XE/releases/latest")!)

    private let updateMetadataURL: URL

    private init(_ updateMetadataURL: URL) {
        self.updateMetadataURL = updateMetadataURL
    }

    public func checkUpdates() async throws -> UpdateModel.Version? {
        if Metadata.debugMode { return nil }
        let release: GitHubRelease = try await HTTPClient.shared.get(updateMetadataURL, revalidate: true).decode(GitHubRelease.self)
        let latestVersion: String = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        // 与「a.b.c.d」形式对齐：d 为热修复序号，对应 CFBundleVersion
        guard isNewer(latestVersion, than: "\(Metadata.appVersion).\(Metadata.bundleVersion)") else { return nil }
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
            throw SimpleError("最新 Release 中没有可用的更新包")
        }
        return UpdateModel.Version(
            name: displayName(of: latestVersion),
            bundleVersion: 0,
            summary: release.body ?? "",
            updateLogLinks: [.init(name: "GitHub 更新日志", url: release.htmlURL)],
            downloads: .init(github: asset.browserDownloadURL, mirror: asset.browserDownloadURL, size: asset.size, sha1: nil)
        )
    }
    
    /// 获取当前版本的更新内容。优先按当前版本号查找对应的 Release，失败时回退到最新 Release。
    public func fetchChangelog() async throws -> (version: String, body: String, url: URL) {
        var tags: [String] = ["v\(Metadata.appVersion)"]
        if Metadata.bundleVersion != 0 {
            tags.insert("v\(Metadata.appVersion).\(Metadata.bundleVersion)", at: 0)
        }
        for tag in tags {
            guard let url: URL = .init(string: "https://api.github.com/repos/AaronXieA/PCL.Mac-XE/releases/tags/\(tag)") else { continue }
            if let release: GitHubRelease = try? await HTTPClient.shared.get(url, revalidate: true).decode(GitHubRelease.self) {
                return (release.tagName, release.body ?? "", release.htmlURL)
            }
        }
        let release: GitHubRelease = try await HTTPClient.shared.get(updateMetadataURL, revalidate: true).decode(GitHubRelease.self)
        return (release.tagName, release.body ?? "", release.htmlURL)
    }
    
    /// 将 `a.b.c.d` 形式的版本号展示为 `a.b.c (d)`。
    private func displayName(of version: String) -> String {
        let parts: [Substring] = version.split(separator: ".")
        guard parts.count == 4 else { return version }
        return "\(parts[0]).\(parts[1]).\(parts[2]) (\(parts[3]))"
    }

    /// 语义化版本号比较：remote 比 local 新时返回 true
    private func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(remoteParts.count, localParts.count) {
            let remoteValue = i < remoteParts.count ? remoteParts[i] : 0
            let localValue = i < localParts.count ? localParts[i] : 0
            if remoteValue != localValue { return remoteValue > localValue }
        }
        return false
    }

    public func installUpdate(_ version: UpdateModel.Version, useMirror: Bool = true) async throws {
        let destination: URL = URLConstants.tempURL.appending(path: "launcher-update-\(version.name)")
        let downloadItem: DownloadItem = .init(
            url: useMirror ? version.downloads.mirror : version.downloads.github,
            destination: destination,
            sha1: version.downloads.sha1
        )
        defer { try? FileManager.default.removeItem(at: destination) }
        try await FileDownloader.shared.download(downloadItem)
        try FileManager.default.unzipItem(at: destination, to: destination.deletingLastPathComponent())
        let newBundle: URL = URLConstants.tempURL.appending(path: "PCL.Mac XE.app")
        if !FileManager.default.fileExists(atPath: newBundle.path) {
            throw SimpleError("更新包格式错误，请手动安装更新。")
        }
        _ = try FileManager.default.replaceItemAt(
            Bundle.main.bundleURL,
            withItemAt: newBundle,
            backupItemName: "PCL.Mac XE.app.backup",
            options: [.usingNewMetadataOnly]
        )
        
        log("App Bundle 替换完成，正在重启")
        // 使用 /usr/bin/open 延迟开启新进程，确保同时只有一个进程存在
        let process: Process = .init()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundleURL.path]
        try process.run()
        await NSApplication.shared.terminate(nil)
    }
}
