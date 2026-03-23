import SwiftUI

// MARK: - ShimmerView

/// 通用骨架 Shimmer，占位加载时使用。
///
/// ## 设计背景
/// 列表加载时显示骨架屏，提升用户体验感知速度。
///
/// ## 使用示例
/// ```swift
/// if isLoading {
///     ShimmerView(height: 80)
/// } else {
///     ResultRow(result)
/// }
/// ```
struct ShimmerView: View {

    /// 圆角半径
    var cornerRadius: CGFloat = 12
    
    /// 固定高度（可选）
    var height: CGFloat? = nil

    /// 动画相位
    @State private var phase: CGFloat = -1

    var body: some View {
        Rectangle()
            .fill(.gray.opacity(0.25))
            .overlay {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    LinearGradient(
                        colors: [
                            .gray.opacity(0.15),
                            .gray.opacity(0.4),
                            .gray.opacity(0.15)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 1.5)
                    .offset(x: width * phase)
                    .animation(
                        .smooth(duration: 1.5)
                            .repeatForever(autoreverses: false),
                        value: phase
                    )
                }
                .clipped()
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .onAppear {
                phase = 1
            }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ShimmerView") {
    VStack(spacing: 16) {
        ShimmerView(height: 80)
        ShimmerView(height: 120)
        ShimmerView(cornerRadius: 24, height: 60)
    }
    .padding()
}
#endif
