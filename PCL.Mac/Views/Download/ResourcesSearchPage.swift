//
//  ResourcesSearchPage.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2026/3/16.
//

import SwiftUI
import Core

struct ResourcesSearchPage: View {
    @StateObject private var viewModel: ResourcesSearchViewModel
    @EnvironmentObject private var instanceManager: InstanceManager
    
    init(type: ResourceType) {
        self._viewModel = StateObject(wrappedValue: ResourcesSearchViewModel.shared(for: type))
    }
    
    var body: some View {
        CardContainer {
            MySearchBox(placeholder: "搜索\(viewModel.type.localizedName)", initialText: viewModel.query) { query in
                performSearch(query, page: 0)
            }
            filterBar
            
            if let searchResults = viewModel.searchResults {
                PaginatedContainer(currentPage: $viewModel.currentPage, pageCount: viewModel.totalPages) { _ in
                    MyCard(nil) {
                        LazyVStack(spacing: 0) {
                            ForEach(searchResults) { project in
                                ProjectListItemView(project: project)
                                    .onTapGesture {
                                        AppRouter.shared.append(.projectInstall(project: project, instanceId: viewModel.installTarget.id))
                                    }
                            }
                        }
                    }
                }
                .onChange(of: viewModel.currentPage) { newValue in
                    // 搜索进行中（结果已被清空）时不重复发起请求，避免切换筛选时多打一次
                    guard viewModel.searchResults != nil else { return }
                    performSearch(viewModel.query, page: newValue)
                }
            } else {
                MyLoading(viewModel: viewModel.loadingVM)
            }
        }
        .task {
            // 返回本页时保留上一次的搜索状态，只在尚未加载时发起搜索
            guard viewModel.searchResults == nil else { return }
            performSearch(viewModel.query, page: viewModel.currentPage)
        }
        .onChange(of: viewModel.filterSignature) { _ in
            performSearch(viewModel.query, page: 0)
        }
    }
    
    // MARK: - 筛选栏
    
    private var filterBar: some View {
        MyCard(nil, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    FilterFunnelShape()
                        .fill(Color.color2)
                        .frame(width: 15, height: 15)
                    Text("筛选器")
                        .font(.custom("PingFangSC-Semibold", size: 17))
                        .foregroundStyle(Color.color1)
                }
                
                HStack(spacing: 12) {
                    MySelect($viewModel.sort, entries: SearchSort.allCases)
                        .frame(maxWidth: .infinity)
                    MySelect($viewModel.gameVersion, entries: gameVersionOptions)
                        .frame(maxWidth: .infinity)
                }
                
                HStack(spacing: 12) {
                    if viewModel.type == .mod || viewModel.type == .modpack {
                        MySelect($viewModel.loader, entries: loaderOptions)
                            .frame(maxWidth: .infinity)
                    }
                    if viewModel.type == .mod {
                        MySelect($viewModel.category, entries: categoryOptions)
                            .frame(maxWidth: .infinity)
                    }
                    MySelect($viewModel.installTarget, entries: instanceOptions)
                        .frame(maxWidth: secondRowSelectCount > 1 ? .infinity : 240)
                    if secondRowSelectCount == 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    /// 第二行筛选器的数量，用于决定宽度分配。
    private var secondRowSelectCount: Int {
        switch viewModel.type {
        case .mod: 3
        case .modpack: 2
        case .resourcepack, .shader: 1
        }
    }
    
    private var gameVersionOptions: [GameVersionFilter] {
        let releases: [String] = (VersionManifest.shared?.versions ?? [])
            .filter { $0.type == .release }
            .map(\.id)
        return [.all] + releases.map { .init(id: $0, name: $0) }
    }
    
    private var loaderOptions: [LoaderFilter] {
        [.all, .init(loader: .fabric), .init(loader: .forge), .init(loader: .neoforge)]
    }
    
    private var categoryOptions: [CategoryFilter] {
        [.all] + Self.modCategories.map { slug in
            .init(slug: slug, name: ProjectListItemModel.localizeTag(slug) ?? Self.categoryFallbackNames[slug] ?? slug)
        }
    }
    
    private var instanceOptions: [InstallTarget] {
        var options: [InstallTarget] = [.current]
        let allInstances: [MinecraftInstance] = instanceManager.repositories.values
            .flatMap { repository in Array((repository.instances ?? [:]).values) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        options.append(contentsOf: allInstances.map { .init(id: $0.id, name: $0.name) })
        return options
    }
    
    private static let modCategories: [String] = [
        "adventure", "cursed", "decoration", "economy", "equipment", "food", "game-mechanics",
        "library", "magic", "optimization", "social", "technology", "transportation", "utility", "worldgen"
    ]
    
    private static let categoryFallbackNames: [String: String] = [
        "adventure": "冒险", "cursed": "诅咒", "decoration": "装饰", "economy": "经济",
        "equipment": "装备", "food": "食物", "game-mechanics": "游戏机制", "library": "前置库",
        "magic": "魔法", "optimization": "优化", "social": "社交", "technology": "科技",
        "transportation": "运输", "utility": "实用工具", "worldgen": "世界生成"
    ]
    
    // MARK: - 搜索
    
    private func performSearch(_ query: String, page: Int) {
        Task {
            do {
                try await viewModel.search(query, pageIndex: page)
            } catch let error where error.isCancellationError {
            } catch {
                err("搜索\(viewModel.type.localizedName)失败：\(error.localizedDescription)")
                await MainActor.run {
                    viewModel.loadingVM.fail(with: "搜索\(viewModel.type.localizedName)失败：\(error.localizedDescription)")
                }
            }
        }
    }
}

/// PCL 风格的漏斗筛选图标。
private struct FilterFunnelShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path: Path = .init()
        let width: CGFloat = rect.width
        let height: CGFloat = rect.height
        path.move(to: .init(x: width * 0.05, y: height * 0.08))
        path.addLine(to: .init(x: width * 0.95, y: height * 0.08))
        path.addLine(to: .init(x: width * 0.61, y: height * 0.56))
        path.addLine(to: .init(x: width * 0.61, y: height * 0.93))
        path.addLine(to: .init(x: width * 0.39, y: height * 0.93))
        path.addLine(to: .init(x: width * 0.39, y: height * 0.56))
        path.closeSubpath()
        return path
    }
}

struct ProjectListItemView: View {
    private let project: ProjectListItemModel
    private let isTagRowSeparated: Bool
    
    init(project: ProjectListItemModel, primary: Bool = false) {
        self.project = project
        self.isTagRowSeparated = primary && project.tags.count > 3
    }
    
    var body: some View {
        MyListItem {
            HStack {
                Group {
                    if let iconURL: URL = project.iconURL {
                        NetworkImage(url: iconURL)
                    } else {
                        Image(.iconModLogo)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 48, height: 48)
                .padding(.leading, 4)
                
                VStack(alignment: .leading, spacing: 2) {
                    MyText(project.title, size: 16)
                        .lineLimit(1)
                    
                    if isTagRowSeparated {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(project.tags, id: \.self) { tag in
                                    MyTag(tag, labelColor: .colorGray2, backgroundColor: .init(0x000000, alpha: 17 / 255), size: 12)
                                }
                            }
                        }
                        
                        MyText(project.description, color: .colorGray3)
                    } else {
                        HStack {
                            ForEach(project.tags.prefix(3), id: \.self) { tag in
                                MyTag(tag, labelColor: .colorGray2, backgroundColor: .init(0x000000, alpha: 17 / 255), size: 12)
                            }
                            MyText(project.description, color: .colorGray3)
                                .lineLimit(1)
                        }
                    }
                    
                    HStack {
                        InformationView(icon: .iconSettingsPage, text: project.supportDescription, width: 200)
                        InformationView(icon: .iconDownloadPage, text: project.downloads, width: 150)
                        InformationView(icon: .iconUpload, text: project.lastUpdate, width: 150)
                        Spacer()
                    }
                    
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
    }
    
    private struct InformationView: View {
        private let icon: ImageResource
        private let text: String
        private let width: CGFloat
        
        init(icon: ImageResource, text: String, width: CGFloat) {
            self.icon = icon
            self.text = text
            self.width = width
        }
        
        var body: some View {
            HStack(spacing: 6) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14)
                    .foregroundStyle(Color.colorGray3)
                MyText(text, size: 12, color: .colorGray3)
            }
            .frame(width: width, alignment: .leading)
        }
    }
}
