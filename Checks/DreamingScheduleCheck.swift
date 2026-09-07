import Foundation

@main
enum DreamingScheduleCheck {
    static func main() throws {
        let zone = "Australia/Melbourne"
        let schedule = DreamingSchedule(projectPath: "/fixture/project", hour: 2, minute: 30,
                                        timeZoneID: zone, enabled: true)
        precondition(DreamingScheduler.isEligible(schedule, at: date("2026-09-07T02:32:00", zone), attemptedLocalDay: nil))
        precondition(!DreamingScheduler.isEligible(schedule, at: date("2026-09-07T02:35:00", zone), attemptedLocalDay: nil))
        precondition(!DreamingScheduler.isEligible(schedule, at: date("2026-09-07T02:32:00", zone), attemptedLocalDay: "2026-09-07"))

        let invalid = DreamingSchedule(projectPath: "/fixture/project", hour: 2, minute: 30,
                                       timeZoneID: "Not/A_TimeZone", enabled: true)
        precondition(!DreamingScheduler.isEligible(invalid, at: Date(), attemptedLocalDay: nil))

        let fallback = DreamingSchedule(projectPath: "/fixture/project", hour: 2, minute: 1,
                                        timeZoneID: zone, enabled: true)
        let firstOccurrence = Date(timeIntervalSince1970: 1_775_314_860) // 2026-04-05 02:01 AEDT
        let repeatedOccurrence = Date(timeIntervalSince1970: 1_775_318_460) // 2026-04-05 02:01 AEST
        precondition(DreamingScheduler.isEligible(fallback, at: firstOccurrence, attemptedLocalDay: nil))
        precondition(!DreamingScheduler.isEligible(fallback, at: repeatedOccurrence, attemptedLocalDay: "2026-04-05"))

        let disabled = DreamingSchedule(projectPath: "/fixture/project", hour: 2, minute: 30,
                                        timeZoneID: zone, enabled: false)
        precondition(!DreamingScheduler.isEligible(disabled, at: date("2026-09-07T02:32:00", zone), attemptedLocalDay: nil))
        print("PASS dreaming schedule window, disabled default, invalid timezone, and DST repeat deduplication")
    }

    private static func date(_ local: String, _ timeZoneID: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: timeZoneID)
        return formatter.date(from: local)!
    }
}
