import SwiftUI

/// 工具页 - 卡片网格布局
struct ToolsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 第一行：两个卡片
                    HStack(spacing: 16) {
                        ToolCard(
                            title: "文图相似度",
                            icon: "text.below.photo",
                            gradient: Gradient(colors: [
                                Color(red: 155/255, green: 142/255, blue: 212/255),
                                Color(red: 180/255, green: 158/255, blue: 217/255)
                            ])
                        ) {
                            // TODO: 导航到文图相似度页面
                        }
                        
                        ToolCard(
                            title: "图图相似度",
                            icon: "photo.on.rectangle",
                            gradient: Gradient(colors: [
                                Color(red: 212/255, green: 165/255, blue: 176/255),
                                Color(red: 201/255, green: 160/255, blue: 176/255)
                            ])
                        ) {
                            // TODO: 导航到图图相似度页面
                        }
                    }
                    
                    // 第二行：一个跨列卡片
                    ToolCard(
                        title: "相似图片聚类",
                        icon: "square.grid.3x3.fill",
                        gradient: Gradient(colors: [
                            Color(red: 138/255, green: 180/255, blue: 217/255),
                            Color(red: 160/255, green: 196/255, blue: 227/255)
                        ])
                    ) {
                        // TODO: 导航到相似图片聚类页面
                    }
                }
                .padding()
            }
            .navigationTitle("工具")
        }
    }
}

// MARK: - Tool Card

struct ToolCard: View {
    let title: String
    let icon: String
    let gradient: Gradient
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
                
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .background(
                LinearGradient(
                    gradient: gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
    }
}

#Preview {
    ToolsView()
}
