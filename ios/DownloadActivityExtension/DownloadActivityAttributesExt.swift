import ActivityKit
import Foundation

struct DownloadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var activeTaskCount: Int
        var totalTaskCount: Int
        var totalProgress: Double
        var totalDownloadedBytes: Int64
        var totalBytes: Int64
        var totalSpeed: Double
        var currentTaskName: String
        var status: String // downloading, paused, completed
    }

    var id: String = "download"
}
