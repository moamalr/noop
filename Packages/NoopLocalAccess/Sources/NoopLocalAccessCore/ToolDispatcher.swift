import Foundation

/// The single read-only dispatch surface shared by MCP and the direct CLI transport.
public final class NoopToolDispatcher {
    private let configuration: LocalAccessConfiguration
    private var dataAccess: NoopDataAccess?
    /// Inode of the file `dataAccess` was opened from. A snapshot that is replaced on disk (a new file
    /// renamed over the old path, as a phone pull does) gets a new inode, so the next call reopens it
    /// rather than serving the replaced file for the rest of a long-lived MCP session. A live store
    /// written in place keeps its inode, and its open read connection already sees new commits.
    private var openedInode: UInt64?

    public init(configuration: LocalAccessConfiguration = .environment()) {
        self.configuration = configuration
    }

    public static let toolNames = [
        "health_snapshot",
        "metric_series",
        "data_freshness",
        "sleep_summary",
        "workout_summary",
        "heart_rate_series",
    ]

    public func dispatch(name: String, arguments: [String: JSONValue] = [:]) throws -> JSONValue {
        switch name {
        case "health_snapshot":
            return try data().healthSnapshot(days: boundedDays(arguments["days"], default: 14, max: 120))
        case "metric_series":
            guard let key = arguments["key"]?.stringValue else {
                throw LocalAccessError.invalidParams("metric_series requires key")
            }
            return try data().metricSeries(
                key: key,
                source: arguments["source"]?.stringValue ?? "my-whoop",
                days: boundedDays(arguments["days"], default: 90, max: 4000),
                fromDay: arguments["from_day"]?.stringValue,
                toDay: arguments["to_day"]?.stringValue,
                limit: boundedLimit(arguments["limit"], default: 500, max: 2000)
            )
        case "data_freshness":
            return try data().freshness()
        case "sleep_summary":
            return try data().sleepSummary(days: boundedDays(arguments["days"], default: 30, max: 4000))
        case "workout_summary":
            return try data().workoutSummary(days: boundedDays(arguments["days"], default: 90, max: 4000))
        case "heart_rate_series":
            let window = try heartRateWindow(
                from: arguments["from"]?.stringValue,
                to: arguments["to"]?.stringValue,
                hours: boundedLimit(arguments["hours"], default: 24, max: maxHeartRateWindowHours)
            )
            return try data().heartRateSeries(
                from: window.from,
                to: window.to,
                bucketMinutes: boundedLimit(arguments["bucket_minutes"], default: 5, max: 60)
            )
        default:
            throw LocalAccessError.toolNotFound(name)
        }
    }

    public func resourcePayload(uri: String) throws -> JSONValue {
        switch uri {
        case "noop://health/snapshot":
            return try dispatch(name: "health_snapshot", arguments: ["days": .int(14)])
        case "noop://data/freshness":
            return try dispatch(name: "data_freshness")
        case "noop://metrics/catalog":
            return NoopDataAccess.metricCatalog()
        case "noop://sources":
            return NoopDataAccess.sources()
        default:
            throw LocalAccessError.resourceNotFound(uri)
        }
    }

    private func data() throws -> NoopDataAccess {
        let inode = currentInode()
        if let dataAccess, inode == openedInode { return dataAccess }
        do {
            let access = try NoopDataAccess.open(configuration: configuration)
            dataAccess = access
            openedInode = inode
            return access
        } catch let error as LocalAccessError {
            throw error
        } catch {
            throw LocalAccessError.databaseUnavailable("NOOP database is not available: \(error)")
        }
    }

    private func currentInode() -> UInt64? {
        guard let path = try? DatabasePathResolver.resolve(configuration: configuration),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        else { return nil }
        return (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
    }
}
