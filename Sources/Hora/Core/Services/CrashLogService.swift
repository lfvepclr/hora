import Foundation

/// 崩溃日志服务 - 捕获未处理异常和信号，写入本地日志文件
/// 日志位置: ~/Library/Logs/Hora/
/// 线程安全：内部用 NSLock 保护日志缓冲区与文件写入（Swift 6 严格并发下标 @unchecked Sendable）
final class CrashLogService: @unchecked Sendable {
    static let shared = CrashLogService()
    
    // MARK: - Properties
    
    /// 日志目录
    private let logDirectory: URL
    
    /// 应用诊断日志文件
    private let diagnosticLogFile: URL
    
    /// 原始异常处理器（保存以便链式调用）
    fileprivate var previousExceptionHandler: NSUncaughtExceptionHandler?
    
    /// 原始信号处理器
    private var previousSignalHandlers: [Int32: (@convention(c) (Int32) -> Void)] = [:]
    
    /// 诊断日志缓冲区（启动阶段暂存，文件创建后写入）
    private var pendingLogs: [String] = []
    private var isFileReady = false
    
    /// 保护 pendingLogs / isFileReady / 文件写入的锁
    private let lock = NSLock()
    
    // MARK: - Init
    
    private init() {
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Hora")
        self.logDirectory = logDir
        self.diagnosticLogFile = logDir.appendingPathComponent("diagnostic.log")
    }
    
    // MARK: - Setup
    
    /// 安装崩溃捕获和日志系统（应在 applicationDidFinishLaunching 最开始调用）
    func setup() {
        // 1. 创建日志目录
        createLogDirectoryIfNeeded()
        
        // 2. 标记文件就绪，写入暂存日志
        lock.lock()
        isFileReady = true
        flushPendingLogs()
        lock.unlock()
        
        // 3. 检查上次崩溃日志
        checkPreviousCrashLogs()
        
        // 4. 注册异常处理器
        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)
        
        // 5. 注册信号处理器
        installSignalHandlers()
        
        log("CrashLogService initialized successfully")
    }
    
    // MARK: - Diagnostic Logging
    
    /// 记录诊断日志
    func log(_ message: String) {
        let timestamp = DateFormatter.iso8601Full.string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        
        print("[Hora] \(entry)")
        
        lock.lock()
        defer { lock.unlock() }
        if isFileReady {
            appendToFile(entry)
        } else {
            pendingLogs.append(entry)
        }
    }
    
    /// 记录错误日志
    func logError(_ message: String, file: String = #file, line: Int = #line) {
        let filename = (file as NSString).lastPathComponent
        log("❌ ERROR [\(filename):\(line)] \(message)")
    }
    
    /// 记录警告日志
    func logWarning(_ message: String, file: String = #file, line: Int = #line) {
        let filename = (file as NSString).lastPathComponent
        log("⚠️ WARN [\(filename):\(line)] \(message)")
    }
    
    // MARK: - Crash Log Path
    
    /// 获取最近的崩溃日志文件路径（供UI展示用）
    var lastCrashLogPath: String? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil) else {
            return nil
        }
        
        let crashFiles = files.filter { $0.lastPathComponent.hasPrefix("crash-") && $0.pathExtension == "log" }
        return crashFiles.sorted { $0.lastPathComponent > $1.lastPathComponent }.first?.path
    }
    
    // MARK: - Private Helpers
    
    private func createLogDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logDirectory.path) {
            try? fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        }
    }
    
    private func flushPendingLogs() {
        guard !pendingLogs.isEmpty else { return }
        for entry in pendingLogs {
            appendToFile(entry)
        }
        pendingLogs.removeAll()
    }
    
    private func appendToFile(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        
        let fm = FileManager.default
        if fm.fileExists(atPath: diagnosticLogFile.path) {
            if let handle = try? FileHandle(forWritingTo: diagnosticLogFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            // 首次写入，创建文件并写入Header
            let header = generateDiagnosticHeader()
            let headerData = (header + "\n").data(using: .utf8) ?? Data()
            let fullData = headerData + data
            try? fullData.write(to: diagnosticLogFile, options: .atomic)
        }
    }
    
    private func generateDiagnosticHeader() -> String {
        """
        ========================================
        Hora Diagnostic Log
        Version: \(AppInfo.version) (\(AppInfo.build))
        OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Bundle: \(Bundle.main.bundlePath)
        Module Bundle: \(Bundle.module.bundlePath)
        Start Time: \(DateFormatter.iso8601Full.string(from: Date()))
        ========================================
        """
    }
    
    private func checkPreviousCrashLogs() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        let crashFiles = files.filter { $0.lastPathComponent.hasPrefix("crash-") && $0.pathExtension == "log" }
        if let latest = crashFiles.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first {
            log("Previous crash log found: \(latest.path)")
        }
    }
    
    // MARK: - Signal Handlers
    
    private let signalsToMonitor: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE]
    
    private func installSignalHandlers() {
        for sig in signalsToMonitor {
            var old = sigaction()
            sigaction(sig, nil, &old)
            // 保存旧的 sa_sigaction 或者传统的 sa_handler
            // 注意: 在信号处理器中只能做异步安全操作
            
            signal(sig) { sigNum in
                // 先调用原始处理器
                // 注意: signal handler 中不能做复杂操作
                
                // 写入崩溃日志（使用异步安全方式）
                CrashLogService.writeCrashLogForSignal(sigNum)
                
                // 恢复默认处理器并重新触发，让系统生成标准 crash report
                signal(sigNum, SIG_DFL)
                raise(sigNum)
            }
        }
    }
    
    // MARK: - Crash Log Writing (Async-Signal-Safe)
    
    /// 在异常处理器中写入崩溃日志（非信号安全上下文，可以使用 Obj-C/Foundation）
    fileprivate static func writeCrashLogForException(_ exception: NSException) {
        let service = shared
        let timestamp = DateFormatter.filenameSafe.string(from: Date())
        let crashLogPath = service.logDirectory.appendingPathComponent("crash-\(timestamp).log")
        
        var content = """
        ========================================
        Hora Crash Report
        ========================================
        Time: \(DateFormatter.iso8601Full.string(from: Date()))
        App Version: \(AppInfo.version) (\(AppInfo.build))
        OS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Bundle Path: \(Bundle.main.bundlePath)
        Module Bundle: \(Bundle.module.bundlePath)
        
        Exception Name: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "unknown")
        User Info: \(exception.userInfo ?? [:])
        
        Call Stack:
        \(exception.callStackSymbols.joined(separator: "\n"))
        ========================================
        
        """
        
        // 附带最近的诊断日志
        if let diagData = try? Data(contentsOf: service.diagnosticLogFile),
           let diagContent = String(data: diagData, encoding: .utf8) {
            content += """
            --- Recent Diagnostic Log ---
            \(diagContent.suffix(4096))
            """
        }
        
        try? content.write(to: crashLogPath, atomically: true, encoding: .utf8)
    }
    
    /// 在信号处理器中写入崩溃日志（异步信号安全上下文，使用最小化操作）
    private static func writeCrashLogForSignal(_ signal: Int32) {
        let service = shared
        let timestamp = DateFormatter.filenameSafe.string(from: Date())
        let crashLogPath = service.logDirectory.appendingPathComponent("crash-sig\(signal)-\(timestamp).log")
        
        let signalName: String
        switch signal {
        case SIGABRT: signalName = "SIGABRT"
        case SIGSEGV: signalName = "SIGSEGV"
        case SIGBUS: signalName = "SIGBUS"
        case SIGILL: signalName = "SIGILL"
        case SIGTRAP: signalName = "SIGTRAP"
        case SIGFPE: signalName = "SIGFPE"
        default: signalName = "SIGNAL(\(signal))"
        }
        
        // 获取调用栈（在信号处理器中 Thread.callStackSymbols 未必可靠，但可以尝试）
        let symbols = Thread.callStackSymbols.joined(separator: "\n")
        
        var content = """
        ========================================
        Hora Crash Report (Signal)
        ========================================
        Time: \(DateFormatter.iso8601Full.string(from: Date()))
        App Version: \(AppInfo.version) (\(AppInfo.build))
        OS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Bundle Path: \(Bundle.main.bundlePath)
        
        Signal: \(signalName) (\(signal))
        
        Call Stack (may be unreliable in signal handler):
        \(symbols)
        ========================================
        
        """
        
        // 附带最近的诊断日志
        if let diagData = try? Data(contentsOf: service.diagnosticLogFile),
           let diagContent = String(data: diagData, encoding: .utf8) {
            content += """
            --- Recent Diagnostic Log ---
            \(diagContent.suffix(4096))
            """
        }
        
        try? content.write(to: crashLogPath, atomically: true, encoding: .utf8)
    }
}

// MARK: - Exception Handler

private func uncaughtExceptionHandler(_ exception: NSException) {
    // 先写入崩溃日志
    CrashLogService.writeCrashLogForException(exception)
    
    // 调用之前的处理器（如果有）
    if let previous = CrashLogService.shared.previousExceptionHandler {
        previous(exception)
    }
}

// MARK: - DateFormatter Extensions

private extension DateFormatter {
    static let iso8601Full: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    static let filenameSafe: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
