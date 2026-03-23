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
                            gradient: Gradient(colors: [Color(hex: "667eea"), Color(hex: "764ba2")])
                        ) {
                            // TODO: 导航到文图相似度页面
                        }
                        
                        ToolCard(
                            title: "图图相似度",
                            icon: "photo.on.rectangle",
                            gradient: Gradient(colors: [Color(hex: "f093fb"), Color(hex: "f5576c")])
                        ) {
                            // TODO: 导航到图图相似度页面
                        }
                    }
                    
                    // 第二行：一个跨列卡片
                    ToolCard(
                        title: "相似图片聚类",
                        icon: "square.grid.3x3.fill",
                        gradient: Gradient(colors: [Color(hex: "4facfe"), Color(hex: "00f2fe")])
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
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(
                LinearGradient(
                    gradient: gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ToolsView()
}
