import XCTest
@testable import TodoistCore

final class PomodoroTests: XCTestCase {
    let task = TodoistTask(id: "1", content: "Write tests", projectId: nil, priority: 1, due: nil)

    func testFullCycle() {
        var clock = Date(timeIntervalSince1970: 0)
        let p = Pomodoro(workMinutes: 25, breakMinutes: 5)
        p.now = { clock }

        p.start(task)
        XCTAssertEqual(p.phase, .work)
        XCTAssertEqual(p.remaining, 1500)
        XCTAssertEqual(p.level, 0)

        clock += 750
        XCTAssertEqual(p.level, 0.5, accuracy: 0.001)

        p.togglePause(); clock += 100
        XCTAssertEqual(p.remaining, 750)
        p.togglePause(); clock += 250
        XCTAssertEqual(p.remaining, 500)

        p.extend(by: 300)
        XCTAssertEqual(p.remaining, 800)
        XCTAssertNil(p.tick())

        clock += 800
        XCTAssertEqual(p.tick(), .work)
        XCTAssertEqual(p.phase, .workDone)
        XCTAssertEqual(p.level, 1)

        p.startBreak()
        XCTAssertEqual(p.remaining, 300)
        XCTAssertEqual(p.level, 1)
        clock += 300
        XCTAssertEqual(p.tick(), .rest)
        XCTAssertEqual(p.phase, .idle)
        XCTAssertNil(p.task)
    }

    func testTaskDecoding() throws {
        let json = #"{"results":[{"id":"9","content":"Buy milk","project_id":"p1","priority":4,"due":{"date":"2026-09-03","string":"today"},"labels":["Creative Memories"]}],"next_cursor":null}"#
        struct Page: Decodable { let results: [TodoistTask] }
        let page = try JSONDecoder().decode(Page.self, from: Data(json.utf8))
        XCTAssertEqual(page.results.first?.content, "Buy milk")
        XCTAssertEqual(page.results.first?.due?.string, "today")
        XCTAssertEqual(page.results.first?.labels, ["Creative Memories"])
    }
}
