import SwiftUI
import QuartzCore

// MARK: - PerformanceOverlay

/// 浮动性能监控面板
///
/// ## 功能
/// - 实时显示内存、温度、FPS
/// - 可拖拽、可折叠为小圆点
/// - 仅 DEBUG 构建可见
///
/// ## 注入方式
/// ```swift
/// // 在 App 入口添加
/// .overlay {
///     #if DEBUG
///     PerformanceOverlay()
///     #endif
/// }
/// ```
struct PerformanceOverlay: View {

    // MARK: - State

    @State private var monitor = PerformanceMetricsCollector()
    @State private var isExpanded = false
    @State private var dragOffset: CGSize = .zero
    @State private var position: CGPoint = CGPoint(x: 72, y: 80)
    @State private var showDetails = false

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            Group {
                if isExpanded {
                    if showDetails {
                        detailedPanel
                    } else {
                        expandedPanel
                    }
                } else {
                    collapsedDot
                }
            }
            .position(clampedPosition(in: geo.size))
            .gesture(dragGesture(in: geo.size))
            .animation(.snappy(duration: 0.25), value: isExpanded)
            .animation(.snappy(duration: 0.2), value: showDetails)
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }
}

// MARK: - Collapsed Dot

private extension PerformanceOverlay {

    var collapsedDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: "gauge")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            .onTapGesture { isExpanded = true }
    }

    var dotColor: Color {
        switch monitor.thermalState {
        case .nominal:  .green
        case .fair:     .yellow
        case .serious:  .orange
        case .critical: .red
        @unknown default: .gray
        }
    }
}

// MARK: - Expanded Panel

private extension PerformanceOverlay {

    var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 标题栏
            HStack {
                Image(systemName: "gauge")
                    .font(.caption2.bold())
                Text("Performance")
                    .font(.caption2.bold())
                Spacer()
                Button {
                    showDetails = true
                } label: {
                    Image(systemName: "chart.line.ascending")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                Button {
                    isExpanded = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            Divider()

            // 核心指标
            metricRow(icon: "memorychip", label: "内存",
                      value: monitor.formattedMemory,
                      color: monitor.memoryColor)

            metricRow(icon: "thermometer.medium", label: "温度",
                      value: monitor.thermalLabel,
                      color: monitor.thermalColor)

            metricRow(icon: "speedometer", label: "FPS",
                      value: monitor.formattedFPS,
                      color: monitor.fpsColor)
        }
        .padding(10)
        .frame(width: 180)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .onTapGesture { } // 防止点击穿透
    }

    var detailedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题栏
            HStack {
                Button {
                    showDetails = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                Text("详细指标")
                    .font(.caption2.bold())
                Spacer()
                Button {
                    showDetails = false
                    isExpanded = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            Divider()

            // 设备信息
            GroupBox("设备状态") {
                VStack(spacing: 4) {
                    detailRow(label: "内存", value: monitor.formattedMemory, color: monitor.memoryColor)
                    detailRow(label: "温度", value: monitor.thermalLabel, color: monitor.thermalColor)
                    detailRow(label: "FPS", value: monitor.formattedFPS, color: monitor.fpsColor)
                    detailRow(label: "电量", value: monitor.formattedBattery, color: .green)
                }
            }
        }
        .padding(10)
        .frame(width: 220)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    func metricRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 14)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.primary.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(.caption2, design: .monospaced).bold())
                .foregroundStyle(color)
        }
    }

    func detailRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.primary.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(.caption2, design: .monospaced).bold())
                .foregroundStyle(color)
        }
    }
}

// MARK: - Drag Gesture

private extension PerformanceOverlay {

    func clampedPosition(in size: CGSize) -> CGPoint {
        let margin: CGFloat = 20
        let x = min(max(position.x + dragOffset.width, margin), size.width - margin)
        let y = min(max(position.y + dragOffset.height, margin), size.height - margin)
        return CGPoint(x: x, y: y)
    }

    func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                position = clampedPosition(in: size)
                dragOffset = .zero
            }
    }
}

// MARK: - Performance Metrics Collector

/// 性能数据采集（定时刷新）
@Observable
private final class PerformanceMetricsCollector {

    // MARK: - 设备状态
    
    private(set) var memoryMB: Double = 0
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    private(set) var fps: Double = 60
    private(set) var batteryLevel: Double = 1.0

    // MARK: - FPS 计算
    
    private var lastFrameTime: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var displayLink: CADisplayLink?

    private var timer: Timer?

    // MARK: - Lifecycle

    init() {
        refresh()
        setupFPSMonitor()

        // 每 2 秒刷新所有指标
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
        displayLink?.invalidate()
    }

    // MARK: - FPS Monitor

    private func setupFPSMonitor() {
        displayLink = CADisplayLink(target: FPSProxy(target: self), selector: #selector(FPSProxy.tick(_:)))
        displayLink?.add(to: .main, forMode: .common)
    }

    func recordFrame() {
        frameCount += 1
        let now = CACurrentMediaTime()
        let elapsed = now - lastFrameTime
        if elapsed >= 1.0 {
            fps = Double(frameCount) / elapsed
            frameCount = 0
            lastFrameTime = now
        }
    }

    // MARK: - Data Refresh

    func refresh() {
        // 内存使用
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            memoryMB = Double(info.phys_footprint) / 1024 / 1024
        }
        
        // 温度状态
        thermalState = ProcessInfo.processInfo.thermalState
        
        // 电量
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = Double(UIDevice.current.batteryLevel)
    }

    // MARK: - Formatted Values

    var formattedMemory: String {
        if memoryMB >= 1024 {
            return String(format: "%.1f GB", memoryMB / 1024)
        }
        return String(format: "%.0f MB", memoryMB)
    }

    var memoryColor: Color {
        if memoryMB < 200 { return .green }
        if memoryMB < 400 { return .yellow }
        return .orange
    }

    var thermalLabel: String {
        switch thermalState {
        case .nominal:  "正常"
        case .fair:     "轻微"
        case .serious:  "严重"
        case .critical: "危急"
        @unknown default: "未知"
        }
    }

    var thermalColor: Color {
        switch thermalState {
        case .nominal:  .green
        case .fair:     .yellow
        case .serious:  .orange
        case .critical: .red
        @unknown default: .gray
        }
    }

    var formattedFPS: String {
        String(format: "%.0f", fps)
    }

    var fpsColor: Color {
        if fps >= 55 { return .green }
        if fps >= 30 { return .yellow }
        return .red
    }

    var formattedBattery: String {
        if batteryLevel < 0 { return "充电中" }
        return String(format: "%.0f%%", batteryLevel * 100)
    }
}

// MARK: - FPS Proxy

/// FPS 代理（避免 @Observable 与 @objc 冲突）
private class FPSProxy {
    weak var target: PerformanceMetricsCollector?
    init(target: PerformanceMetricsCollector) { self.target = target }
    @objc func tick(_: CADisplayLink) {
        target?.recordFrame()
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        Text("App Content")
    }
    .overlay { PerformanceOverlay() }
}
#endif
