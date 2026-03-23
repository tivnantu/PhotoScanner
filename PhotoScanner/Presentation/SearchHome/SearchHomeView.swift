import SwiftUI
import PhotosUI

/// 搜索首页 - 搜索引擎风格
struct SearchHomeView: View {
    @State private var searchText: String = ""
    @State private var showTextSearch: Bool = false
    @State private var showImageSearch: Bool = false
    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var recentSearches: [String] = ["风景", "人物", "建筑", "美食", "旅行", "宠物"]
    
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
                                    showTextSearch = true
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
                
                // 搜索历史
                VStack(alignment: .leading, spacing: 12) {
                    Text("搜索历史")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(recentSearches, id: \.self) { search in
                            Button(action: {
                                searchText = search
                                showTextSearch = true
                            }) {
                                Text(search)
                                    .font(.subheadline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .navigationDestination(isPresented: $showTextSearch) {
                TextSearchView(initialQuery: searchText)
            }
            .navigationDestination(isPresented: $showImageSearch) {
                ImageSearchView()
            }
            .onChange(of: selectedPickerItem) { _, newItem in
                if newItem != nil {
                    showImageSearch = true
                }
            }
        }
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
