import SwiftUI

/// 简化版文搜图结果页 - 只展示搜索结果
struct TextSearchResultsView: View {
    @Environment(\.services) private var services
    @State private var viewModel: TextSearchViewModel?
    @State private var queryText: String = ""
    @FocusState private var isSearchFieldFocused: Bool
    
    let initialQuery: String
    
    var body: some View {
        Group {
            if let viewModel {
                contentView(viewModel)
            } else {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("搜索结果")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel == nil else { return }
            let nextViewModel = TextSearchViewModel(services: services)
            viewModel = nextViewModel
            await nextViewModel.initialize()
            
            // 设置初始查询并立即搜索
            queryText = initialQuery
            nextViewModel.queryText = initialQuery
            
            // 保存搜索历史
            Task {
                await SearchHistoryManager.shared.addHistory(initialQuery)
            }
            
            await nextViewModel.performSearch()
        }
    }
    
    @ViewBuilder
    private func contentView(_ viewModel: TextSearchViewModel) -> some View {
        VStack(spacing: 0) {
            // 搜索框
            searchBar(viewModel)
            
            // 内容区域
            if viewModel.isSearching {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text("正在搜索...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let failure = viewModel.searchFailure {
                errorView(failure, viewModel)
            } else if viewModel.searchResults.isEmpty && viewModel.hasAttemptedSearch {
                emptyView()
            } else if !viewModel.searchResults.isEmpty {
                resultsView(viewModel)
            } else {
                // 初始加载态
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text("准备搜索...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Search Bar
    
    @ViewBuilder
    private func searchBar(_ viewModel: TextSearchViewModel) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("输入描述搜索图片...", text: $queryText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        if !queryText.trimmingCharacters(in: .whitespaces).isEmpty {
                            viewModel.queryText = queryText
                            Task {
                                await SearchHistoryManager.shared.addHistory(queryText)
                                await viewModel.performSearch()
                            }
                        }
                    }
                
                if !queryText.isEmpty {
                    Button(action: { queryText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Button("取消") {
                queryText = ""
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - Results View
    
    @ViewBuilder
    private func resultsView(_ viewModel: TextSearchViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // 结果数量
                HStack {
                    Text("找到 \(viewModel.searchResults.count) 张相似图片")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // 结果网格
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 4
                ) {
                    ForEach(viewModel.searchResults) { result in
                        TextSearchResultCell(result: result)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Empty View
    
    @ViewBuilder
    private func emptyView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("暂无搜索结果")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("请尝试其他关键词")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error View
    
    @ViewBuilder
    private func errorView(_ failure: TextImageFeedback, _ viewModel: TextSearchViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            
            Text(failure.title)
                .font(.headline)
            
            Text(failure.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            if let actionTitle = failure.actionTitle {
                Button(actionTitle) {
                    Task {
                        await viewModel.performSearch()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Result Cell

struct TextSearchResultCell: View {
    let result: TextSearchResultItem
    
    var body: some View {
        VStack(spacing: 4) {
            if let previewData = result.previewData,
               let uiImage = UIImage(data: previewData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
            
            Text(String(format: "%.0f%%", result.score * 100))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(scoreColor)
        }
    }
    
    private var scoreColor: Color {
        if result.score >= 0.8 {
            return .green
        } else if result.score >= 0.6 {
            return .blue
        } else {
            return .secondary
        }
    }
}

#Preview {
    NavigationStack {
        TextSearchResultsView(initialQuery: "风景")
    }
}
