//
//  LauncherSettingsPage.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2026/7/9.
//

import AppKit
import Core
import SwiftUI
import UniformTypeIdentifiers

struct LauncherSettingsPage: View {
    @State private var downloadSourcePolicy: DownloadSourcePolicy = LauncherConfig.shared.downloadSourcePolicy
    @State private var homepageType: LauncherConfig.HomepageType = LauncherConfig.shared.homepageType
    @State private var backgroundMode: LauncherConfig.BackgroundDisplayMode = LauncherConfig.shared.backgroundDisplayMode
    @ObservedObject private var backgroundManager: BackgroundManager = .shared
    
    var body: some View {
        CardContainer {
            MyCard("下载", foldable: false) {
                configLine(label: "下载源") {
                    MySelect(
                        $downloadSourcePolicy,
                        entries: [.officialFirst, .mirrorFirst]
                    )
                }
                .onChange(of: downloadSourcePolicy) { newValue in
                    DownloadSourceManager.shared.policy = newValue
                    LauncherConfig.shared.downloadSourcePolicy = newValue
                }
            }
            
            MyCard("个性化", foldable: false) {
                configLine(label: "主页") {
                    MySelect(
                        $homepageType,
                        entries: [.empty, .demo]
                    )
                }
                .onChange(of: homepageType) { newValue in
                    LauncherConfig.shared.homepageType = newValue
                }
                
                configLine(label: "背景图片") {
                    HStack(spacing: 10) {
                        MyText(
                            backgroundManager.fileName ?? "未设置",
                            size: 13,
                            color: .colorGray3
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 180, alignment: .trailing)
                        
                        MyButton("选择图片") {
                            selectBackgroundImage()
                        }
                        .frame(width: 96, height: 32)
                        
                        if backgroundManager.image != nil {
                            MyButton("清除") {
                                backgroundManager.clear()
                            }
                            .frame(width: 64, height: 32)
                        }
                    }
                }
                
                configLine(label: "显示方式") {
                    MySelect($backgroundMode, entries: LauncherConfig.BackgroundDisplayMode.allCases)
                }
                .onChange(of: backgroundMode) { newValue in
                    backgroundManager.setMode(newValue)
                }
            }
            .cardIndex(1)
        }
    }
    
    private func selectBackgroundImage() {
        let panel: NSOpenPanel = .init()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url: URL = panel.url else { return }
        do {
            try backgroundManager.importImage(from: url)
        } catch {
            hint("设置背景图片失败：\(error.localizedDescription)", type: .critical)
        }
    }
    
    @ViewBuilder
    private func configLine(label: String,  @ViewBuilder body: () -> some View) -> some View {
        HStack(spacing: 20) {
            MyText(label)
                .frame(width: 80, alignment: .leading)
            HStack {
                Spacer(minLength: 0)
                body()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
    }
}
