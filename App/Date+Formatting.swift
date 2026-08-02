import Foundation

extension Date {
    /// Formats as a short, human-readable timestamp: "10:19am" for today,
    /// "yesterday" for yesterday, or short date+time otherwise.
    var shortTimestamp: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mma"
            return formatter.string(from: self).lowercased()
        } else if calendar.isDateInYesterday(self) {
            return "yesterday"
        } else {
            let formatter = DateFormatter()
            if Calendar.current.component(.year, from: self)
                == Calendar.current.component(.year, from: Date()) {
                formatter.setLocalizedDateFormatFromTemplate("MMMd")
            } else {
                formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
            }
            return formatter.string(from: self)
        }
    }

    /// Formats as a brief date and time: "Aug 2, 10:19am", or "Aug 2, 2025,
    /// 10:19am" outside the current year. Unlike `shortTimestamp` this always
    /// names the day, so a stamp from today still reads as a date.
    var shortDateAndTime: String {
        let formatter = DateFormatter()
        let sameYear = Calendar.current.component(.year, from: self)
            == Calendar.current.component(.year, from: Date())
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdyyyy")
        let date = formatter.string(from: self)

        formatter.dateFormat = "h:mma"
        let time = formatter.string(from: self).lowercased()

        return "\(date), \(time)"
    }
}
