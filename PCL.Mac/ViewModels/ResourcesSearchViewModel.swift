//
//  ResourcesSearchViewModel.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2026/3/16.
//

import Foundation
import Core

/// 搜索排序方式，对应 Modrinth 的 `index` 参数。
enum SearchSort: String, CaseIterable, CustomStringConvertible {
    case relevance, downloads, follows, newest, updated
    
    var description: String {
        switch self {
        case .relevance: "相关度"
        case .downloads: "下载量"
        case .follows: "关注量"
        case .newest: "最新发布"
        case .updated: "最近更新"
        }
    }
}

/// 游戏版本筛选项，`id` 为 `nil` 表示全部版本。
struct GameVersionFilter: Hashable, CustomStringConvertible {
    let id: String?
    let name: String
    
    static let all: GameVersionFilter = .init(id: nil, name: "全部版本")
    
    var description: String { name }
}

/// 加载器筛选项。
struct LoaderFilter: Hashable, CustomStringConvertible {
    let loader: ModLoader?
    
    static let all: LoaderFilter = .init(loader: nil)
    
    var description: String { loader?.description ?? "全部加载器" }
    
    var modrinthValue: [String] { loader.map { [$0.rawValue] } ?? [] }
}

/// 分类筛选项。
struct CategoryFilter: Hashable, CustomStringConvertible {
    let slug: String?
    let name: String
    
    static let all: CategoryFilter = .init(slug: nil, name: "全部分类")
    
    var description: String { name }
}

/// 安装目标实例。
struct InstallTarget: Hashable, CustomStringConvertible {
    enum Kind: Hashable {
        /// 不选择实例，只按版本 / 加载器筛选
        case none
        /// 使用当前选中的实例
        case current
        /// 指定实例
        case specific(UUID)
    }
    
    let kind: Kind
    let name: String
    
    static let current: InstallTarget = .init(kind: .current, name: "当前实例")
    static let none: InstallTarget = .init(kind: .none, name: "不选择")
    
    init(kind: Kind, name: String) {
        self.kind = kind
        self.name = name
    }
    
    init(id: UUID, name: String) {
        self.kind = .specific(id)
        self.name = name
    }
    
    var id: UUID? {
        if case .specific(let id) = kind { return id }
        return nil
    }
    
    var description: String { name }
}

class ResourcesSearchViewModel: ObservableObject {
    @Published public var searchResults: [ProjectListItemModel]?
    @Published public var query: String = ""
    
    // MARK: 筛选条件
    
    @Published public var sort: SearchSort = .relevance
    @Published public var gameVersion: GameVersionFilter = .all
    @Published public var loader: LoaderFilter = .all
    @Published public var category: CategoryFilter = .all
    @Published public var installTarget: InstallTarget = .current
    @Published public var currentPage: Int = 0
    
    public let type: ResourceType
    public let loadingVM: MyLoadingViewModel = .init(text: "加载中")
    private var lastSearchResponse: ModrinthAPIClient.SearchResponse?
    private var searchToken: Int = 0
    
    public var totalPages: Int {
        guard let lastSearchResponse else { return 0 }
        return Int(ceil(Double(lastSearchResponse.totalHits) / Double(lastSearchResponse.limit)))
    }
    
    /// 筛选条件标识，用于在变化时触发重新搜索。
    public var filterSignature: String {
        "\(sort.rawValue)|\(gameVersion.id ?? "")|\(loader.loader?.rawValue ?? "")|\(category.slug ?? "")"
    }
    
    private static var cache: [ResourceType: ResourcesSearchViewModel] = [:]
    
    /// 获取按类型缓存的实例，使离开详情页再返回时保留搜索词、筛选条件与结果。
    public static func shared(for type: ResourceType) -> ResourcesSearchViewModel {
        if let cached = cache[type] {
            return cached
        }
        let viewModel: ResourcesSearchViewModel = .init(type: type)
        cache[type] = viewModel
        return viewModel
    }
    
    public init(type: ResourceType) {
        self.type = type
    }
    
    public func search(_ query: String, pageIndex: Int = 0) async throws {
        let token: Int = await MainActor.run {
            searchToken += 1
            return searchToken
        }
        await MainActor.run {
            self.query = query
            self.currentPage = pageIndex
            loadingVM.reset()
            searchResults = nil
        }
        
        let chinesePlan: ChineseModSearchPlan? = try await chinesePlanIfNeeded(for: query)
        
        if let chinesePlan {
            let response: ModrinthAPIClient.SearchResponse
            var directProjects: [ModrinthProject] = []
            
            if pageIndex == 0 {
                async let searchRequest = ModrinthAPIClient.shared.search(
                    type: type,
                    chinesePlan.englishQuery,
                    forVersion: gameVersion.id,
                    loaders: loader.modrinthValue,
                    categories: category.slug.map { [$0] } ?? [],
                    index: sort.rawValue,
                    pageIndex: pageIndex
                )
                async let projectsRequest = ModrinthAPIClient.shared.projects(Array(chinesePlan.slugs.prefix(20)))
                response = try await searchRequest
                directProjects = (try? await projectsRequest) ?? []
            } else {
                response = try await ModrinthAPIClient.shared.search(
                    type: type,
                    chinesePlan.englishQuery,
                    forVersion: gameVersion.id,
                    loaders: loader.modrinthValue,
                    categories: category.slug.map { [$0] } ?? [],
                    index: sort.rawValue,
                    pageIndex: pageIndex
                )
            }
            try Task.checkCancellation()
            
            let slugOrder: [String: Int] = Dictionary(uniqueKeysWithValues: chinesePlan.slugs.enumerated().map {
                ($0.element, $0.offset)
            })
            directProjects.sort { lhs, rhs in
                (slugOrder[lhs.slug] ?? Int.max) < (slugOrder[rhs.slug] ?? Int.max)
            }
            
            var merged: [ModrinthProject] = []
            var seenProjectIds: Set<String> = []
            for project in directProjects + response.hits {
                guard seenProjectIds.insert(project.id).inserted else { continue }
                merged.append(project)
            }
            
            let results: [ProjectListItemModel] = merged
                .filter { $0.clientCompatibility != .unsupported }
                .map { ProjectListItemModel($0, chineseTitle: chinesePlan.chineseNames[$0.slug]) }
            
            await MainActor.run {
                guard searchToken == token else { return }
                lastSearchResponse = response
                searchResults = results
            }
            return
        }
        
        let response: ModrinthAPIClient.SearchResponse = try await ModrinthAPIClient.shared.search(
            type: type,
            query,
            forVersion: gameVersion.id,
            loaders: loader.modrinthValue,
            categories: category.slug.map { [$0] } ?? [],
            index: sort.rawValue,
            pageIndex: pageIndex
        )
        try Task.checkCancellation()
        
        let results: [ProjectListItemModel] = response.hits
            .filter { $0.clientCompatibility != .unsupported }
            .map { ProjectListItemModel($0) }
        
        await MainActor.run {
            // 丢弃过期的搜索结果，避免快速切换筛选条件时出现旧数据
            guard searchToken == token else { return }
            lastSearchResponse = response
            searchResults = results
        }
    }
    
    public func changePage(_ page: Int) async throws {
        try await search(query, pageIndex: page)
    }
    
    // MARK: - 中文搜索
    
    private enum ChineseSearchLookup: Sendable {
        case unavailable
        case noMatch
        case plan(ChineseModSearchPlan)
    }
    
    /// 中文查询转换为搜索计划；非中文查询或索引缺失时返回 `nil`。
    private func chinesePlanIfNeeded(for query: String) async throws -> ChineseModSearchPlan? {
        guard type == .mod, ChineseModSearchIndex.isChineseQuery(query) else { return nil }
        
        let lookup: ChineseSearchLookup = await Task.detached(priority: .userInitiated) {
            guard let index = ChineseModSearchIndex.shared else { return .unavailable }
            guard let plan = index.plan(for: query) else { return .noMatch }
            return .plan(plan)
        }.value
        
        switch lookup {
        case .unavailable:
            return nil
        case .noMatch:
            throw ChineseSearchNoResultError()
        case .plan(let plan):
            return plan
        }
    }
}
