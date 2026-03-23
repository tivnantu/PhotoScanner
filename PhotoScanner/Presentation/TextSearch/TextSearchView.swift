import SwiftUI
import Photos
import PhotosUI
import UIKit
import OSLog

struct TextSearchView: View {
    @Environment(\.services) private var services
    @State private var viewModel: TextSearchViewModel?
    @State private var pickerItems: [PhotosPickerItem] = []
    @FocusState private var isTextFieldFocused: Bool
    
    var initialQuery: String = ""
    
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
                let nextViewModel = TextSearchViewModel(services: services)
                viewModel = nextViewModel
                await nextViewModel.initialize()
                
                // 设置初始查询
                if !initialQuery.isEmpty {
                    nextViewModel.queryText = initialQuery
                }
            }
        }
    }

    @ViewBuilder
    private func statusSection(_ viewModel: TextSearchViewModel) -> some View {
        Section {
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
    private func importSection(_ viewModel: TextSearchViewModel) -> some View {
        Section("图片管理") {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: nil,
                matching: .images,
                preferredItemEncoding: .automatic,
                photoLibrary: .shared()
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
                Label("清空所有数据", systemImage: "trash")
            }
            .disabled(viewModel.isBuilding || viewModel.indexedCount == 0)

            Text(viewModel.importSourceHintText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func searchSection(_ viewModel: TextSearchViewModel) -> some View {
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
    private func performanceSection(_ viewModel: TextSearchViewModel) -> some View {
        Section("运行观测") {
            if viewModel.performanceMetrics.isEmpty {
                Text("完成一次索引恢复、构建或搜索后，这里会显示最近一次关键链路耗时。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.performanceMetrics) { metric in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(metric.title)
                                .font(.subheadline)
                            Spacer()
                            Text(metric.durationText)
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Text(metric.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text("记录于 \(metric.recordedAtText)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Text(viewModel.performanceHintText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func resultsSection(_ viewModel: TextSearchViewModel) -> some View {
        Section("搜索结果") {
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
                            HStack(spacing: 8) {
                                Text(result.sourceLabel)
                                Text("匹配度 \(String(format: "%.0f%%", result.score * 100))")
                                    .fontWeight(.medium)
                            }
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
        into viewModel: TextSearchViewModel
    ) async {
        guard !items.isEmpty else { return }

        do {
            var inputs: [IndexedAssetInput] = []
            inputs.reserveCapacity(items.count)

            for (index, item) in items.enumerated() {
                let normalizedIdentifier = item.itemIdentifier?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let shortIdentifier = shortIdentifier(normalizedIdentifier)

                if let data = try await item.loadTransferable(type: Data.self) {
                    inputs.append(
                        try IndexedAssetInput(
                            assetLocalIdentifier: normalizedIdentifier,
                            imageData: data
                        )
                    )
                } else {
                    Logger.ui.error("选图[\(index + 1)/\(items.count)] 数据读取失败，itemIdentifier: \(shortIdentifier)")
                }
            }

            if inputs.isEmpty {
                await viewModel.presentImportFailure(PSError.invalidInput("未读取到可用图片，请重新选择"))
                return
            }

            await viewModel.handlePickedAssets(inputs)
        } catch {
            Logger.ui.error("文搜图导入失败: \(error.localizedDescription)")
            await viewModel.presentImportFailure(error)
        }
    }

    private func shortIdentifier(_ identifier: String?) -> String {
        guard let identifier, !identifier.isEmpty else { return "nil" }
        return String(identifier.prefix(24))
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
