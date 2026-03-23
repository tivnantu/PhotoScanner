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
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: viewModel.statusSystemImage)
                    .font(.title3)
                    .foregroundStyle(statusTint(for: viewModel.buildState))
                    .frame(width: 24)

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

                    if let actionTitle = viewModel.statusActionTitle {
                        Button(actionTitle) {
                            Task {
                                await viewModel.rebuildIndexFromImportedAssets()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
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

            if viewModel.canRebuildFromImportedAssets {
                Button {
                    Task {
                        await viewModel.rebuildIndexFromImportedAssets()
                    }
                } label: {
                    Label("使用已导入图片重新建索引", systemImage: "arrow.clockwise")
                }
            }

            Button(role: .destructive) {
                Task {
                    await viewModel.clearIndex()
                }
            } label: {
                Label("清空本地索引与导入图片", systemImage: "trash")
            }
            .disabled(viewModel.isBuilding || viewModel.indexedCount == 0)

            Text(viewModel.importSourceHintText)
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

            Text(viewModel.searchHintText)
                .font(.footnote)
                .foregroundStyle(.secondary)

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
                    Text(viewModel.searchButtonTitle)
                    Spacer()
                }
            }
            .disabled(!viewModel.canSearch)
        }
    }

    @ViewBuilder
    private func resultsSection(_ viewModel: TextImageSearchViewModel) -> some View {
        Section("结果") {
            if let feedback = viewModel.resultsFeedback {
                feedbackCard(feedback) {
                    guard feedback.actionTitle != nil else { return }
                    Task {
                        await viewModel.retrySearch()
                    }
                }
            } else {
                if let summary = viewModel.resultsSummaryText {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.searchResults) { result in
                    HStack(spacing: 12) {
                        preview(result.previewData)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.displayTitle)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text("\(result.sourceLabel) · 相似度：\(String(format: "%.4f", result.score))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func feedbackCard(_ feedback: TextImageFeedback, action: @escaping () -> Void) -> some View {
        let tint = feedbackTint(for: feedback.tone)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: feedback.systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 6) {
                    Text(feedback.title)
                        .font(.headline)
                    Text(feedback.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let actionTitle = feedback.actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            }
        }
        .padding(.vertical, 4)
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
            var inputs: [IndexedAssetInput] = []
            inputs.reserveCapacity(items.count)

            for item in items {
                if let data = try await item.loadTransferable(type: Data.self) {
                    inputs.append(
                        try IndexedAssetInput(
                            assetLocalIdentifier: item.itemIdentifier,
                            imageData: data
                        )
                    )
                }
            }

            if inputs.isEmpty {
                await viewModel.presentImportFailure(PSError.invalidInput("未读取到可用图片，请重新选择"))
                return
            }

            await viewModel.handlePickedAssets(inputs)
        } catch {
            await viewModel.presentImportFailure(error)
        }
    }

    private func statusTint(for buildState: IndexBuildState) -> Color {
        switch buildState {
        case .idle:
            return .secondary
        case .preparing, .building:
            return .accentColor
        case .ready:
            return .green
        case .failed:
            return .orange
        }
    }

    private func feedbackTint(for tone: TextImageFeedbackTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .info:
            return .accentColor
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
