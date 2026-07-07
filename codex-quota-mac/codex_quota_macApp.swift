//
//  codex_quota_macApp.swift
//  codex-quota-mac
//
//  Created by 鲍小帅 on 2026/7/6.
//

import SwiftUI

@main
struct codex_quota_macApp: App {
    // 原生 AppDelegate，用于管理状态栏、主窗口和额度刷新生命周期。
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
