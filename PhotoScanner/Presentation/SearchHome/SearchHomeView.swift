import SwiftUI
import PhotosUI

/// 搜索首页 - 搜索引擎风格
struct SearchHomeView: View {
    @State private var searchText: String = ""
    @State private var showTextSearch: Bool = false
    @State private var showImageSearch: Bool = false
    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var searchHistory: [String] = []
    @State private var showClearHistoryAlert: Bool = false
    @Namespace private var searchTransition
    
    // 高频搜索建议
    private let searchSuggestions: [String] = ["海边日落", "宠物", "笑容"]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()
                
                // Logo + 标题
                VStack(spacing: 12) {
                    Image(systemName: "photo.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("PhotoScanner")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                
                // 统一搜索框
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        
                        TextField("输入描述搜索图片...", text: $searchText)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                                    saveSearchAndNavigate()
                                }
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .matchedGeometryEffect(id: "searchBar", in: searchTransition)
                    
                    // 图片搜索按钮
                    PhotosPicker(selection: $selectedPickerItem, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 20)
                
                // 搜索建议和历史
                VStack(alignment: .leading, spacing: 12) {
                    // 高频搜索建议
                    VStack(alignment: .leading, spacing: 8) {
                        Text("推荐搜索")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            ForEach(searchSuggestions, id: \.self) { suggestion in
                                Button(action: {
                                    searchText = suggestion
                                    saveSearchAndNavigate()
                                }) {
                                    Text(suggestion)
                                        .font(.subheadline)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundStyle(.blue)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    
                    // 搜索历史
                    if !searchHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
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
                                        saveSearchAndNavigate()
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
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .navigationDestination(isPresented: $showTextSearch) {
                TextSearchResultsView(initialQuery: searchText, namespace: searchTransition)
            }
            .navigationDestination(isPresented: $showImageSearch) {
                ImageSearchView()
            }
            .onChange(of: selectedPickerItem) { _, newItem in
                if newItem != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showImageSearch = true
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
    
    // MARK: - Helper Methods
    
    private func loadSearchHistory() async {
        searchHistory = await SearchHistoryManager.shared.getHistory()
    }
    
    private func saveSearchAndNavigate() {
        Task {
            await SearchHistoryManager.shared.addHistory(searchText)
            await loadSearchHistory()
            
            withAnimation(.easeInOut(duration: 0.3)) {
                showTextSearch = true
            }
        }
    }
    
    private func clearSearchHistory() async {
        await SearchHistoryManager.shared.clearHistory()
        searchHistory = []
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

#Preview {
    SearchHomeView()
}
