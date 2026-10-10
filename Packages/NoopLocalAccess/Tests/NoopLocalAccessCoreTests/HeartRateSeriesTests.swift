import Foundation
import GRDB
import XCTest
@testable import NoopLocalAccessCore

final class HeartRateSeriesTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let firstHour: [String: JSONValue] = [
        "from": .string("1970-01-01T00:00:00Z"),
        "to": .string("1970-01-01T01:00:00Z"),
    ]

    func testBucketsAggregateStrapSamplesAndSkipZeroReadings() throws {
        // Seeded store already holds my-whoop samples at ts 100 (70 bpm) and 101 (72 bpm).
        let url = try TemporaryDatabase.seeded()
        try DatabaseQueue(path: url.path).write { db in
            try db.execute(sql: """
                INSERT INTO hrSample(deviceId, ts, bpm)
                VALUES ('my-whoop', 400, 90), ('my-whoop', 401, 0), ('another-strap', 102, 150)
                """)
        }
        let dispatcher = NoopToolDispatcher(configuration: LocalAccessConfiguration(databasePath: url.path))

        let payload = try dispatcher.dispatch(name: "heart_rate_series", arguments: [
            "from": .string("1970-01-01T00:00:00Z"),
            "to": .string("1970-01-01T00:10:00Z"),
            "bucket_minutes": .int(5),
        ])
        let object = try XCTUnwrap(payload.objectValue)

        XCTAssertEqual(object["bucketMinutes"], .int(5))
        XCTAssertEqual(object["returned"], .int(2))
        let summary = try XCTUnwrap(object["summary"]?.objectValue)
        XCTAssertEqual(summary["samples"], .int(3))
        XCTAssertEqual(summary["minBpm"], .int(70))
        XCTAssertEqual(summary["maxBpm"], .int(90))
        XCTAssertEqual(summary["avgBpm"], .double(77.3))
        guard case .array(let buckets)? = object["buckets"] else { return XCTFail("Expected buckets array") }
        XCTAssertEqual(buckets.first?.objectValue?["avgBpm"], .double(71))
        XCTAssertEqual(buckets.first?.objectValue?["samples"], .int(2))
        XCTAssertEqual(buckets.last?.objectValue?["samples"], .int(1))
    }

    func testWideWindowsWidenTheBucketToStayBounded() throws {
        let url = try TemporaryDatabase.seeded()
        let dispatcher = NoopToolDispatcher(configuration: LocalAccessConfiguration(databasePath: url.path))

        let payload = try dispatcher.dispatch(name: "heart_rate_series", arguments: [
            "from": .string("1970-01-01T00:00:00Z"),
            "hours": .int(168),
            "bucket_minutes": .int(1),
        ])

        // 168 h / 2000 buckets = 5.04 min, so one-minute buckets widen to six.
        XCTAssertEqual(payload.objectValue?["bucketMinutes"], .int(6))
    }

    func testWindowDefaultsLocalTimesAndBounds() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let trailing = try heartRateWindow(from: nil, to: nil, hours: 24, now: now, timeZone: utc)
        XCTAssertEqual(trailing.from, now.addingTimeInterval(-86_400))
        XCTAssertEqual(trailing.to, now)

        // 07:30 on 9 Oct 2026 in Auckland is NZDT (UTC+13).
        let auckland = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        let morning = try heartRateWindow(from: "2026-10-09T07:30", to: nil, hours: 2, timeZone: auckland)
        XCTAssertEqual(morning.from, ISO8601DateFormatter().date(from: "2026-10-08T18:30:00Z"))
        XCTAssertEqual(morning.to.timeIntervalSince(morning.from), 7_200)

        let day = try heartRateWindow(from: "2026-10-09", to: "2026-10-10", hours: 24, timeZone: utc)
        XCTAssertEqual(day.to.timeIntervalSince(day.from), 86_400)

        XCTAssertThrowsError(try heartRateWindow(from: "2026-10-10", to: "2026-10-09", hours: 24, timeZone: utc))
        XCTAssertThrowsError(try heartRateWindow(from: "2026-10-01", to: "2026-10-09", hours: 24, timeZone: utc))
        XCTAssertThrowsError(try heartRateWindow(from: "yesterday", to: nil, hours: 24, timeZone: utc))
    }

    func testReplacedSnapshotIsReopenedOnTheNextCall() throws {
        let url = try TemporaryDatabase.seeded()
        let dispatcher = NoopToolDispatcher(configuration: LocalAccessConfiguration(databasePath: url.path))
        let before = try dispatcher.dispatch(name: "heart_rate_series", arguments: firstHour)
        XCTAssertEqual(before.objectValue?["summary"]?.objectValue?["samples"], .int(2))

        // A phone pull writes a fresh file and renames it over the old path.
        let replacement = try TemporaryDatabase.seeded()
        try DatabaseQueue(path: replacement.path).write { db in
            try db.execute(sql: "INSERT INTO hrSample(deviceId, ts, bpm) VALUES ('my-whoop', 200, 80)")
        }
        XCTAssertEqual(rename(replacement.path, url.path), 0)

        let after = try dispatcher.dispatch(name: "heart_rate_series", arguments: firstHour)
        XCTAssertEqual(after.objectValue?["summary"]?.objectValue?["samples"], .int(3))
    }

    func testCLIParsesHeartRateFlags() throws {
        let parsed = try NoopCLIQuery.parse(arguments: [
            "heart_rate_series", "--from", "2026-10-09T07:30", "--hours", "2", "--bucket-minutes", "10",
        ])
        XCTAssertEqual(parsed.arguments["from"], .string("2026-10-09T07:30"))
        XCTAssertEqual(parsed.arguments["hours"], .int(2))
        XCTAssertEqual(parsed.arguments["bucket_minutes"], .int(10))

        XCTAssertThrowsError(try NoopCLIQuery.parse(arguments: ["heart_rate_series", "--days", "7"]))
        XCTAssertThrowsError(try NoopCLIQuery.parse(arguments: ["sleep_summary", "--from", "2026-10-09"]))
    }
}
