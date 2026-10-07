//
//  LaunchPage.swift
//  PCL.Mac XE
//
//  Created by AnemoFlower on 2025/11/9.
//

import SwiftUI
import Core

struct LaunchPage: View {
    var body: some View {
        switch LauncherConfig.shared.homepageType {
        case .empty: Spacer()
        case .demo: DemoHomepageView()
        }
    }
}
