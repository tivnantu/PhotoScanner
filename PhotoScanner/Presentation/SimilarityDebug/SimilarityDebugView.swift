import SwiftUI
import PhotosUI

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

    @ViewBuilder
    private var imageSection: some View {
        let preview = viewModel?.selectedImagePreview

        Section("图片") {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                if let preview {
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
