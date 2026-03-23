//
// ContentView.swift
// PhotoScanner
//
// 应用首页。
// 文搜图和以图搜图作为核心功能入口。
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TextSearchView()
                .tabItem {
                    Label("文搜图", systemImage: "text.magnifyingglass")
                }

            ImageSearchView()
                .tabItem {
                    Label("以图搜图", systemImage: "photo.fill")
                }
        }
    }
}

#Preview {
    ContentView()
}
