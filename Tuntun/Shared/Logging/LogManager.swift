//
//  LogManager.swift
//  Tuntun
//
//  Created by dimaswisodewo on 18/11/2026.
//

import Foundation
import os

// MARK: - Category

/// The area of the app a log line belongs to. The raw value is the OSLog category, so Console
/// and `log stream` can filter by it.
enum LogCategory: String, CaseIterable, Sendable {
    case app
    case audio
    case voice
    case tracking
    case session
    case storage
}

// MARK: - Level

/// Severity of a log line, mapped onto the matching `OSLogType`.
enum LogLevel: Sendable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault

    /// Fixed-width tag so the columns after it line up in the console.
    var tag: String {
        switch self {
        case .debug:
            return "DEBUG "
        case .info:
            return "INFO  "
        case .notice:
            return "NOTICE"
        case .warning:
            return "WARN  "
        case .error:
            return "ERROR "
        case .fault:
            return "FAULT "
        }
    }

    /// A glyph that makes the severity visible at a glance while scrolling.
    var glyph: String {
        switch self {
        case .debug:
            return "⚪️"
        case .info:
            return "🔵"
        case .notice:
            return "🟢"
        case .warning:
            return "🟡"
        case .error:
            return "🔴"
        case .fault:
            return "💥"
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .debug:
            return .debug
        case .info:
            return .info
        case .notice:
            return .default
        case .warning:
            return .error
        case .error:
            return .error
        case .fault:
            return .fault
        }
    }
}

// MARK: - Manager

/// The app's one logging entry point, built on OSLog.
///
/// Every line is formatted as
/// `2026-11-18T14:03:22.123+07:00 🔴 ERROR [storage] [bg] LocalSessionRepository.swift:78 summaries() › message`
/// so a console or device log shows when, how severe, which area, which thread and which call
/// site produced it.
///
/// `shared` is reached directly rather than injected: the manager holds only immutable values
/// (one `Logger` per category and a value-type date style), so it is not global mutable state,
/// and it is usable from Foundation-only logic files and any thread.
final class LogManager: Sendable {
    static let shared = LogManager()

    private let loggers: [LogCategory: Logger]

    private let timestampStyle = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true,
        timeZone: .current
    )

    private init() {
        let subsystem = Bundle.main.bundleIdentifier ?? "Tuntun"

        var loggers: [LogCategory: Logger] = [:]
        for category in LogCategory.allCases {
            loggers[category] = Logger(
                subsystem: subsystem,
                category: category.rawValue
            )
        }

        self.loggers = loggers
    }

    // MARK: - Logging

    /// Writes one formatted line. The message is built only when it will be written, so a
    /// `debug` call in a per-frame path costs nothing in Release.
    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        category: LogCategory,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        #if !DEBUG
        if level == .debug {
            return
        }
        #endif

        guard let logger = loggers[category] else {
            return
        }

        let formatted = format(
            level: level,
            message: message(),
            category: category,
            file: file,
            function: function,
            line: line
        )

        // Public, like the previous NSLog lines: messages carry diagnostics, never patient data.
        logger.log(
            level: level.osLogType,
            "\(formatted, privacy: .public)"
        )
    }

    func debug(
        _ message: @autoclosure () -> String,
        category: LogCategory,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(.debug, message(), category: category, file: file, function: function, line: line)
    }

    func info(
        _ message: @autoclosure () -> String,
        category: LogCategory,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(.info, message(), category: category, file: file, function: function, line: line)
    }

    func notice(
        _ message: @autoclosure () -> String,
        category: LogCategory,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(.notice, message(), category: category, file: file, function: function, line: line)
    }

    func warning(
        _ message: @autoclosure () -> String,
        category: LogCategory,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(.warning, message(), category: category, file: file, function: function, line: line)
    }

    func error(
        _ message: @autoclosure () -> String,
        category: LogCategory,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(.error, message(), category: category, file: file, function: function, line: line)
    }

    /// Logs a failure with the error's domain, code and description appended.
    func error(
        _ message: @autoclosure () -> String,
        error: any Error,
        category: LogCategory,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(
            .error,
            "\(message()) — \(Self.describe(error))",
            category: category,
            file: file,
            function: function,
            line: line
        )
    }

    func fault(
        _ message: @autoclosure () -> String,
        category: LogCategory,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(.fault, message(), category: category, file: file, function: function, line: line)
    }

    // MARK: - Formatting

    private func format(
        level: LogLevel,
        message: String,
        category: LogCategory,
        file: StaticString,
        function: StaticString,
        line: UInt
    ) -> String {
        let timestamp = Date().formatted(timestampStyle)
        let thread = Thread.isMainThread ? "main" : "bg"
        let fileName = Self.fileName(from: file)

        return "\(timestamp) \(level.glyph) \(level.tag) [\(category.rawValue)] [\(thread)] "
            + "\(fileName):\(line) \(function) › \(message)"
    }

    /// `#fileID` is `Module/File.swift`; only the file name is useful in the line.
    private static func fileName(from file: StaticString) -> Substring {
        let path = "\(file)"

        guard let slash = path.lastIndex(of: "/") else {
            return Substring(path)
        }

        return path[path.index(after: slash)...]
    }

    private static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) code=\(nsError.code): \(nsError.localizedDescription)"
    }
}
