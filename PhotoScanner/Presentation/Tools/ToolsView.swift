import SwiftUI

/// 工具页 - 借鉴 V1 DiscoverView 的两列网格布局
struct ToolsView: View {
    @Environment(\.services) private var services
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 探索工具 - 两列网格（V1 风格）
                    exploreToolsSection
                    
                    // 即将推出
                    comingSoonSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .navigationTitle("发现")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    // MARK: - 探索工具
    
    private var exploreToolsSection: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            alignment: .leading,
            spacing: 12
        ) {
            NavigationLink(destination: TextImageSimilarityView(services: services)) {
                ToolGridCard(
                    icon: "doc.text.magnifyingglass",
                    title: "图文相似度",
                    subtitle: "照片与文字匹配度"
                )
            }
            .buttonStyle(ToolCardButtonStyle())
            
            NavigationLink(destination: ImageImageSimilarityView(services: services)) {
                ToolGridCard(
                    icon: "square.on.square.badge.person.crop",
                    title: "图图相似度",
                    subtitle: "两张照片对比"
                )
            }
            .buttonStyle(ToolCardButtonStyle())
            
            NavigationLink(destination: SimilarityClusteringView(services: services)) {
                ToolGridCard(
                    icon: "rectangle.3.group",
                    title: "相似聚类",
                    subtitle: "自动发现相似图片簇"
                )
            }
            .buttonStyle(ToolCardButtonStyle())
            
            NavigationLink(destination: ImageSearchToolView(services: services)) {
                ToolGridCard(
                    icon: "photo.on.rectangle.angled",
                    title: "以图搜图",
                    subtitle: "选张照片找相似"
                )
            }
            .buttonStyle(ToolCardButtonStyle())
        }
    }
    
    // MARK: - 即将推出
    
    private var comingSoonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("即将推出")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                ToolGridCard(
                    icon: "person.crop.rectangle.stack",
                    title: "人脸分组",
                    subtitle: "自动识别人物",
                    isComingSoon: true
                )
                
                ToolGridCard(
                    icon: "map",
                    title: "地点相册",
                    subtitle: "按拍摄地点浏览",
                    isComingSoon: true
                )
            }
        }
    }
}

// MARK: - Tool Grid Card（V1 风格两列网格卡片）

struct ToolGridCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var isComingSoon: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标（左侧，带背景）
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isComingSoon ? .secondary : Color.accentColor)
                .frame(width: 40, height: 40)
                .background(
                    (isComingSoon ? Color.secondary : Color.accentColor)
                        .opacity(0.12)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            // 标题和副标题（右侧）
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isComingSoon ? .secondary : .primary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(isComingSoon ? .tertiary : .secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 卡片按压缩放 ButtonStyle（V1 风格）

struct ToolCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Image Search Tool View（简化版，作为以图搜图入口）

struct ImageSearchToolView: View {
    let services: AppServices
    
    var body: some View {
        TextImageSimilarityView(services: services)
            .navigationTitle("以图搜图")
    }
}

#Preview {
    ToolsView()
}
