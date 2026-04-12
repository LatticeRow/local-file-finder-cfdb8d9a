import OSLog

struct AppLogger {
    private let logger: Logger

    init(subsystem: String, category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    func info(_ message: String) {
        logger.log(level: .info, "\(message, privacy: .private(mask: .hash))")
    }
}
