import XCTest
@testable import TodoistCore

final class SessionLogTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 0)

    private func session(_ kind: Session.Kind, at offset: TimeInterval, minutes: Double = 25) -> Session {
        var s = Session(kind: kind, start: epoch + offset, planned: minutes * 60)
        s.end = s.start + minutes * 60
        return s
    }

    func testRoundsCountFocusSinceTheLastLongBreak() {
        let log = [session(.focus, at: 0), session(.shortBreak, at: 1800, minutes: 5),
                   session(.focus, at: 3600), session(.longBreak, at: 5400, minutes: 15),
                   session(.focus, at: 7200), session(.shortBreak, at: 9000, minutes: 5),
                   session(.focus, at: 10800)]
        XCTAssertEqual(SessionLog.roundsSinceLongBreak(log), 2)
        XCTAssertEqual(SessionLog.roundsSinceLongBreak([]), 0)
        XCTAssertEqual(SessionLog.roundsSinceLongBreak([session(.longBreak, at: 0)]), 0)
    }

    func testUntrackedIsTheTimeWithNoTaskAttached() {
        var s = session(.focus, at: 0)   // 25 minutes
        s.segments = [.init(taskId: "1", content: "Release notes", start: s.start, end: s.start + 600)]
        XCTAssertEqual(s.seconds, 1500)
        XCTAssertEqual(s.untracked, 900)

        s.segments.append(.init(taskId: "2", content: "Picker", start: s.start + 600, end: s.start + 1500))
        XCTAssertEqual(s.untracked, 0)
    }

    func testSurvivesEncoding() throws {
        var s = session(.focus, at: 0)
        s.segments = [.init(taskId: "1", content: "Release notes", start: s.start, end: s.start + 600)]
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let back = try d.decode([Session].self, from: e.encode([s]))
        XCTAssertEqual(back.first?.id, s.id)
        XCTAssertEqual(back.first?.segments.first?.content, "Release notes")
        XCTAssertEqual(back.first?.untracked, 900)
    }

    /// The Today view groups by calendar day, not by a 24-hour window.
    func testTodayIsTheCalendarDay() {
        let now = Date()
        let log = [session(.focus, at: 0), Session(kind: .focus, start: now, planned: 1500)]
        XCTAssertEqual(SessionLog.today(log, now: now).count, 1)
    }
}
