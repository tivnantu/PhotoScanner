//
// ContentView.swift
// PhotoScanner
//
// 应用首页。
// 当前阶段以最小文搜图为主入口，同时保留相似度验证页作为内部调试台。
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TextImageSearchView()
                .tabItem {
                    Label("文搜图", systemImage: "text.magnifyingglass")
                }

            SimilarityDebugView()
                .tabItem {
                    Label("验证台", systemImage: "waveform.path.ecg")
                }
        }
    }
}

#Preview {
    ContentView()
}
