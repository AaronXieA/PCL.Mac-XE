//
//  InstalledResourcesPage.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2026/6/7.
//

import SwiftUI
import Core

struct InstalledResourcesPage: View {
    @EnvironmentObject private var instanceManager: InstanceManager
    @StateObject private var viewModel: InstalledResourcesViewModel
    @StateObject private var loadingVM: MyLoadingViewModel
    @State private var hasLoaderBackup: Bool = false
    
    init(instanceManager: InstanceManager, id: String, type: ResourceType) {
        self._viewModel = .init(wrappedValue: .init(instanceManager: instanceManager, id: id, type: type))
        self._loadingVM = .init(wrappedValue: MyLoadingViewModel(text: "加载中"))
    }
    
    var body: some View {
        Group {
            if !viewModel.supportMods {
                MyCard(nil) {
                    VStack(spacing: 10) {
                        MyText("该实例不可使用 Mod", size: 19, color: .color3)
                        
                        Rectangle()
                            .fill(Color.color3)
                            .frame(height: 2)
                        
                        MyText("你需要先安装 Forge、Fabric 等 Mod 加载器才能使用 Mod，请在安装实例时选择这些加载器。\n如果你已经安装了 Mod 加载器，那么你很可能选择了错误的实例，请点击实例选择按钮切换实例。")
                            .padding(.vertical, 5)
                        
                        HStack(spacing: 20) {
                            MyButton("转到下载页面", type: .highlight) {
                                AppRouter.shared.setRoot(.download)
                            }
                            .frame(width: 140)
                            MyButton("实例选择") {
                                AppRouter.shared.setRoot(.launch)
                                AppRouter.shared.append(.instanceList(repositoryId: viewModel.currentRepositoryId))
                            }
                            .frame(width: 140)
                        }
                        .frame(height: 35)
                    }
                    .padding(10)
                }
                .padding(40)
            } else {
                CardContainer {
                    MySearchBox(placeholder: "搜索\(viewModel.type.localizedName)") { keyword in
                        viewModel.setSearchKeyword(keyword)
                    }
                    
                    MyCard(nil) {
                        HStack {
                            MyButton("打开文件夹") {
                                if let directory = viewModel.directory() {
                                    NSWorkspace.shared.open(directory)
                                }
                            }
                            .frame(width: 110)
                            if viewModel.type == .mod, let instance = viewModel.instance, instance.modLoader != nil {
                                MyButton("一键更新模组", type: .black) {
                                    Task { await updateMods(for: instance) }
                                }
                                .frame(width: 110)
                            }
                            if viewModel.type == .mod, let instance = viewModel.instance, instance.modLoader == .fabric {
                                MyButton("重装 Loader", type: .black) {
                                    Task { await chooseLoaderVersion(for: instance) }
                                }
                                .frame(width: 100)
                            }
                            if viewModel.type == .mod, let instance = viewModel.instance, instance.modLoader == .fabric, hasLoaderBackup {
                                MyButton("撤回 Loader") {
                                    Task { await rollbackLoader(for: instance) }
                                }
                                .frame(width: 100)
                            }
                            if viewModel.type == .mod, let instance = viewModel.instance {
                                MyButton("撤回上次更新", disabled: !ModUpdateService.hasBackup(for: instance)) {
                                    Task {
                                        do {
                                            let count: Int = try ModUpdateService.rollbackLatest(for: instance)
                                            hint("已撤回上次更新，恢复 \(count) 个 Mod。", type: .finish)
                                            try await viewModel.load()
                                        } catch {
                                            err("撤回更新失败：\(error.localizedDescription)")
                                        }
                                    }
                                }
                                .frame(width: 110)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(height: 40)
                    }
                    .cardIndex(1)
                    
                    if let resources = viewModel.resources, !resources.isEmpty {
                        PaginatedContainer(currentPage: $viewModel.currentPage, pageCount: viewModel.pageCount) { currentPage in
                            MyCard(nil) {
                                VStack(spacing: 0) {
                                    ForEach(resources, id: \.id) { resource in
                                        ResourceListItem(viewModel: viewModel, resource: resource)
                                    }
                                }
                            }
                            .onChange(of: currentPage) { _ in
                                viewModel.updateResources()
                            }
                        }
                    } else {
                        MyLoading(viewModel: loadingVM)
                    }
                }
            }
        }
        .task {
            if let instance = viewModel.instance {
                hasLoaderBackup = FabricLoaderService.hasBackup(for: instance)
                if viewModel.type == .mod, instance.modLoader == .fabric {
                    // 预取版本列表，点击「重装 Loader」时直接弹出，不再等待网络。
                    Task { _ = try? await FabricLoaderService.loaderVersions(for: instance.version.id) }
                }
            }
            loadingVM.reset()
            do {
                try await viewModel.load()
            } catch {
                err("加载资源列表失败：\(error.localizedDescription)")
                loadingVM.fail(with: "加载资源列表失败：\(error.localizedDescription)")
            }
        }
        .onChange(of: viewModel.resources) { newValue in
            if let newValue, newValue.isEmpty {
                if viewModel.hasSearchKeyword {
                    loadingVM.fail(with: "没有匹配的结果")
                } else {
                    loadingVM.fail(with: "这个实例没有安装任何\(viewModel.type.localizedName)！")
                }
            }
        }
        .onDisappear {
            viewModel.resources = nil
        }
    }
    
    /// 一键更新实例中的所有 Mod（内测功能）。
    private func updateMods(for instance: MinecraftInstance) async {
        guard await MessageBoxManager.shared.showTextAsync(
            title: "确定要更新吗？",
            content: "一键更新模组是PCL.Mac XE的内测功能，不保证稳定性，如果发现更新后游戏无法启动，请点击撤回！",
            level: .info,
            .no(),
            .yes(label: "确认", type: .highlight)
        ) == 1 else {
            return
        }
        
        await ModUpdateService.requestUpdate(for: instance) { updatedMods in
            Task { @MainActor in
                if updatedMods.isEmpty {
                    hint("所有 Mod 都已是最新版本！", type: .finish)
                } else {
                    hint("已更新 \(updatedMods.count) 个 Mod。", type: .finish)
                    let detail: String = updatedMods.map {
                        "· \($0.name)：\($0.oldVersion) → \($0.newVersion)"
                    }.joined(separator: "\n")
                    let choice: Int = await MessageBoxManager.shared.showTextAsync(
                        title: "模组更新完成（\(updatedMods.count) 个）",
                        content: "以下 Mod 已更新：\n\(detail)\n\n如更新后出现问题，可撤回本次更新。",
                        level: .info,
                        .no(label: "撤回更新", type: .red),
                        .yes(label: "完成", type: .highlight)
                    )
                    if choice == 0 {
                        do {
                            let count: Int = try ModUpdateService.rollbackLatest(for: instance)
                            hint("已撤回本次更新，恢复 \(count) 个 Mod。", type: .finish)
                        } catch {
                            err("撤回更新失败：\(error.localizedDescription)")
                        }
                    }
                }
                try? await viewModel.load()
            }
        }
    }
    
    /// 选择要重装的 Fabric Loader 版本。
    private func chooseLoaderVersion(for instance: MinecraftInstance) async {
        guard await MessageBoxManager.shared.showTextAsync(
            title: "确定要重装 Loader 吗？",
            content: "将重装实例（\(instance.name)）的 Fabric Loader，并在下一步选择要安装的版本。\n重装前会自动备份当前 Loader；若重装后游戏无法启动，可点击「撤回 Loader」恢复原版本。",
            level: .info,
            .no(),
            .yes(label: "确认", type: .highlight)
        ) == 1 else {
            return
        }
        
        let versions: [FabricLoaderService.LoaderVersion]
        let currentVersion: String? = FabricLoaderService.currentLoaderVersion(of: instance)
        do {
            versions = try await FabricLoaderService.loaderVersions(for: instance.version.id)
        } catch {
            err("获取 Fabric Loader 版本列表失败：\(error.localizedDescription)")
            return
        }
        
        var displayVersions: [FabricLoaderService.LoaderVersion] = Array(versions.prefix(60))
        if let currentVersion, !displayVersions.contains(where: { $0.version == currentVersion }) {
            displayVersions.append(.init(version: currentVersion, stable: true))
        }
        let items: [ListItem] = displayVersions.map { entry in
            var description: String = entry.stable ? "稳定版" : "测试版"
            if entry.version == currentVersion {
                description = "当前版本 · \(description)"
            }
            return .init(name: "Fabric Loader \(entry.version)", description: description)
        }
        
        guard let index: Int = await MessageBoxManager.shared.showListAsync(
            title: "选择要重装的 Fabric Loader 版本",
            items: items
        ) else {
            return
        }
        let targetVersion: String = displayVersions[index].version
        startLoaderReinstall(instance: instance, targetVersion: targetVersion, currentVersion: currentVersion)
    }
    
    /// 在后台任务中重装 Fabric Loader。
    private func startLoaderReinstall(instance: MinecraftInstance, targetVersion: String, currentVersion: String?) {
        let name: String = currentVersion == targetVersion
            ? "重装 Fabric Loader \(targetVersion)"
            : "更新 Fabric Loader \(currentVersion ?? "未知") → \(targetVersion)"
        let repository: MinecraftRepository = instanceManager.currentRepository
        let task: MyTask<EmptyModel> = .init(
            name: name,
            model: EmptyModel(),
            [
                .init(0, "重装 Fabric Loader") { subTask, _ in
                    var lastProgress: Double = -1
                    _ = try await FabricLoaderService.reinstall(
                        for: instance,
                        in: repository,
                        loaderVersion: targetVersion
                    ) { progress in
                        // 下载器进度回调非常频繁，限制刷新频率，避免拖慢下载。
                        guard progress >= 1 || progress - lastProgress >= 0.01 else { return }
                        lastProgress = progress
                        subTask.setProgress(progress)
                    }
                }
            ]
        )
        TaskManager.shared.execute(task: task) { error in
            guard error == nil else { return }
            hasLoaderBackup = FabricLoaderService.hasBackup(for: instance)
        }
    }
    
    /// 撤回最近一次 Loader 重装。
    private func rollbackLoader(for instance: MinecraftInstance) async {
        do {
            let version: String? = try FabricLoaderService.rollbackLatest(for: instance)
            hasLoaderBackup = FabricLoaderService.hasBackup(for: instance)
            hint("已撤回 Loader 重装，恢复 \(version ?? "原版本")。", type: .finish)
        } catch {
            err("撤回 Loader 失败：\(error.localizedDescription)")
        }
    }
}

private struct ResourceListItem: View {
    @ObservedObject private var viewModel: InstalledResourcesViewModel
    @ObservedObject private var resource: ResourceDisplayModel
    
    init(viewModel: InstalledResourcesViewModel, resource: ResourceDisplayModel) {
        self.viewModel = viewModel
        self.resource = resource
    }
    
    var body: some View {
        MyListItem { hovered in
            HStack {
                resource.icon.makeView()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Color.color1)
                
                VStack(alignment: .leading) {
                    HStack(alignment: .center, spacing: 0) {
                        Group {
                            if #available(macOS 13, *) {
                                MyText(resource.name)
                                    .strikethrough(resource.disabled)
                            } else {
                                MyText((resource.disabled ? "（已禁用）" : "") + resource.name)
                            }
                        }
                        .animation(.easeInOut(duration: 0.1), value: resource.disabled)
                        
                        MyText(" | \(resource.fileName)", size: 12, color: .colorGray3)
                        HStack(spacing: 3) {
                            ForEach(resource.tags, id: \.self) { tag in
                                MyTag(tag, labelColor: .colorGray2, backgroundColor: .black.opacity(0.05), size: 12)
                            }
                        }
                        .padding(.leading, 3)
                    }
                    HStack(spacing: 0) {
                        if let version = resource.version {
                            MyText("\(version) | ", size: 12, color: .colorGray3)
                        }
                        MyText(resource.description, size: 12, color: .colorGray3)
                    }
                }
                .lineLimit(1)
                .textSelection(.enabled)
                
                Spacer(minLength: 0)
                
                HStack {
                    ListItemButton(.resource(.btnOpen), scale: 0.8) {
                        NSWorkspace.shared.activateFileViewerSelecting([resource.url])
                    }
                    if !resource.sources.isEmpty {
                        ListItemButton(.resource(.iconAbout), clickPerform: viewInfo)
                    }
                    ListItemButton(.resource(resource.disabled ? .btnEnable : .btnDisable), clickPerform: toggleDisabled)
                        .animation(.easeInOut(duration: 0.1), value: resource.disabled)
                }
                .padding(.horizontal, 4)
                .allowsHitTesting(hovered)
                .opacity(hovered ? 1 : 0)
            }
        }
    }
    
    private func viewInfo() {
        Task {
            do {
                guard let info = try await viewModel.loadInfo(for: resource) else {
                    hint("未找到 \(resource.fileName) 对应的远端资源信息！", type: .critical)
                    return
                }
                AppRouter.shared.append(.projectInstall(project: info, instanceId: nil))
            } catch {
                err("获取资源信息失败：\(error.localizedDescription)")
                hint("获取资源信息失败：\(error.localizedDescription)", type: .critical)
            }
        }
    }
    
    private func toggleDisabled() {
        do {
            try viewModel.toggleDisabled(resource)
        } catch {
            let type = resource.disabled ? "启用" : "禁用"
            err("\(type)资源失败：\(error.localizedDescription)")
            hint("\(type)资源失败：\(error.localizedDescription)", type: .critical)
        }
    }
}
