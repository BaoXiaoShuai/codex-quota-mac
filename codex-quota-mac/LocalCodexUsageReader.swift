import Foundation

/// 从本机 Codex 会话记录汇总出的单日 Token 用量。
struct LocalCodexUsageSnapshot: Equatable {
    let dateKey: String
    let tokens: Int64
    let sessionCount: Int
}

/// 只读取 Token 计数事件，不保留或输出会话正文。
final class LocalCodexUsageReader {
    private let fileManager: FileManager
    private let codexHomeURL: URL

    init(fileManager: FileManager = .default, codexHomeURL: URL? = nil) {
        self.fileManager = fileManager
        if let codexHomeURL {
            self.codexHomeURL = codexHomeURL
        } else if let configuredHome = ProcessInfo.processInfo.environment["CODEX_HOME"],
                  !configuredHome.isEmpty {
            self.codexHomeURL = URL(
                fileURLWithPath: (configuredHome as NSString).expandingTildeInPath,
                isDirectory: true
            )
        } else {
            self.codexHomeURL = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }
    }

    /// 汇总本地当天用量。每个会话按累计值差额计算，避免重复 token_count 通知被重复相加。
    func readToday(now: Date = Date(), timeZone: TimeZone = .current) -> LocalCodexUsageSnapshot? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone

        let dayStart = calendar.startOfDay(for: now)
        guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart),
              let scanCutoff = calendar.date(byAdding: .day, value: -1, to: dayStart) else {
            return nil
        }

        let sessionsURL = codexHomeURL.appendingPathComponent("sessions", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let timestampParser = CodexTimestampParser()
        var sessions: [String: SessionUsage] = [:]
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) >= scanCutoff,
                  let usage = readSession(
                    at: fileURL,
                    dayStart: dayStart,
                    nextDayStart: nextDayStart,
                    timestampParser: timestampParser
                  ),
                  usage.hasTodayEvent else {
                continue
            }

            let key = usage.sessionID ?? fileURL.deletingPathExtension().lastPathComponent
            var merged = sessions[key] ?? SessionUsage()
            merged.maximumBeforeToday = max(merged.maximumBeforeToday, usage.maximumBeforeToday)
            merged.maximumToday = max(merged.maximumToday, usage.maximumToday)
            merged.hasTodayEvent = true
            sessions[key] = merged
        }

        var total: Int64 = 0
        var contributingSessions = 0
        for usage in sessions.values {
            let tokens = max(0, usage.maximumToday - usage.maximumBeforeToday)
            guard tokens > 0 else {
                continue
            }
            contributingSessions += 1
            let (sum, overflow) = total.addingReportingOverflow(tokens)
            total = overflow ? Int64.max : sum
        }

        guard total > 0 else {
            return nil
        }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"
        return LocalCodexUsageSnapshot(
            dateKey: dayFormatter.string(from: dayStart),
            tokens: total,
            sessionCount: contributingSessions
        )
    }

    private func readSession(
        at url: URL,
        dayStart: Date,
        nextDayStart: Date,
        timestampParser: CodexTimestampParser
    ) -> SessionUsage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        var usage = SessionUsage()
        var pending = Data()

        do {
            while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                pending.append(chunk)
                consumeCompleteLines(
                    from: &pending,
                    usage: &usage,
                    dayStart: dayStart,
                    nextDayStart: nextDayStart,
                    timestampParser: timestampParser
                )
            }
            if !pending.isEmpty {
                consumeLine(
                    pending,
                    usage: &usage,
                    dayStart: dayStart,
                    nextDayStart: nextDayStart,
                    timestampParser: timestampParser
                )
            }
        } catch {
            return usage.hasTodayEvent ? usage : nil
        }
        return usage
    }
    private func consumeCompleteLines(
        from buffer: inout Data,
        usage: inout SessionUsage,
        dayStart: Date,
        nextDayStart: Date,
        timestampParser: CodexTimestampParser
    ) {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            consumeLine(
                line,
                usage: &usage,
                dayStart: dayStart,
                nextDayStart: nextDayStart,
                timestampParser: timestampParser
            )
        }
    }

    private func consumeLine(
        _ line: Data,
        usage: inout SessionUsage,
        dayStart: Date,
        nextDayStart: Date,
        timestampParser: CodexTimestampParser
    ) {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line),
              let event = object as? [String: Any],
              let payload = event["payload"] as? [String: Any] else {
            return
        }

        if event["type"] as? String == "session_meta" {
            usage.sessionID = payload["id"] as? String ?? usage.sessionID
            return
        }

        guard event["type"] as? String == "event_msg",
              payload["type"] as? String == "token_count",
              let timestampText = event["timestamp"] as? String,
              let timestamp = timestampParser.date(from: timestampText),
              timestamp < nextDayStart,
              let info = payload["info"] as? [String: Any],
              let totalUsage = info["total_token_usage"] as? [String: Any],
              let totalNumber = totalUsage["total_tokens"] as? NSNumber else {
            return
        }

        let cumulativeTokens = max(0, totalNumber.int64Value)
        if timestamp < dayStart {
            usage.maximumBeforeToday = max(usage.maximumBeforeToday, cumulativeTokens)
        } else {
            usage.maximumToday = max(usage.maximumToday, cumulativeTokens)
            usage.hasTodayEvent = true
        }
    }
}

private struct SessionUsage {
    var sessionID: String?
    var maximumBeforeToday: Int64 = 0
    var maximumToday: Int64 = 0
    var hasTodayEvent = false
}

private final class CodexTimestampParser {
    private let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func date(from value: String) -> Date? {
        fractional.date(from: value) ?? standard.date(from: value)
    }
}
extension LocalCodexUsageSnapshot {
    /// 用本地实时记录补齐官方当天数据；取较大值，避免官方回填后重复计算。
    func merging(into official: AccountTokenUsage?) -> AccountTokenUsage {
        let officialBuckets = official?.dailyUsageBuckets ?? []
        let matchingBuckets = officialBuckets.filter { String($0.startDate.prefix(10)) == dateKey }
        let officialToday = matchingBuckets.reduce(Int64(0)) { partial, bucket in
            let value = max(0, bucket.tokens)
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? Int64.max : sum
        }
        let mergedToday = max(officialToday, tokens)

        var mergedBuckets = officialBuckets.filter { String($0.startDate.prefix(10)) != dateKey }
        mergedBuckets.append(TokenUsageDailyBucket(startDate: dateKey, tokens: mergedToday))

        let oldSummary = official?.summary
        let oldPeak = oldSummary?.peakDailyTokens ?? 0
        let summary = AccountTokenUsageSummary(
            currentStreakDays: oldSummary?.currentStreakDays,
            lifetimeTokens: oldSummary?.lifetimeTokens,
            longestRunningTurnSec: oldSummary?.longestRunningTurnSec,
            longestStreakDays: oldSummary?.longestStreakDays,
            peakDailyTokens: max(oldPeak, mergedToday)
        )
        return AccountTokenUsage(dailyUsageBuckets: mergedBuckets, summary: summary)
    }
}
