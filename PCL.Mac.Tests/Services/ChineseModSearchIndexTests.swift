//
//  ChineseModSearchIndexTests.swift
//  PCL.Mac XE
//

import Foundation
import Core
import Testing
@testable import PCL_Mac_XE

struct ChineseModSearchIndexTests {
    @Test func testChineseIndex() throws {
        let fileURL: URL = FileManager.default.temporaryDirectory
            .appending(path: "WikiEntries-\(UUID().uuidString).txt")
        try "@example-mod|示例模组\n@minimap-mod|小地图 (Minimap)\n".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let index: ChineseModSearchIndex = try ChineseModSearchIndex(fileURL: fileURL)

        #expect(ChineseModSearchIndex.isChineseQuery("小地图"))
        #expect(!ChineseModSearchIndex.isChineseQuery("minimap"))

        let plan: ChineseModSearchPlan? = index.plan(for: "小地图")
        #expect(plan?.englishQuery == "minimap")
        #expect(plan?.slugs.contains("minimap-mod") == true)
        #expect(plan?.chineseNames["minimap-mod"] == "小地图 (Minimap)")

        #expect(index.plan(for: "不存在") == nil)
    }

    @Test func testBundledDatabase() throws {
        let index: ChineseModSearchIndex = try #require(ChineseModSearchIndex.shared)
        let plan: ChineseModSearchPlan = try #require(index.plan(for: "小地图"))
        #expect(!plan.slugs.isEmpty)
        #expect(!plan.englishQuery.isEmpty)
        #expect(plan.slugs.count <= 100)
        #expect(plan.slugs.contains("xaeros-minimap"))
    }

    @Test @MainActor func testChineseSearchIntegration() async throws {
        let viewModel: ResourcesSearchViewModel = .init(type: .mod)
        try await viewModel.search("小地图")

        let results: [ProjectListItemModel] = try #require(viewModel.searchResults)
        #expect(!results.isEmpty)
        #expect(results.contains { $0.chineseTitle != nil })
    }
}
