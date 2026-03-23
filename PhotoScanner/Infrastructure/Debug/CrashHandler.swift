import Foundation
import Darwin

// MARK: - CrashHandler

/// 崩溃处理器
///
/// 捕获 Swift fatalErrors 和 Unix 信号，打印详细堆栈信息。
/// 仅在 DEBUG 构建中生效。
///
/// ## 使用方式
/// 在 App 启动时调用：
/// ```swift
/// @main
/// struct PhotoScannerApp: App {
///     init() {
///         #if DEBUG
///         CrashHandler.setup()
///         #endif
///     }
/// }
/// ```
///
/// ## 捕获类型
/// - Swift fatalErrors / precondition failures → SIGTRAP
/// - 未捕获的 ObjC 异常
/// - Unix 信号：SIGABRT, SIGSEGV, SIGILL, SIGBUS
enum CrashHandler {
    
    /// 设置崩溃处理
    static func setup() {
        // 捕获 Swift fatalErrors
        NSSetUncaughtExceptionHandler { exception in
            print("💥 [CRASH] Unhandled Exception:")
            print("  Reason: \(exception.reason ?? "Unknown")")
            print("  Stack Trace:")
            for (index, frame) in (exception.callStackSymbols ?? []).enumerated() {
                print("    [\(index)] \(frame)")
            }
        }
        
        // 捕获 Unix 信号
        signal(SIGABRT, signalHandler)
        signal(SIGTRAP, signalHandler)
        signal(SIGSEGV, signalHandler)
        signal(SIGILL, signalHandler)
        signal(SIGBUS, signalHandler)
    }
}

// MARK: - Signal Handler

/// C 函数指针必须是全局函数
private func signalHandler(_ sig: Int32) {
    let signalName: String
    switch sig {
    case SIGABRT: 
        signalName = "SIGABRT (Abort)"
    case SIGTRAP: 
        signalName = "SIGTRAP (fatalError/precondition)"
    case SIGSEGV: 
        signalName = "SIGSEGV (Bad memory access)"
    case SIGILL: 
        signalName = "SIGILL (Illegal instruction)"
    case SIGBUS: 
        signalName = "SIGBUS (Bus error)"
    default: 
        signalName = "Signal(\(sig))"
    }
    
    print("💥 [CRASH] \(signalName)")
    print("  Stack Trace:")
    let frames = Thread.callStackSymbols
    for (index, frame) in frames.enumerated() {
        print("    [\(index)] \(frame)")
    }
    
    // 恢复默认处理并退出
    signal(sig, SIG_DFL)
    raise(sig)
}
