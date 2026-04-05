import os.log

enum Log {
    static let subsystem = "com.smartclose.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let interception = Logger(subsystem: subsystem, category: "interception")
    static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let decision = Logger(subsystem: subsystem, category: "decision")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
}
