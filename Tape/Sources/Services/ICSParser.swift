import Foundation

/// Parses ICS/iCal feeds into UpcomingMeeting objects.
/// Handles VEVENT blocks with DTSTART, DTEND, SUMMARY.
/// Supports UTC (Z suffix), TZID-prefixed, and floating time formats.
struct ICSParser {

    struct ParsedEvent {
        let summary: String
        let startDate: Date
        let endDate: Date
    }

    static func parse(_ icsString: String) -> [ParsedEvent] {
        var events: [ParsedEvent] = []
        let lines = unfoldLines(icsString)

        var inEvent = false
        var summary: String?
        var dtStart: Date?
        var dtEnd: Date?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed == "BEGIN:VEVENT" {
                inEvent = true
                summary = nil
                dtStart = nil
                dtEnd = nil
            } else if trimmed == "END:VEVENT" {
                if let summary, let dtStart, let dtEnd {
                    events.append(ParsedEvent(summary: summary, startDate: dtStart, endDate: dtEnd))
                }
                inEvent = false
            } else if inEvent {
                if trimmed.hasPrefix("SUMMARY") {
                    summary = extractValue(trimmed)
                } else if trimmed.hasPrefix("DTSTART") {
                    dtStart = parseDateTime(trimmed)
                } else if trimmed.hasPrefix("DTEND") {
                    dtEnd = parseDateTime(trimmed)
                }
            }
        }

        return events
    }

    /// ICS long lines are folded with CRLF + whitespace. Unfold them.
    private static func unfoldLines(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var result: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                // Continuation of previous line
                if !result.isEmpty {
                    result[result.count - 1] += String(line.dropFirst())
                }
            } else {
                result.append(line)
            }
        }
        return result
    }

    /// Extract value from "PROPERTY;PARAMS:VALUE" or "PROPERTY:VALUE"
    private static func extractValue(_ line: String) -> String? {
        guard let colonIndex = line.firstIndex(of: ":") else { return nil }
        return String(line[line.index(after: colonIndex)...])
    }

    /// Parse ICS datetime from lines like:
    ///   DTSTART:20260330T190000Z                          (UTC)
    ///   DTSTART;TZID=America/New_York:20260330T140000     (with timezone)
    ///   DTSTART;VALUE=DATE:20260330                       (all-day)
    private static func parseDateTime(_ line: String) -> Date? {
        guard let colonIndex = line.firstIndex(of: ":") else { return nil }

        let params = String(line[...line.index(before: colonIndex)])
        let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

        // Extract TZID if present
        var timeZone: TimeZone?
        if let tzRange = params.range(of: "TZID=") {
            let tzString = String(params[tzRange.upperBound...]).components(separatedBy: ";").first ?? ""
            timeZone = TimeZone(identifier: tzString)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if value.hasSuffix("Z") {
            // UTC format: 20260330T190000Z
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter.date(from: value)
        } else if value.contains("T") {
            // Local or TZID format: 20260330T140000
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            formatter.timeZone = timeZone ?? .current
            return formatter.date(from: value)
        } else {
            // All-day: 20260330
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = timeZone ?? .current
            return formatter.date(from: value)
        }
    }
}
