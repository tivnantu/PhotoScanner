import SwiftUI

/// 设置页 - List + Section 布局
struct SettingsView: View {
    @State private var scanLimitIndex: Int = 1 // 默认 3000
    @State private var isScanning: Bool = false
    @State private var scannedCount: Int = 1234
    @State private var totalCount: Int = 3000
    
    private let scanLimits = ["1000", "3000", "5000", "8000", "1万", "1.5万", "2万", "无限"]
    
    var body: some View {
        NavigationStack {
            List {
                // 扫描控制区
                Section("扫描控制") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("扫描进度")
                            .font(.headline)
                        
                        ProgressView(value: Double(scannedCount), total: Double(totalCount))
                        
                        Text("已扫描 \(scannedCount.formatted()) / \(totalCount.formatted()) 张")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Spacer()
                            
                            if isScanning {
                                Button("暂停") {
                                    isScanning = false
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button("继续") {
                                    isScanning = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    
                    Picker("扫描数量上限", selection: $scanLimitIndex) {
                        ForEach(0..<scanLimits.count, id: \.self) { index in
                            Text("\(scanLimits[index]) 张").tag(index)
                        }
                    }
                }
                
                // 图库信息区
                Section("图库信息") {
                    HStack {
                        Text("图库总量")
                        Spacer()
                        Text("12,345 张")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("已索引")
                        Spacer()
                        Text("1,234 张")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("索引大小")
                        Spacer()
                        Text("3.2 MB")
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 缓存管理区
                Section("缓存管理") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("清理缓存")
                            Text("缓存大小: 48 MB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("清理") {
                            // TODO: 实现缓存清理
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // 关于区
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com")!) {
                        HStack {
                            Text("开源许可")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("设置")
        }
    }
}

#Preview {
    SettingsView()
}
