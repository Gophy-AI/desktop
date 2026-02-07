import Foundation
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "CrashReporter")

/// Global crash reporter that catches and logs unhandled exceptions and signals
public final class CrashReporter: @unchecked Sendable {
    public static let shared = CrashReporter()

    private let crashLogURL: URL
    private var isInstalled = false

    private init() {
        // Store crash logs in Application Support/Gophy/Logs
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logsDir = appSupport.appendingPathComponent("Gophy/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        crashLogURL = logsDir.appendingPathComponent("crash_\(timestamp).log")
    }

    /// Install crash handlers - call this at app startup
    public func install() {
        guard !isInstalled else { return }
        isInstalled = true

        logger.info("Installing crash handlers, log file: \(self.crashLogURL.path, privacy: .public)")

        // Set up Objective-C exception handler
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.handleException(exception)
        }

        // Set up signal handlers for common crash signals
        setupSignalHandler(SIGABRT)
        setupSignalHandler(SIGBUS)
        setupSignalHandler(SIGFPE)
        setupSignalHandler(SIGILL)
        setupSignalHandler(SIGSEGV)
        setupSignalHandler(SIGTRAP)

        writeToLog("=== Crash Reporter Installed ===")
        writeToLog("Date: \(Date())")
        writeToLog("App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "unknown")")
        writeToLog("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        writeToLog("=============================\n")
    }

    private func setupSignalHandler(_ signal: Int32) {
        Foundation.signal(signal) { sig in
            CrashReporter.shared.handleSignal(sig)
        }
    }

    private func handleException(_ exception: NSException) {
        let message = """
        === UNCAUGHT EXCEPTION ===
        Date: \(Date())
        Name: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "unknown")
        User Info: \(exception.userInfo ?? [:])
        Call Stack:
        \(exception.callStackSymbols.joined(separator: "\n"))
        ===========================
        """

        logger.critical("\(message, privacy: .public)")
        writeToLog(message)
    }

    private func handleSignal(_ signal: Int32) {
        let signalName: String
        switch signal {
        case SIGABRT: signalName = "SIGABRT (Abort)"
        case SIGBUS: signalName = "SIGBUS (Bus Error)"
        case SIGFPE: signalName = "SIGFPE (Floating Point Exception)"
        case SIGILL: signalName = "SIGILL (Illegal Instruction)"
        case SIGSEGV: signalName = "SIGSEGV (Segmentation Fault)"
        case SIGTRAP: signalName = "SIGTRAP (Trace Trap)"
        default: signalName = "Signal \(signal)"
        }

        let message = """
        === SIGNAL CAUGHT ===
        Date: \(Date())
        Signal: \(signalName)
        Call Stack:
        \(Thread.callStackSymbols.joined(separator: "\n"))
        =====================
        """

        // Use stderr since logger may not work during signal handling
        fputs(message + "\n", stderr)
        writeToLog(message)

        // Re-raise signal with default handler to allow system crash reporting
        Foundation.signal(signal, SIG_DFL)
        raise(signal)
    }

    /// Log a message to the crash log file
    public func writeToLog(_ message: String) {
        let logMessage = "[\(Date())] \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: crashLogURL.path) {
                if let handle = try? FileHandle(forWritingTo: crashLogURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: crashLogURL)
            }
        }
    }

    /// Log an error with context
    public func logError(_ error: Error, context: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let message = """
        === ERROR ===
        Context: \(context)
        Location: \(fileName):\(line) in \(function)
        Error: \(error)
        Localized: \(error.localizedDescription)
        Type: \(type(of: error))
        =============
        """

        logger.error("\(message, privacy: .public)")
        writeToLog(message)
    }

    /// Log a warning with context
    public func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "WARNING [\(fileName):\(line) \(function)]: \(message)"
        logger.warning("\(logMessage, privacy: .public)")
        writeToLog(logMessage)
    }

    /// Log an info message
    public func logInfo(_ message: String) {
        logger.info("\(message, privacy: .public)")
        writeToLog("INFO: \(message)")
    }

    /// Execute an async operation with error logging
    public func withErrorLogging<T>(context: String, operation: () async throws -> T) async throws -> T {
        logInfo("Starting: \(context)")
        do {
            let result = try await operation()
            logInfo("Completed: \(context)")
            return result
        } catch {
            logError(error, context: context)
            throw error
        }
    }

    /// Execute an async operation, catching and logging errors, returning nil on failure
    public func withErrorCatching<T>(context: String, operation: () async throws -> T) async -> T? {
        logInfo("Starting (catch mode): \(context)")
        do {
            let result = try await operation()
            logInfo("Completed: \(context)")
            return result
        } catch {
            logError(error, context: context)
            return nil
        }
    }

    /// Get the path to the current crash log
    public var currentLogPath: String {
        crashLogURL.path
    }

    /// Get all crash log files
    public func getAllCrashLogs() -> [URL] {
        let logsDir = crashLogURL.deletingLastPathComponent()
        let files = try? FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.creationDateKey])
        return files?.filter { $0.pathExtension == "log" }.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            return date1 > date2
        } ?? []
    }
}
