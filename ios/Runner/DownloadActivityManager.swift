import ActivityKit
import Foundation
import SwiftUI

struct DownloadTaskInfo {
    let taskId: String
    let displayName: String
    var downloadedBytes: Int64
    var totalBytes: Int64
    var speed: Double
    var status: String // downloading, paused
}

@available(iOS 16.2, *)
class DownloadActivityManager {
    static let shared = DownloadActivityManager()

    private var activity: Activity<DownloadActivityAttributes>?
    private var tasks: [String: DownloadTaskInfo] = [:]
    private var lastUpdateTime: Date?
    private let updateInterval: TimeInterval = 0.5
    private let lock = NSLock()

    private init() {}

    func addTask(taskId: String, displayName: String, totalBytes: Int64) {
        lock.lock()
        tasks[taskId] = DownloadTaskInfo(
            taskId: taskId,
            displayName: displayName,
            downloadedBytes: 0,
            totalBytes: totalBytes,
            speed: 0,
            status: "downloading"
        )
        lock.unlock()

        startOrUpdateActivity()
    }

    func updateTask(taskId: String, downloadedBytes: Int64, totalBytes: Int64, speed: Double, status: String) {
        lock.lock()
        if var task = tasks[taskId] {
            task.downloadedBytes = downloadedBytes
            task.totalBytes = totalBytes
            task.speed = speed
            task.status = status
            tasks[taskId] = task
        }
        lock.unlock()

        throttledUpdate()
    }

    func removeTask(taskId: String) {
        lock.lock()
        tasks.removeValue(forKey: taskId)
        let isEmpty = tasks.isEmpty
        lock.unlock()

        if isEmpty {
            endActivity()
        } else {
            startOrUpdateActivity()
        }
    }

    private func throttledUpdate() {
        let now = Date()
        lock.lock()
        let shouldUpdate = lastUpdateTime == nil || now.timeIntervalSince(lastUpdateTime!) >= updateInterval
        if shouldUpdate {
            lastUpdateTime = now
        }
        lock.unlock()

        if shouldUpdate {
            startOrUpdateActivity()
        }
    }

    private func startOrUpdateActivity() {
        lock.lock()
        let taskList = Array(tasks.values)
        lock.unlock()

        guard !taskList.isEmpty else { return }

        let activeCount = taskList.filter { $0.status == "downloading" }.count
        let totalCount = taskList.count
        let totalDownloaded = taskList.reduce(0) { $0 + $1.downloadedBytes }
        let totalSize = taskList.reduce(0) { $0 + $1.totalBytes }
        let totalSpeed = taskList.filter { $0.status == "downloading" }.reduce(0) { $0 + $1.speed }
        let progress = totalSize > 0 ? Double(totalDownloaded) / Double(totalSize) : 0

        let currentTask = taskList.first { $0.status == "downloading" } ?? taskList.first
        let currentTaskName = currentTask?.displayName ?? ""

        let allPaused = taskList.allSatisfy { $0.status == "paused" }
        let status = allPaused ? "paused" : "downloading"

        let state = DownloadActivityAttributes.ContentState(
            activeTaskCount: activeCount,
            totalTaskCount: totalCount,
            totalProgress: progress,
            totalDownloadedBytes: totalDownloaded,
            totalBytes: totalSize,
            totalSpeed: totalSpeed,
            currentTaskName: currentTaskName,
            status: status
        )

        if activity == nil {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                NSLog("[LiveActivity] Activities not enabled")
                return
            }

            do {
                let attributes = DownloadActivityAttributes()
                activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
                NSLog("[LiveActivity] Started aggregated activity")
            } catch {
                NSLog("[LiveActivity] Failed to start activity: \(error)")
            }
        } else {
            Task {
                await activity?.update(
                    ActivityContent(state: state, staleDate: nil),
                    alertConfiguration: nil
                )
            }
        }
    }

    private func endActivity() {
        guard let activity = activity else { return }

        let finalState = DownloadActivityAttributes.ContentState(
            activeTaskCount: 0,
            totalTaskCount: 0,
            totalProgress: 1.0,
            totalDownloadedBytes: 0,
            totalBytes: 0,
            totalSpeed: 0,
            currentTaskName: "",
            status: "completed"
        )

        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            NSLog("[LiveActivity] Ended aggregated activity")
        }

        self.activity = nil
        lastUpdateTime = nil
    }

    func endAllActivities() {
        lock.lock()
        tasks.removeAll()
        lock.unlock()
        endActivity()
    }
}

class DownloadActivityManagerWrapper: NSObject {
    @objc static let shared = DownloadActivityManagerWrapper()

    private override init() {
        super.init()
    }

    @objc func addTask(taskId: String, displayName: String, totalBytes: Int64) {
        if #available(iOS 16.2, *) {
            DownloadActivityManager.shared.addTask(taskId: taskId, displayName: displayName, totalBytes: totalBytes)
        }
    }

    @objc func updateTask(taskId: String, downloadedBytes: Int64, totalBytes: Int64, speed: Double, status: String) {
        if #available(iOS 16.2, *) {
            DownloadActivityManager.shared.updateTask(taskId: taskId, downloadedBytes: downloadedBytes, totalBytes: totalBytes, speed: speed, status: status)
        }
    }

    @objc func removeTask(taskId: String) {
        if #available(iOS 16.2, *) {
            DownloadActivityManager.shared.removeTask(taskId: taskId)
        }
    }

    @objc func endAllActivities() {
        if #available(iOS 16.2, *) {
            DownloadActivityManager.shared.endAllActivities()
        }
    }
}
