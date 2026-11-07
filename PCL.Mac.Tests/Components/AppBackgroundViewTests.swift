//
//  AppBackgroundViewTests.swift
//  PCL.Mac XE
//

import AppKit
import SwiftUI
import Testing
@testable import PCL_Mac_XE

@MainActor
struct AppBackgroundViewTests {
    @Test func testAllModesRender() throws {
        let image: NSImage = .init(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()

        for mode in LauncherConfig.BackgroundDisplayMode.allCases {
            let renderer = ImageRenderer(
                content: AppBackgroundView(image: image, mode: mode)
                    .frame(width: 320, height: 200)
            )
            renderer.scale = 1
            let renderedImage = try #require(renderer.cgImage)
            #expect(renderedImage.width == 320)
            #expect(renderedImage.height == 200)

            let bitmap: NSBitmapImageRep = .init(cgImage: renderedImage)
            let cornerRed: CGFloat = bitmap.colorAt(x: 0, y: 0)?.redComponent ?? 0
            let centerRed: CGFloat = bitmap.colorAt(x: 160, y: 100)?.redComponent ?? 0

            if mode == .center {
                // 居中模式：角落是背景色，中心是图片。
                #expect(cornerRed < 0.9)
                #expect(centerRed > 0.9)
            } else {
                // 智能（小图）/适应/平铺都会覆盖角落。
                #expect(cornerRed > 0.9)
            }
        }
    }
}
