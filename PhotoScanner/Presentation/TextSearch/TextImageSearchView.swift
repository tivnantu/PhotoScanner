import SwiftUI
import PhotosUI
import UIKit

struct TextImageSearchView: View {
    @Environment(\.services) private var services
    @State private var viewModel: TextImageSearchViewModel?
    @State private var pickerItems: [PhotosPickerItem] = []
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    List {
                        statusSection(viewModel)
                        importSection(viewModel)
                        searchSection(viewModel)
                        resultsSection(viewModel)
                    }
                    .listStyle(.insetGrouped)
                } else {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("文搜图")
            .task {
                guard viewModel == nil else { return }
                let nextViewModel = TextImageSearchViewModel(services: services)
                viewModel = nextViewModel
                await nextViewModel.initialize()
            }
        }
    }

    @ViewBuilder
    private func statusSection(_ viewModel: TextImageSearchViewModel) -> some View {
        Section("索引状态") {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.statusTitle)
                    .font(.headline)
                Text(viewModel.statusDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if case .building(let progress) = viewModel.buildState {
                    ProgressView(value: progress.fractionCompleted)
                    Text(String(format: "%.0f%%", progress.fractionCompleted * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label("当前已导入 \(viewModel.indexedCount) 张图片", systemImage: "photo.stack")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func importSection(_ viewModel: TextImageSearchViewModel) -> some View {
        Section("建立索引") {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 30,
                matching: .images
            ) {
                Label("选择图片并重建索引", systemImage: "photo.on.rectangle.angled")
            }
            .disabled(viewModel.isBuilding)
            .onChange(of: pickerItems) { _, newItems in
                Task {
                    await importSelectedItems(newItems, into: viewModel)
                    pickerItems = []
                }
            }

            Button(role: .destructive) {
                Task {
                    await viewModel.clearIndex()
                }
            } label: {
                Label("清空本地索引与导入图片", systemImage: "trash")
            }
            .disabled(viewModel.isBuilding && viewModel.indexedCount == 0)

            Text("当前最小闭环会把你选中的图片保存到本地索引目录，后续搜索直接读取图片向量，不会重新编码已索引图片。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func searchSection(_ viewModel: TextImageSearchViewModel) -> some View {
        Section("搜索") {
            TextField("输入描述文本，例如：海边日落、红色灯笼", text: Binding(
                get: { viewModel.queryText },
                set: { viewModel.queryText = $0 }
            ))
            .focused($isTextFieldFocused)
            .submitLabel(.search)
            .onSubmit {
                guard viewModel.canSearch else { return }
                isTextFieldFocused = false
                Task {
                    await viewModel.performSearch()
                }
            }

            Button {
                isTextFieldFocused = false
                Task {
                    await viewModel.performSearch()
                }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isSearching {
                        ProgressView()
                            .padding(.trailing, 8)
                    }
                    Text(viewModel.isSearching ? "搜索中..." : "开始搜索")
                    Spacer()
                }
            }
            .disabled(!viewModel.canSearch)
        }
    }

    @ViewBuilder
    private func resultsSection(_ viewModel: TextImageSearchViewModel) -> some View {
        Section("结果") {
            if viewModel.isSearching {
                HStack {
                    Spacer()
                    ProgressView("正在检索...")
                    Spacer()
                }
            } else if let message = viewModel.searchMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if viewModel.searchResults.isEmpty {
                Text("建立索引后，输入一段文本开始搜索。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.searchResults) { result in
                    HStack(spacing: 12) {
                        preview(result.previewData)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.assetLocalIdentifier)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text("相似度：\(String(format: "%.4f", result.score))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func preview(_ data: Data?) -> some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func importSelectedItems(
        _ items: [PhotosPickerItem],
        into viewModel: TextImageSearchViewModel
    ) async {
        guard !items.isEmpty else { return }

        do {
            var images: [Data] = []
            images.reserveCapacity(items.count)

            for item in items {
                if let data = try await item.loadTransferable(type: Data.self) {
                    images.append(data)
                }
            }

            await viewModel.handlePickedImages(images)
        } catch {
            await MainActor.run {
                viewModel.buildState = .failed(message: error.localizedDescription)
            }
        }
    }
}
