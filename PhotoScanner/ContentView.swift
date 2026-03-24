//
// ContentView.swift
// PhotoScanner
//
// 应用首页。
// 三个主标签页：搜索、工具、设置。
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SearchHomeView()
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }

            ToolsView()
                .tabItem {
                    Label("发现", systemImage: "sparkles")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
        }
    }
}

#Preview {
    ContentView()
}
