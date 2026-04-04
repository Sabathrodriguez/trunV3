import OSLog

/// Central logging namespace. Use these loggers instead of print() throughout the app.
/// Filter logs in Console.app by subsystem "com.trun.app" and a specific category.
///
/// Log level guide:
///   .debug  — routine state transitions (only visible in debug builds / Console.app)
///   .info   — significant milestones (run started, route saved, auth succeeded)
///   .error  — recoverable failures (Firebase returned an error, file write failed)
///   .fault  — unexpected states that should never happen (programmer errors)
enum AppLogger {
    static let location    = Logger(subsystem: "com.trun.app", category: "location")
    static let run         = Logger(subsystem: "com.trun.app", category: "run")
    static let routes      = Logger(subsystem: "com.trun.app", category: "routes")
    static let network     = Logger(subsystem: "com.trun.app", category: "network")
    static let health      = Logger(subsystem: "com.trun.app", category: "health")
    static let strava      = Logger(subsystem: "com.trun.app", category: "strava")
    static let persistence = Logger(subsystem: "com.trun.app", category: "persistence")
    static let liveActivity = Logger(subsystem: "com.trun.app", category: "liveActivity")
    static let auth        = Logger(subsystem: "com.trun.app", category: "auth")
    static let cache       = Logger(subsystem: "com.trun.app", category: "cache")
}
