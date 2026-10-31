//
//  MarkdownView.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2026/10/31.
//

import SwiftUI

/// 轻量 Markdown 渲染视图。
/// 支持标题、无序/有序列表、分隔线、段落，以及粗体、行内代码、链接等行内格式。
struct MarkdownView: View {
    private let blocks: [Block]

    init(_ markdown: String) {
        self.blocks = Self.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 渲染

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(.custom("PingFangSC-Semibold", size: headingSize(for: level)))
                .foregroundStyle(Color.color1)
                .padding(.top, level == 1 ? 0 : 6)
        case .paragraph(let text):
            inlineText(text)
                .font(.custom("PCLEnglish", size: 14))
                .foregroundStyle(Color.color1)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let level, let text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                    .font(.custom("PCLEnglish", size: 14))
                    .foregroundStyle(Color.color3)
                inlineText(text)
                    .font(.custom("PCLEnglish", size: 14))
                    .foregroundStyle(Color.color1)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(level) * 16)
        case .numbered(let index, let text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(index).")
                    .font(.custom("PCLEnglish", size: 14))
                    .foregroundStyle(Color.color3)
                inlineText(text)
                    .font(.custom("PCLEnglish", size: 14))
                    .foregroundStyle(Color.color1)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 16)
        case .divider:
            Rectangle()
                .fill(Color.colorGray2.opacity(0.5))
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: 23
        case 2: 18
        case 3: 16
        default: 14
        }
    }

    private func inlineText(_ text: String) -> Text {
        let attributed: AttributedString = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        return Text(attributed)
    }

    // MARK: - 解析

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case bullet(level: Int, text: String)
        case numbered(index: Int, text: String)
        case divider
    }

    private static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line: String = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // 分隔线
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider)
                continue
            }

            // 标题
            if let heading = parseHeading(trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            // 列表
            let indent: Int = line.prefix(while: { $0 == " " }).count
            let level: Int = min(indent / 4, 2)
            if let item = parseUnorderedItem(trimmed) {
                blocks.append(.bullet(level: level, text: item))
                continue
            }
            if let item = parseOrderedItem(trimmed) {
                blocks.append(.numbered(index: item.index, text: item.text))
                continue
            }

            blocks.append(.paragraph(text: trimmed))
        }
        return blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        let level: Int = line.prefix(while: { $0 == "#" }).count
        guard level <= 6 else { return nil }
        let text: String = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private static func parseUnorderedItem(_ line: String) -> String? {
        for marker in ["* ", "- ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func parseOrderedItem(_ line: String) -> (index: Int, text: String)? {
        let digits: String = String(line.prefix(while: { $0.isNumber }))
        guard !digits.isEmpty, let index = Int(digits) else { return nil }
        let rest: String = String(line.dropFirst(digits.count))
        guard rest.hasPrefix(". ") || rest.hasPrefix("、") else { return nil }
        let text: String = String(rest.dropFirst(rest.hasPrefix(". ") ? 2 : 1))
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (index, text)
    }
}
