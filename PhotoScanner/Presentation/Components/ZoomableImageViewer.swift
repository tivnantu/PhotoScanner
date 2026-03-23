import SwiftUI

// MARK: - ZoomableImageViewer

/// 可缩放的图片查看器
///
/// ## 功能
/// - 双指缩放（1x ~ 3x）
/// - 拖拽平移
/// - 双击切换缩放
/// - 下滑关闭
///
/// ## 设计参考
/// Apple Photos、Telegram 图片查看器
///
/// ## 使用示例
/// ```swift
/// .fullScreenCover(item: $selectedImage) { image in
///     ZoomableImageViewer(image: image)
/// }
/// ```
struct ZoomableImageViewer: View {

    @Environment(\.dismiss) private var dismiss

    /// 要显示的图片
    let image: UIImage

    // MARK: - State
    
    /// 基础缩放（双击后的固定值）
    @State private var baseScale: CGFloat = 1
    
    /// 当前缩放（手势进行中的增量）
    @State private var currentScale: CGFloat = 1
    
    /// 累计偏移
    @State private var offset: CGSize = .zero
    
    /// 手势增量偏移
    @State private var dragOffset: CGSize = .zero

    // MARK: - Constants

    /// 最大缩放倍数
    private let maxScale: CGFloat = 3
    
    /// 下滑关闭阈值（像素）
    private let dismissThreshold: CGFloat = 140

    // MARK: - Body

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .overlay(alignment: .center) {
                imageView
            }
            .overlay(alignment: .topLeading) {
                closeButton
            }
    }

    // MARK: - Subviews

    private var imageView: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(baseScale * currentScale)
            .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
            .gesture(gestures)
            .onTapGesture(count: 2) {
                handleDoubleTap()
            }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .foregroundStyle(.white)
                .shadow(radius: 4)
                .padding()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gestures

    private var gestures: some Gesture {
        SimultaneousGesture(
            magnificationGesture,
            dragGesture
        )
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                currentScale = value
            }
            .onEnded { value in
                let newScale = max(1, min(baseScale * value, maxScale))
                baseScale = newScale
                currentScale = 1
                // 缩放归位时重置偏移
                if baseScale == 1 {
                    offset = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let translation = value.translation
                // 下滑关闭（仅在未缩放时生效）
                if translation.height > dismissThreshold && baseScale <= 1.05 {
                    dismiss()
                    return
                }
                // 累加偏移
                offset.width += translation.width
                offset.height += translation.height
                withAnimation(.standard) {
                    dragOffset = .zero
                }
            }
    }

    // MARK: - Actions

    private func handleDoubleTap() {
        withAnimation(.standard) {
            if baseScale > 1.01 {
                // 已放大 → 缩小
                baseScale = 1
                offset = .zero
            } else {
                // 原始大小 → 放大到 2x
                baseScale = 2
            }
            currentScale = 1
        }
    }
}

// MARK: - Animation Extension

private extension Animation {
    /// 标准动画
    static var standard: Animation {
        .spring(duration: 0.3)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ZoomableImageViewer(image: UIImage(systemName: "photo")!)
}
#endif
