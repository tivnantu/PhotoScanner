import SwiftUI
import PhotosUI

struct ImageSearchView: View {
    @Environment(\.services) private var services
    @State private var viewModel: ImageSearchViewModel?
    @State private var selectedPickerItem: PhotosPickerItem?
    
    var body: some View {
        Group {
            if let viewModel {
                contentView(viewModel)
            } else {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("以图搜图")
        .task {
            guard viewModel == nil else { return }
            let nextViewModel = ImageSearchViewModel(services: services)
            viewModel = nextViewModel
            await nextViewModel.initialize()
        }
        .onChange(of: selectedPickerItem) { _, newItem in
            if let newItem, let viewModel {
                Task {
                    // 尝试使用 assetId
                    if let assetId = newItem.itemIdentifier {
                        await viewModel.selectImage(assetId: assetId)
                    } else {
                        // 回退到原图数据
                        if let data = try? await newItem.loadTransferable(type: Data.self) {
                            await viewModel.searchWithImageData(data)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func contentView(_ viewModel: ImageSearchViewModel) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // 用户友好描述
                descriptionSection()
                
                // 图片选择区
                imagePickerSection(viewModel)
                
                // 状态区
                statusSection(viewModel)
                
                // 搜索结果
                resultsSection(viewModel)
            }
            .padding()
        }
    }
}

// MARK: - Description Section

extension ImageSearchView {
    @ViewBuilder
    private func descriptionSection() -> some View {
        VStack(spacing: 8) {
            Text("选择一张图片，我会告诉你")
                .font(.headline)
            
            Text("图库中有哪些相似的图片")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Image Picker Section

extension ImageSearchView {
    @ViewBuilder
    private func imagePickerSection(_ viewModel: ImageSearchViewModel) -> some View {
        PhotosPicker(selection: $selectedPickerItem, matching: .images) {
            ZStack {
                if let previewImage = viewModel.selectedPreviewImage {
                    // 已选择图片
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // 未选择图片
                    placeholderView()
                }
            }
        }
    }
    
    @ViewBuilder
    private func placeholderView() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("点击选择图片")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Status Section

extension ImageSearchView {
    @ViewBuilder
    private func statusSection(_ viewModel: ImageSearchViewModel) -> some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
            
        case .selectingImage:
            HStack {
                ProgressView()
                Text("选择图片中...")
            }
            
        case .embedding:
            HStack {
                ProgressView()
                Text("分析图片中...")
            }
            
        case .searching:
            HStack {
                ProgressView()
                Text("搜索相似图片...")
            }
            
        case .displaying(let results):
            Text("找到 \(results.count) 张相似图片")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
        case .error(let error):
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(error.localizedDescription)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Results Section

extension ImageSearchView {
    @ViewBuilder
    private func resultsSection(_ viewModel: ImageSearchViewModel) -> some View {
        if case .displaying(let results) = viewModel.state {
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 4
            ) {
                ForEach(results) { result in
                    ResultCell(result: result)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: results)
        }
    }
}

// MARK: - Result Cell

struct ResultCell: View {
    let result: ImageSearchResult
    
    var body: some View {
        VStack(spacing: 4) {
            Image(uiImage: result.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Text(String(format: "%.0f%%", result.similarity * 100))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(similarityColor)
        }
    }
    
    private var similarityColor: Color {
        if result.similarity >= 0.9 {
            return .green
        } else if result.similarity >= 0.8 {
            return .blue
        } else {
            return .secondary
        }
    }
}
