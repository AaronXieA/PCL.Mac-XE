//
//  SkinCapeSelection.swift
//  PCL.Mac XE
//
//  Created by Wunanc on 2026/8/10.
//

import AppKit
import UniformTypeIdentifiers
import Core

extension Notification.Name {
    /// 玩家皮肤发生变化（对象为账号的 `UUID`）。
    static let playerSkinDidChange: Notification.Name = .init("PlayerSkinDidChange")
}

enum SkinCapeSelection {
    private static let thumbnailCropRect = CGRect(x: 1, y: 1, width: 10, height: 16)

    /// 披风 / 皮肤选择入口。
    static func request(for account: Account) {
        Task { @MainActor in
            guard let index = await MessageBoxManager.shared.showListAsync(
                title: "外观设置",
                items: [
                    .init(image: .system("tshirt.fill"), imageSize: 24, name: "更换披风", description: "从账号拥有的披风中选择"),
                    .init(image: .system("person.fill"), imageSize: 24, name: "更换皮肤", description: "上传本地 PNG 皮肤文件")
                ]
            ) else {
                return
            }
            if index == 0 {
                requestCapeSelection(for: account)
            } else {
                requestSkinChange(for: account)
            }
        }
    }

    // MARK: - 披风

    private static func requestCapeSelection(for account: Account) {
        guard let microsoftAccount = account as? MicrosoftAccount else {
            hint("只有正版账号支持更换披风！", type: .critical)
            return
        }

        Task { @MainActor in
            do {
                hint("正在获取披风列表……")
                if microsoftAccount.shouldRefresh() {
                    try await microsoftAccount.refresh()
                }

                let service = MinecraftProfileService(accessToken: microsoftAccount.accessToken)
                let capes = try await service.fetchCapes()
                guard !capes.isEmpty else {
                    hint("当前账号没有可用的披风！", type: .info)
                    return
                }

                let items: [ListItem] = capes.enumerated().map { index, cape in
                    .init(
                        image: ListItem.Image.networkCropped(cape.url, thumbnailCropRect),
                        imageSize: 40,
                        name: cape.alias ?? "披风 \(index + 1)",
                        description: cape.isActive ? "当前使用" : nil
                    )
                }

                guard let index = await MessageBoxManager.shared.showListAsync(
                    title: "选择披风",
                    items: items
                ) else {
                    return
                }

                let cape = capes[index]
                guard !cape.isActive else {
                    hint("这件披风已经在使用中!", type: .critical)
                    return
                }

                try await service.activateCape(cape)
                try await microsoftAccount.reloadProfile()
                persistAccounts()
                hint("披风更换成功！", type: .finish)
            } catch let error where error.isCancellationError {
            } catch {
                err("更换披风失败：\(error.localizedDescription)")
                hint("更换披风失败：\(error.localizedDescription)", type: .critical)
            }
        }
    }

    // MARK: - 皮肤

    private static func requestSkinChange(for account: Account) {
        guard account is MicrosoftAccount || account is YggdrasilAccount else {
            hint("离线账号不支持更换皮肤！", type: .critical)
            return
        }

        let panel: NSOpenPanel = .init()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png]
        panel.title = "选择皮肤文件"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task { @MainActor in
            do {
                let data: Data = try Data(contentsOf: url)
                guard let image = NSImage(data: data) else {
                    hint("无法读取皮肤文件！", type: .critical)
                    return
                }
                let size: NSSize = image.size
                guard (Int(size.width) == 64 && Int(size.height) == 64) || (Int(size.width) == 64 && Int(size.height) == 32) else {
                    hint("皮肤文件尺寸必须是 64×64 或 64×32！", type: .critical)
                    return
                }

                guard let variantIndex = await MessageBoxManager.shared.showListAsync(
                    title: "选择皮肤模型",
                    items: [
                        .init(image: .system("person.fill"), imageSize: 24, name: "经典模型", description: "手臂宽度为 4 像素"),
                        .init(image: .system("person"), imageSize: 24, name: "纤细模型", description: "手臂宽度为 3 像素")
                    ]
                ) else {
                    return
                }
                let variant: SkinVariant = variantIndex == 0 ? .classic : .slim

                hint("正在上传皮肤……")
                if try await account.shouldRefresh() {
                    try await account.refresh()
                }

                switch account {
                case let microsoftAccount as MicrosoftAccount:
                    try await MinecraftProfileService(accessToken: microsoftAccount.accessToken).uploadSkin(data, variant: variant)
                    try await microsoftAccount.reloadProfile()
                case let yggdrasilAccount as YggdrasilAccount:
                    try await YggdrasilService(authServerURL: yggdrasilAccount.authServerURL).uploadSkin(
                        data,
                        variant: variant,
                        for: yggdrasilAccount.profile.id,
                        accessToken: yggdrasilAccount.accessToken
                    )
                    try await yggdrasilAccount.reloadProfile()
                default:
                    return
                }

                persistAccounts()
                NotificationCenter.default.post(name: .playerSkinDidChange, object: account.id)
                hint("皮肤更换成功！", type: .finish)
            } catch let error where error.isCancellationError {
            } catch {
                err("更换皮肤失败：\(error.localizedDescription)")
                hint("更换皮肤失败：\(error.localizedDescription)", type: .critical)
            }
        }
    }

    /// 将账号变动持久化到配置文件。
    private static func persistAccounts() {
        do {
            try LauncherConfig.save()
        } catch {
            err("保存配置文件失败：\(error.localizedDescription)")
        }
    }
}
