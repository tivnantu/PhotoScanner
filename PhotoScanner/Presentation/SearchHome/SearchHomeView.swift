import SwiftUI
import PhotosUI

/// 搜索首页 - 参考UI重新设计
struct SearchHomeView: View {
    @Environment(\.services) private var services
    @State private var searchText: String = ""
    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var searchHistory: [SearchHistoryItem] = []
    @State private var showClearHistoryAlert: Bool = false
    
    // 搜索状态
    @State private var isSearching: Bool = false
    @State private var searchResults: [TextSearchResultItem] = []
    @State private var imageSearchResults: [ImageSearchResult] = []
    @State private var searchFailure: String?
    @State private var searchMode: SearchMode = .none
    
    // 图片预览
    @State private var selectedImage: UIImage?
    @State private var showImagePreview: Bool = false
    
    // 搜索建议
    private let searchSuggestions: [String] = ["海边日落", "猫咪", "美食", "旅行"]
    
    enum SearchMode {
        case none
        case text
        case image
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 内容区域
                if searchMode == .none {
                    initialContent
                } else {
                    searchResultsView
                }
                
                Spacer()
            }
            .ignoresSafeArea(.keyboard)
            .fullScreenCover(isPresented: $showImagePreview) {
                if let image = selectedImage {
                    ImageViewer(image: image, isPresented: $showImagePreview)
                }
            }
            .onChange(of: searchText) { oldValue, newValue in
                if newValue.isEmpty && searchMode == .text {
                    resetSearch()
                }
            }
            .onChange(of: selectedPickerItem) { _, newItem in
                if let newItem = newItem {
                    Task {
                        await performImageSearch(newItem)
                    }
                }
            }
            .task {
                await loadSearchHistory()
            }
            .alert("清除搜索历史", isPresented: $showClearHistoryAlert) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) {
                    Task {
                        await clearSearchHistory()
                    }
                }
            } message: {
                Text("确定要清除所有搜索历史吗？")
            }
        }
    }
    
    // MARK: - Initial Content
    
    @ViewBuilder
    private var initialContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Logo区域
                VStack(spacing: 16) {
                    // 图标
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "photo.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.blue)
                    }
                    
                    // 应用名
                    Text("PhotoScanner")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    // 主标题
                    Text("找到你的每一张照片")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // 副标题
                    Text("文字搜索 · 以图搜图 · 本地隐私")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 60)
                .padding(.bottom, 40)
                
                // 搜索框
                searchBar
                    .padding(.bottom, 24)
                
                // 搜索建议
                if searchMode == .none {
                    searchSuggestionsView
                        .padding(.bottom, 32)
                    
                    // 搜索历史
                    if !searchHistory.isEmpty {
                        historySection
                    }
                }
            }
        }
    }
    
    // MARK: - Search Bar
    
    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 17))
                
                TextField("搜索照片...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                            Task {
                                await performTextSearch()
                            }
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            // 图片搜索按钮
            PhotosPicker(selection: $selectedPickerItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
            }
            .disabled(searchMode != .none)
            .padding(.trailing, 12)
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }
    
    // MARK: - Search Suggestions
    
    @ViewBuilder
    private var searchSuggestionsView: some View {
        HStack(spacing: 12) {
            ForEach(searchSuggestions, id: \.self) { suggestion in
                Button(action: {
                    searchText = suggestion
                    Task {
                        await performTextSearch()
                    }
                }) {
                    Text(suggestion)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - History Section
    
    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("搜索历史")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if !searchHistory.isEmpty {
                    Button("清除") {
                        showClearHistoryAlert = true
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            
            if !searchHistory.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(searchHistory.enumerated()), id: \.element.id) { index, item in
                        historyRow(item: item, isLast: index == searchHistory.count - 1)
                    }
                }
                .background(Color(.systemGray6).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private func historyRow(item: SearchHistoryItem, isLast: Bool) -> some View {
        Button(action: {
            searchText = item.query
            Task {
                await performTextSearch()
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                
                Text(item.query)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(item.resultCount)张")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isLast ? Color.clear : Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color(.systemGray5).opacity(0.5))
                .frame(height: 0.5)
                .padding(.leading, 36)
            , alignment: .bottom
        )
    }
    
    // MARK: - Search Results View
    
    @ViewBuilder
    private var searchResultsView: some View {
        VStack(spacing: 0) {
            // 顶部搜索栏
            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        resetSearch()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 17))
                    
                    TextField("搜索照片...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                                Task {
                                    await performTextSearch()
                                }
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // 结果列表
            ScrollView {
                if isSearching {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        
                        Text("搜索中...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else if let failure = searchFailure {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(.orange)
                        
                        Text(failure)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else if searchMode == .text && !searchResults.isEmpty {
                    textResultsGrid
                } else if searchMode == .image && !imageSearchResults.isEmpty {
                    imageResultsGrid
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        
                        Text("暂无搜索结果")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                }
            }
        }
    }
    
    @ViewBuilder
    private var textResultsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 4
        ) {
            ForEach(searchResults) { result in
                Button(action: {
                    if let data = result.previewData, let image = UIImage(data: data) {
                        selectedImage = image
                        showImagePreview = true
                    }
                }) {
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
                            .foregroundStyle(scoreColor(for: result.score))
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }
    
    @ViewBuilder
    private var imageResultsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 4
        ) {
            ForEach(imageSearchResults) { result in
                Button(action: {
                    selectedImage = result.thumbnail
                    showImagePreview = true
                }) {
                    VStack(spacing: 4) {
                        Image(uiImage: result.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Text(String(format: "%.0f%%", result.similarity * 100))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(scoreColor(for: result.similarity))
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }
    
    // MARK: - Helper Methods
    
    private func scoreColor(for score: Float) -> Color {
        if score >= 0.8 {
            return .green
        } else if score >= 0.6 {
            return .blue
        } else {
            return .secondary
        }
    }
    
    private func loadSearchHistory() async {
        // 模拟加载历史
        searchHistory = [
            SearchHistoryItem(query: "猫咪", resultCount: 10, date: Date()),
            SearchHistoryItem(query: "海边日落", resultCount: 20, date: Date().addingTimeInterval(-86400)),
            SearchHistoryItem(query: "海边大桥", resultCount: 20, date: Date().addingTimeInterval(-86400))
        ]
    }
    
    private func clearSearchHistory() async {
        searchHistory = []
    }
    
    private func deleteHistoryItem(_ item: SearchHistoryItem) async {
        searchHistory.removeAll { $0.id == item.id }
    }
    
    private func performTextSearch() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            searchMode = .text
            isSearching = true
            searchFailure = nil
        }
        
        do {
            let viewModel = TextSearchViewModel(services: services)
            await viewModel.initialize()
            viewModel.queryText = searchText
            try await viewModel.performSearch()
            
            withAnimation(.easeInOut(duration: 0.3)) {
                searchResults = viewModel.searchResults
                isSearching = false
            }
        } catch {
            withAnimation(.easeInOut(duration: 0.3)) {
                searchFailure = error.localizedDescription
                isSearching = false
            }
        }
    }
    
    private func performImageSearch(_ item: PhotosPickerItem) async {
        withAnimation(.easeInOut(duration: 0.3)) {
            searchMode = .image
            isSearching = true
            searchFailure = nil
        }
        
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ImageSearchError.failedToLoadImage
            }
            
            let viewModel = ImageSearchViewModel(services: services)
            await viewModel.initialize()
            try await viewModel.searchWithImageData(data)
            
            if case .displaying(let results) = viewModel.state {
                withAnimation(.easeInOut(duration: 0.3)) {
                    imageSearchResults = results
                    isSearching = false
                }
            } else if case .error(let error) = viewModel.state {
                withAnimation(.easeInOut(duration: 0.3)) {
                    searchFailure = error.localizedDescription
                    isSearching = false
                }
            }
        } catch {
            withAnimation(.easeInOut(duration: 0.3)) {
                searchFailure = error.localizedDescription
                isSearching = false
            }
        }
    }
    
    private func resetSearch() {
        searchText = ""
        searchResults = []
        imageSearchResults = []
        searchFailure = nil
        searchMode = .none
        selectedPickerItem = nil
    }
}

// MARK: - Search History Item

struct SearchHistoryItem: Identifiable {
    let id = UUID()
    let query: String
    let resultCount: Int
    let date: Date
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Image Viewer

struct ImageViewer: View {
    let image: UIImage
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                HStack {
                    Spacer()
                    
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                    .padding()
                }
                
                Spacer()
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = value
                            }
                            .onEnded { _ in
                                withAnimation {
                                    scale = 1.0
                                }
                            }
                    )
                
                Spacer()
            }
        }
        .statusBar(hidden: true)
    }
}

#Preview {
    SearchHomeView()
}
