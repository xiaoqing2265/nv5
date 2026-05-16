import Foundation

enum CrashReporter {
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Logs/NV5", isDirectory: true)
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let filename = "crash-\(timestamp.replacingOccurrences(of: ":", with: "-")).log"
            let fileURL = logDir.appendingPathComponent(filename)

            var report = "NV5 Crash Report\n"
            report += "Date: \(timestamp)\n"
            report += "Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")\n"
            report += "Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")\n"
            report += "Exception: \(exception.name.rawValue)\n"
            report += "Reason: \(exception.reason ?? "unknown")\n"
            report += "Call Stack:\n"
            report += exception.callStackSymbols.joined(separator: "\n")
            report += "\n"

            try? report.write(to: fileURL, atomically: true, encoding: .utf8)
            print("[CrashReporter] Report saved to \(fileURL.path)")
        }

        signal(SIGSEGV) { sig in
            let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Logs/NV5", isDirectory: true)
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let filename = "signal-\(timestamp.replacingOccurrences(of: ":", with: "-")).log"
            let fileURL = logDir.appendingPathComponent(filename)

            var report = "NV5 Signal Crash Report\n"
            report += "Date: \(timestamp)\n"
            report += "Signal: \(sig)\n"
            report += "Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")\n"

            try? report.write(to: fileURL, atomically: true, encoding: .utf8)
            print("[CrashReporter] Signal report saved to \(fileURL.path)")
            exit(1)
        }
    }
}
