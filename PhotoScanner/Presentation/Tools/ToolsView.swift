import SwiftUI

/// 工具页
struct ToolsView: View {
    @Environment(\.services) private var services
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 功能卡片网格
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        NavigationLink(destination: TextImageSimilarityView(services: services)) {
                            ToolCard(
                                title: "图文相似度",
                                subtitle: "照片与文字匹配度",
                                icon: "doc.text.image",
                                gradient: Gradient(colors: [
                                    Color(red: 88/255, green: 166/255, blue: 255/255),
                                    Color(red: 126/255, green: 182/255, blue: 255/255)
                                ])
                            )
                        }
                        .buttonStyle(.plain)
                        
                        NavigationLink(destination: ImageImageSimilarityView(services: services)) {
                            ToolCard(
                                title: "图图相似度",
                                subtitle: "两张照片对比",
                                icon: "photo.on.rectangle",
                                gradient: Gradient(colors: [
                                    Color(red: 255/255, green: 149/255, blue: 0/255),
                                    Color(red: 255/255, green: 179/255, blue: 64/255)
                                ])
                            )
                        }
                        .buttonStyle(.plain)
                        
                        NavigationLink(destination: SimilarityClusteringView(services: services)) {
                            ToolCard(
                                title: "相似聚类",
                                subtitle: "自动发现相似图片簇",
                                icon: "square.grid.3x3.fill",
                                gradient: Gradient(colors: [
                                    Color(red: 175/255, green: 82/255, blue: 222/255),
                                    Color(red: 191/255, green: 114/255, blue: 234/255)
                                ])
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                    // 即将推出
                    VStack(alignment: .leading, spacing: 12) {
                        Text("即将推出")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                        
                        VStack(spacing: 0) {
                            ComingSoonRow(
                                title: "人脸分组",
                                subtitle: "按人物自动分组",
                                icon: "person.2.fill"
                            )
                            
                            Divider()
                                .padding(.leading, 44)
                            
                            ComingSoonRow(
                                title: "地点相册",
                                subtitle: "按拍摄地点组织",
                                icon: "location.fill"
                            )
                        }
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("工具")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Tool Card

struct ToolCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: Gradient
    var action: (() -> Void)? = nil
    
    var body: some View {
        if let action = action {
            Button(action: action) {
                cardContent
            }
            .buttonStyle(.plain)
        } else {
            cardContent
        }
    }
    
    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 图标
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(
                        gradient: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Spacer()
            
            // 标题和副标题
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 110)
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Coming Soon Row

struct ComingSoonRow: View {
    let title: String
    let subtitle: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
            
            // 文字
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // 即将推出标签
            Text("即将推出")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))
                .foregroundStyle(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    ToolsView()
}
