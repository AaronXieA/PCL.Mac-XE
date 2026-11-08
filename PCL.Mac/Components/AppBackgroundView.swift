//
//  AppBackgroundView.swift
//  PCL.Mac XE
//
//  启动器自定义背景的绘制，显示方式与 PCL2 对齐。
//

import AppKit
import SwiftUI

struct AppBackgroundView: View {
    let image: NSImage?
    let mode: LauncherConfig.BackgroundDisplayMode
    var opacity: Double = 1.0

    /// PCL2 ColorBg1 的微蓝色遮罩。
    private static let overlayColor: Color = .init(
        red: 0xE0 / 255,
        green: 0xEA / 255,
        blue: 0xFD / 255
    )
    private static let overlayOpacity: Double = 0.30

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(0xC0DEF5)

                if let image {
                    BackgroundImageLayer(image: image, mode: mode, size: geometry.size)
                        .opacity(opacity)
                    Self.overlayColor.opacity(Self.overlayOpacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct BackgroundImageLayer: View {
    let image: NSImage
    let mode: LauncherConfig.BackgroundDisplayMode
    let size: CGSize

    private var effectiveMode: LauncherConfig.BackgroundDisplayMode {
        guard mode == .smart else { return mode }
        // 与 PCL2 一致：图片较小时平铺，较大时适应。
        let isSmallImage: Bool = image.size.width < size.width / 2 && image.size.height < size.height / 2
        return isSmallImage ? .tile : .fit
    }

    var body: some View {
        Group {
            switch effectiveMode {
            case .smart, .fit:
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            case .center:
                Image(nsImage: image)
                    .resizable()
                    .frame(width: image.size.width, height: image.size.height)
            case .tile:
                Canvas { context, canvasSize in
                    let tileSize: CGSize = image.size
                    guard tileSize.width > 0, tileSize.height > 0 else { return }
                    let resolvedImage = context.resolve(Image(nsImage: image))
                    var y: CGFloat = 0
                    while y < canvasSize.height {
                        var x: CGFloat = 0
                        while x < canvasSize.width {
                            context.draw(
                                resolvedImage,
                                in: CGRect(x: x, y: y, width: tileSize.width, height: tileSize.height)
                            )
                            x += tileSize.width
                        }
                        y += tileSize.height
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}
