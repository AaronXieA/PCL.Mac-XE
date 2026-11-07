//
//  ChineseModSearchIndex.swift
//  PCL.Mac XE
//
//  中文模组搜索索引。
//  数据来源：PCL2（Meloong-Git/PCL）的 PCLCS/Resource/WikiEntries.txt。
//

import Foundation

/// 中文查询转换后的搜索计划。
public struct ChineseModSearchPlan: Sendable {
    /// 转换得到的英文搜索关键词。
    public let englishQuery: String
        /// 直接请求的 Modrinth slug 列表，按匹配度排序。
    public let slugs: [String]
    /// Modrinth slug 对应的中文译名。
    public let chineseNames: [String: String]

    public init(englishQuery: String, slugs: [String], chineseNames: [String: String]) {
        self.englishQuery = englishQuery
        self.slugs = slugs
        self.chineseNames = chineseNames
    }
}

/// 中文搜索没有匹配结果。
public struct ChineseSearchNoResultError: LocalizedError {
    public init() {}

    public var errorDescription: String? {
        "未找到对应的中文模组"
    }
}

/// PCL2 中文译名数据库的解析与检索。
public final class ChineseModSearchIndex: @unchecked Sendable {
    /// 内置数据库索引。资源缺失时返回 `nil`。
    public static let shared: ChineseModSearchIndex? = {
        guard let url = Bundle.main.url(forResource: "WikiEntries", withExtension: "txt") else {
            err("未找到中文译名数据库 WikiEntries.txt")
            return nil
        }
        do {
            return try ChineseModSearchIndex(fileURL: url)
        } catch {
            err("加载中文译名数据库失败：\(error.localizedDescription)")
            return nil
        }
    }()

    private struct Entry {
        let slug: String
        let chineseName: String
        let aliases: [String]
        /// 数据行序，用于在相似度相同时排序。
        let lineIndex: Int
    }

    private let entries: [Entry]
    private let totalEntries: Double

    private static let stopWords: Set<String> = [
        "the", "of", "mod", "and", "forge", "fabric", "for", "quilt", "neoforge"
    ]

    /// 使用指定数据文件创建索引。
    public init(fileURL: URL) throws {
        let content: String = try String(contentsOf: fileURL, encoding: .utf8)
        var lines: [String] = content
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\r", with: "") }
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        // 最后一行是浏览量编码，不参与检索。
        if let last: String = lines.last, !last.contains("|") && !last.contains("¨") {
            lines.removeLast()
        }

        var parsedEntries: [Entry] = []
        for (lineIndex, line) in lines.enumerated() where !line.isEmpty {
            for token in line.components(separatedBy: "¨") {
                let parts: [String] = token.components(separatedBy: "|")
                guard parts.count >= 2 else { continue }
                guard let slug: String = Self.modrinthSlug(from: parts[0]) else { continue }
                var chineseName: String = parts[parts.count - 1].trimmingCharacters(in: .whitespaces)
                guard !chineseName.isEmpty else { continue }
                if chineseName.contains("*") {
                    let englishName: String = slug
                        .replacingOccurrences(of: "-", with: " ")
                        .replacingOccurrences(of: "/", with: " ")
                        .capitalized
                    chineseName = chineseName.replacingOccurrences(of: "*", with: " (\(englishName))")
                }
                parsedEntries.append(.init(
                    slug: slug,
                    chineseName: chineseName,
                    aliases: Self.aliases(from: chineseName),
                    lineIndex: lineIndex
                ))
            }
        }
        self.entries = parsedEntries
        self.totalEntries = Double(max(parsedEntries.count, 1))
    }

    /// 查询是否包含中文字符。
    public static func isChineseQuery(_ query: String) -> Bool {
        let trimmed: String = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }

    /// 将中文查询转换为英文关键词与直接请求的工程列表。
    public func plan(for query: String, maxMatches: Int = 100) -> ChineseModSearchPlan? {
        let normalizedQuery: String = Self.normalize(query)
        guard !normalizedQuery.isEmpty else { return nil }

        var matches: [(entry: Entry, similarity: Double)] = []
        for entry in entries {
            let similarity: Double = Self.similarity(normalizedQuery, aliases: entry.aliases)
            if similarity >= 0.25 {
                matches.append((entry, similarity))
            }
        }
        guard !matches.isEmpty else { return nil }

        matches.sort { lhs, rhs in
            lhs.similarity == rhs.similarity
                ? lhs.entry.lineIndex > rhs.entry.lineIndex
                : lhs.similarity > rhs.similarity
        }
        let topMatches = matches.prefix(maxMatches)

        var slugs: [String] = []
        var chineseNames: [String: String] = [:]
        for match in topMatches where chineseNames[match.entry.slug] == nil {
            chineseNames[match.entry.slug] = match.entry.chineseName
            slugs.append(match.entry.slug)
        }

        var wordWeights: [String: Double] = [:]
        for match in topMatches {
            let popularityFactor: Double = 1 + Double(match.entry.lineIndex) / totalEntries
            for word in Self.extractWords(from: match.entry) {
                wordWeights[word, default: 0] += match.similarity * popularityFactor
            }
        }

        let englishQuery: String
        if let best = wordWeights.max(by: { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        })?.key {
            englishQuery = best
        } else if let firstSlug: String = slugs.first {
            englishQuery = firstSlug.replacingOccurrences(of: "-", with: " ")
        } else {
            return nil
        }

        return .init(englishQuery: englishQuery, slugs: slugs, chineseNames: chineseNames)
    }

    // MARK: - 解析

    /// 从 slug 字段解析 Modrinth slug。
    private static func modrinthSlug(from field: String) -> String? {
        let value: String = field.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("@") {
            let slug: String = String(value.dropFirst())
            return slug.isEmpty ? nil : slug
        }
        if value.hasSuffix("@") {
            let slug: String = String(value.dropLast())
            return slug.isEmpty ? nil : slug
        }
        if let at: String.Index = value.firstIndex(of: "@") {
            let slug: String = String(value[value.index(after: at)...])
            return slug.isEmpty ? nil : slug
        }
        // 不含 @ 的条目仅存在于 CurseForge，本项目不使用。
        return nil
    }

    /// 提取中文名的检索别名。
    private static func aliases(from chineseName: String) -> [String] {
        var base: String = normalize(chineseName)
        if let range = base.range(of: " - ") {
            base = String(base[..<range.lowerBound])
        }
        if let range = base.range(of: " (") {
            let beforeParenthesis: String = String(base[..<range.lowerBound])
            let aliasList: [String] = beforeParenthesis
                .components(separatedBy: "/")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return aliasList + [base]
        }
        return base
            .components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func normalize(_ text: String) -> String {
        let simplified: String = text.applyingTransform(StringTransform(rawValue: "Traditional-Simplified"), reverse: false) ?? text
        return simplified
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    // MARK: - 相似度

    private static func similarity(_ query: String, aliases: [String]) -> Double {
        var best: Double = 0
        for alias in aliases where !alias.isEmpty {
            if alias == query { return 1.0 }
            if alias.count >= 2 && alias.contains(query) {
                best = max(best, 0.9)
            }
            if query.count >= 2 && query.contains(alias) {
                best = max(best, 0.8)
            }
            best = max(best, diceCoefficient(query, alias))
        }
        return best
    }

    /// 字符二元组 Dice 相似度。
    private static func diceCoefficient(_ lhs: String, _ rhs: String) -> Double {
        let left: [Character] = Array(lhs)
        let right: [Character] = Array(rhs)
        guard left.count >= 2, right.count >= 2 else { return 0 }

        var leftBigrams: [String: Int] = [:]
        for index in 0..<(left.count - 1) {
            let bigram: String = String(left[index]) + String(left[index + 1])
            leftBigrams[bigram, default: 0] += 1
        }

        var intersection: Int = 0
        var rightCount: Int = 0
        for index in 0..<(right.count - 1) {
            let bigram: String = String(right[index]) + String(right[index + 1])
            rightCount += 1
            if let count = leftBigrams[bigram], count > 0 {
                leftBigrams[bigram] = count - 1
                intersection += 1
            }
        }
        let totalBigrams: Int = (left.count - 1) + rightCount
        guard totalBigrams > 0 else { return 0 }
        return 2 * Double(intersection) / Double(totalBigrams)
    }

    // MARK: - 英文关键词

    private static func extractWords(from entry: Entry) -> [String] {
        var candidates: [String] = []
        candidates.append(entry.slug
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " "))

        let name: String = entry.chineseName
        if let start = name.range(of: " (") {
            var parenthesis: String = String(name[start.upperBound...])
            parenthesis = parenthesis.trimmingCharacters(in: .whitespaces)
            parenthesis = parenthesis.trimmingCharacters(in: CharacterSet(charactersIn: ")"))
            candidates.append(parenthesis)
        } else {
            candidates.append(name)
        }

        var words: [String] = []
        let disallowedCharacters: CharacterSet = CharacterSet(charactersIn: "{[()]}/:.,;'\"-")
        for candidate in candidates {
            for rawWord in candidate.components(separatedBy: .whitespacesAndNewlines) {
                let word: String = rawWord
                    .trimmingCharacters(in: disallowedCharacters)
                    .lowercased()
                guard word.count > 1 else { continue }
                guard !stopWords.contains(word) else { continue }
                guard Int(word) == nil else { continue }
                guard word.unicodeScalars.allSatisfy(\.isASCII) else { continue }
                words.append(word)
            }
        }

        let uniqueWords: [String] = Array(Set(words))
        let wordSet: Set<String> = Set(uniqueWords)
        return uniqueWords.filter { word in
            !uniqueWords.contains { candidate in
                candidate.count < word.count
                    && word.hasPrefix(candidate)
                    && canForm(String(word.dropFirst(candidate.count)), using: wordSet)
            }
        }
    }

    /// 判断字符串能否由其他候选词拼接而成。
    private static func canForm(_ text: String, using words: Set<String>) -> Bool {
        if words.contains(text) { return true }
        for word in words where word.count < text.count && text.hasPrefix(word) {
            if canForm(String(text.dropFirst(word.count)), using: words) {
                return true
            }
        }
        return false
    }
}
