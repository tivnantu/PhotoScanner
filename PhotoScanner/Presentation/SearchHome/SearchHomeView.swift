import SwiftUI
import PhotosUI

/// 搜索首页 - 搜索引擎风格
struct SearchHomeView: View {
    @Environment(\.services) private var services
    @State private var searchText: String = ""
    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var searchHistory: [String] = []
    @State private var showClearHistoryAlert: Bool = false
    @State private var currentPlaceholderIndex: Int = 0
    
    // 搜索状态
    @State private var isSearching: Bool = false
    @State private var searchResults: [TextSearchResultItem] = []
    @State private var imageSearchResults: [ImageSearchResult] = []
    @State private var searchFailure: String?
    @State private var searchMode: SearchMode = .none
    
    // 图片预览
    @State private var selectedImage: UIImage?
    @State private var showImagePreview: Bool = false
    
    // placeholder 轮换列表
    private let placeholders: [String] = [
        "海边日落",
        "宠物",
        "笑容",
        "城市夜景",
        "美食",
        "旅行风景"
    ]
    
    enum SearchMode {
        case none
        case text
        case image
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Logo + 标题（搜索时隐藏）
                if searchMode == .none {
                    VStack(spacing: 12) {
                        rainbowLogo()
                        
                        Text("PhotoScanner")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    .padding(.top, 60)
                    .padding(.bottom, 40)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // 统一搜索框
                searchBar
                
                // 内容区域
                if searchMode != .none {
                    searchResultsView
                        .transition(.opacity)
                } else {
                    // 搜索历史
                    if !searchHistory.isEmpty {
                        historySection
                            .padding(.top, 24)
                            .transition(.opacity)
                    }
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
                startPlaceholderRotation()
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
    
    // MARK: - Logo with Rainbow Effect
    
    @ViewBuilder
    private func rainbowLogo() -> some View {
        TimelineView(.animation) { timeline in
            Image(systemName: "photo.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: rainbowColors(at: timeline.date),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse, options: .repeating, isActive: true)
        }
    }
    
    private func rainbowColors(at date: Date) -> [Color] {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.0) / 3.0
        
        return [
            Color(hue: phase, saturation: 0.5, brightness: 0.85),
            Color(hue: (phase + 0.17).truncatingRemainder(dividingBy: 1.0), saturation: 0.5, brightness: 0.85),
            Color(hue: (phase + 0.33).truncatingRemainder(dividingBy: 1.0), saturation: 0.5, brightness: 0.85),
            Color(hue: (phase + 0.5).truncatingRemainder(dividingBy: 1.0), saturation: 0.5, brightness: 0.85)
        ]
    }
    
    // MARK: - Search Bar
    
    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                ZStack(alignment: .leading) {
                    if searchText.isEmpty && searchMode == .none {
                        Text(placeholders[currentPlaceholderIndex])
                            .foregroundStyle(.tertiary)
                            .font(.body)
                            .transition(.opacity)
                            .id(currentPlaceholderIndex)
                    }
                    
                    TextField("", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                                Task {
                                    await performTextSearch()
                                }
                            }
                        }
                }
                
                if !searchText.isEmpty || searchMode != .none {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            resetSearch()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // 图片搜索按钮
            PhotosPicker(selection: $selectedPickerItem, matching: .images) {
                Image(systemName: "camera.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(searchMode != .none)
        }
        .padding(.horizontal, 20)
        .padding(.top, searchMode == .none ? 0 : 60)
    }
    
    // MARK: - History Section
    
    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("搜索历史")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button("清除") {
                    showClearHistoryAlert = true
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
            
            FlowLayout(spacing: 8) {
                ForEach(searchHistory, id: \.self) { query in
                    Button(action: {
                        searchText = query
                        Task {
                            await performTextSearch()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption2)
                            
                            Text(query)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Search Results View
    
    @ViewBuilder
    private var searchResultsView: some View {
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
        searchHistory = await SearchHistoryManager.shared.getHistory()
    }
    
    private func clearSearchHistory() async {
        await SearchHistoryManager.shared.clearHistory()
        searchHistory = []
    }
    
    private func startPlaceholderRotation() {
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentPlaceholderIndex = (currentPlaceholderIndex + 1) % placeholders.count
            }
        }
    }
    
    private func performTextSearch() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        await SearchHistoryManager.shared.addHistory(searchText)
        await loadSearchHistory()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            searchMode = .text
            isSearching = true
            searchFailure = nil
        }
        
        // TODO: 实际搜索逻辑
        // 模拟搜索延迟
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isSearching = false
        }
    }
    
    private func performImageSearch(_ item: PhotosPickerItem) async {
        withAnimation(.easeInOut(duration: 0.3)) {
            searchMode = .image
            isSearching = true
            searchFailure = nil
        }
        
        // TODO: 实际图片搜索逻辑
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isSearching = false
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

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height + spacing } - spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += item.dimensions(in: .unspecified).width + spacing
            }
            y += row.height + spacing
        }
    }
    
    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row(items: [], height: 0)
        var currentX: CGFloat = 0
        let maxWidth = proposal.width ?? 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && !currentRow.items.isEmpty {
                rows.append(currentRow)
                currentRow = Row(items: [], height: 0)
                currentX = 0
            }
            
            currentRow.items.append(subview)
            currentRow.height = max(currentRow.height, size.height)
            currentX += size.width + spacing
        }
        
        if !currentRow.items.isEmpty {
            rows.append(currentRow)
        }
        
        return rows
    }
    
    struct Row {
        var items: [LayoutSubview]
        var height: CGFloat
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
