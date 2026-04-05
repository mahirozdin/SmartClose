import Foundation

struct WindowInfo: Equatable {
    let role: String?
    let subrole: String?
    let isMinimized: Bool?
    let isVisible: Bool?
    let title: String?
}

struct WindowCountResult: Equatable {
    let count: Int
    let ambiguous: Bool
    let ignoredCount: Int
    let reasons: [String]
}
