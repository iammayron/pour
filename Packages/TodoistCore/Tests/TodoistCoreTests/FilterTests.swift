import XCTest
@testable import TodoistCore

final class FilterTests: XCTestCase {
    func testBuckets() {
        let today = "2026-09-04"
        let t = { (d: String) in TodoistTask(id: d, content: d, due: .init(date: d, string: d)) }
        let late = t("2026-09-01"), now = t("2026-09-04T15:00:00"), soon = t("2026-09-09"), none = TodoistTask(id: "n", content: "n")
        XCTAssertEqual([late, now, soon, none].filter { $0.matches("overdue", today: today) }, [late])
        XCTAssertEqual([late, now, soon, none].filter { $0.matches("today", today: today) }, [now])
        XCTAssertEqual([late, now, soon, none].filter { $0.matches("7 days", today: today) }, [now, soon])
        XCTAssertEqual([late, now, soon, none].filter { $0.matches("upcoming", today: today) }.count, 4)
    }
}
