//
// SimilarityDebugView.swift
// PhotoScanner
//
// 底模接入验证页。
// 功能：选 1 张图 → 输入 1 条文本 → 计算相似度 → 展示结果。
// 定位：不是最终产品页，是 Plugin / Engine 边界的验证台。
//

import SwiftUI
import PhotosUI

// MARK: - SimilarityDebugView

struct SimilarityDebugView: View {

    @Environment(\.services) private var services
    @State private var viewModel: SimilarityDebugViewModel?
    @State private var pickerItem: PhotosPickerItem?
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                imageSection
                textSection
                actionSection
                resultSection
            }
            .navigationTitle("相似度验证")
            .task {
                let vm = SimilarityDebugViewModel(services: services)
                viewModel = vm
                await vm.initializeModelIfNeeded()
            }
        }
    }

    // MARK: - 图片选择区

    @ViewBuilder
    private var imageSection: some View {
        Section("图片") {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                if let preview = viewModel?.selectedImagePreview {
                    preview
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Label("选择一张照片", systemImage: "photo")
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                Task {
                    await viewModel?.handlePickedPhoto(newItem)
                }
            }
        }
    }

    // MARK: - 文本输入区

    @ViewBuilder
    private var textSection: some View {
        Section("文本") {
            TextField("输入描述文本", text: Binding(
                get: { viewModel?.inputText ?? "" },
                set: { viewModel?.inputText = $0 }
            ))
            .focused($isTextFieldFocused)
            .submitLabel(.done)
            .onSubmit {
                isTextFieldFocused = false
            }
        }
    }

    // MARK: - 操作区

    @ViewBuilder
    private var actionSection: some View {
        Section {
            Button {
                isTextFieldFocused = false
                Task {
                    await viewModel?.computeSimilarity()
                }
            } label: {
                HStack {
                    Spacer()
                    if viewModel?.state == .computing {
                        ProgressView()
                            .padding(.trailing, 8)
                    }
                    Text(buttonTitle)
                    Spacer()
                }
            }
            .disabled(!(viewModel?.canCompute ?? false))
        }
    }

    private var buttonTitle: String {
        switch viewModel?.state {
        case .loadingModel: return "模型加载中..."
        case .computing: return "计算中..."
        default: return "计算相似度"
        }
    }

    // MARK: - 结果区

    @ViewBuilder
    private var resultSection: some View {
        switch viewModel?.state {
        case .success(let score):
            Section("结果") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("相似度分数")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.4f", score))
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.bold)
                }
            }
        case .failure(let message):
            Section("错误") {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        default:
            EmptyView()
        }
    }
}
