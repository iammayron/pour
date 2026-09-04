import XCTest
@testable import TodoistCore

final class DueTests: XCTestCase {
    func testParsesEveryShapeTodoistSends() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let allDay = TodoistTask.Due(date: "2026-07-20", string: "20 Jul")
        XCTAssertFalse(allDay.hasTime)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: allDay.parsed!),
                       DateComponents(year: 2026, month: 7, day: 20))

        let floating = TodoistTask.Due(date: "2026-07-20T12:00:00", string: "2026-07-20 12:00")
        XCTAssertTrue(floating.hasTime)
        XCTAssertEqual(cal.dateComponents([.hour, .minute], from: floating.parsed!),
                       DateComponents(hour: 12, minute: 0))

        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let utc = TodoistTask.Due(date: "2026-07-20T12:00:00Z", string: "20 Jul 12:00")
        XCTAssertEqual(cal.dateComponents([.hour], from: utc.parsed!), DateComponents(hour: 12))

        // Unparseable input falls back to Todoist's own text rather than showing nothing.
        let junk = TodoistTask.Due(date: "no", string: "someday")
        XCTAssertNil(junk.parsed)
        XCTAssertEqual(junk.label, "someday")
    }
}
