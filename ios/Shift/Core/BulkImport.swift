import Foundation

enum BulkImport {
    static func parse(_ text: String) -> [(title: String, memo: String)] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        var rows: [(title: String, memo: String)] = []
        for line in trimmed.split(separator: "\n", omittingEmptySubsequences: false) {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            let title = cols.first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            guard !title.isEmpty else { continue }
            let memo = cols.count > 1 ? cols[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            rows.append((title: title, memo: memo))
        }
        return rows
    }

    static func makeEvents(_ rows: [(title: String, memo: String)], color: String) -> [ShiftEvent] {
        rows.map {
            ShiftEvent(id: UUID().uuidString, title: $0.title, memo: $0.memo, color: color,
                       startDate: nil, endDate: nil, placed: false, allDay: true,
                       startTime: nil, endTime: nil, workHours: nil)
        }
    }
}
