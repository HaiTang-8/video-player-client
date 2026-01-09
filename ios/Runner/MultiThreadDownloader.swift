import Foundation
import ActivityKit
import UIKit

struct DownloadProgress {
    let taskId: String
    let downloadedBytes: Int64
    let totalBytes: Int64
    let speed: Double
    let activeThreads: Int
    let status: String
    let error: String?

    func toDict() -> [String: Any?] {
        return [
            "taskId": taskId,
            "downloadedBytes": downloadedBytes,
            "totalBytes": totalBytes,
            "speed": speed,
            "activeThreads": activeThreads,
            "status": status,
            "error": error
        ]
    }
}

class MultiThreadDownloader: NSObject {
    static let defaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36 Edg/87.0.664.57"
    static let shared = MultiThreadDownloader(threadCount: 8)

    private let threadCount: Int
    private var downloadTasks: [String: BackgroundDownloadTask] = [:]
    private var backgroundSession: URLSession!
    private var backgroundCompletionHandler: (() -> Void)?
    private let lock = NSLock()

    override init() {
        self.threadCount = 8
        super.init()
        setupBackgroundSession()
    }

    init(threadCount: Int) {
        self.threadCount = threadCount
        super.init()
        setupBackgroundSession()
    }

    private func setupBackgroundSession() {
        let config = URLSessionConfiguration.background(withIdentifier: "com.mediaserver.mediaPlayer.backgroundDownload")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.shouldUseExtendedBackgroundIdleMode = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 86400 * 7
        config.httpMaximumConnectionsPerHost = 6

        backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        NSLog("[iOS-Downloader] Background session initialized")
    }

    func handleBackgroundSessionCompletion(_ completionHandler: @escaping () -> Void) {
        backgroundCompletionHandler = completionHandler
    }

    func startDownload(
        taskId: String,
        url: String,
        savePath: String,
        headers: [String: String],
        displayName: String? = nil,
        onProgress: @escaping (DownloadProgress) -> Void
    ) {
        let task = BackgroundDownloadTask(
            taskId: taskId,
            url: url,
            savePath: savePath,
            headers: headers,
            threadCount: threadCount,
            session: backgroundSession,
            displayName: displayName,
            onProgress: onProgress
        )

        lock.lock()
        downloadTasks[taskId] = task
        lock.unlock()

        task.start()
    }

    func pauseDownload(taskId: String) {
        lock.lock()
        let task = downloadTasks[taskId]
        lock.unlock()
        task?.pause()
    }

    func resumeDownload(taskId: String) {
        lock.lock()
        let task = downloadTasks[taskId]
        lock.unlock()
        task?.resume()
    }

    func cancelDownload(taskId: String) {
        lock.lock()
        let task = downloadTasks[taskId]
        downloadTasks.removeValue(forKey: taskId)
        lock.unlock()
        task?.cancel()
    }

    func getTask(byURLSessionTaskId taskId: Int) -> BackgroundDownloadTask? {
        lock.lock()
        defer { lock.unlock() }
        for (_, task) in downloadTasks {
            if task.hasURLSessionTask(taskId) {
                return task
            }
        }
        return nil
    }

    func removeTask(_ taskId: String) {
        lock.lock()
        downloadTasks.removeValue(forKey: taskId)
        lock.unlock()
    }

    func handleAppWillResignActive() {}
    func handleAppDidBecomeActive() {}
}

// MARK: - URLSessionDelegate
extension MultiThreadDownloader: URLSessionDelegate, URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let task = getTask(byURLSessionTaskId: downloadTask.taskIdentifier) else {
            NSLog("[iOS-Downloader] No task found for download task %d", downloadTask.taskIdentifier)
            return
        }
        task.handleDownloadComplete(downloadTask: downloadTask, location: location)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let task = getTask(byURLSessionTaskId: downloadTask.taskIdentifier) else { return }
        task.handleProgress(downloadTask: downloadTask, bytesWritten: bytesWritten, totalBytesWritten: totalBytesWritten)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            NSLog("[iOS-Downloader] Task %d error: %@", task.taskIdentifier, error.localizedDescription)
            if let downloadTask = getTask(byURLSessionTaskId: task.taskIdentifier) {
                downloadTask.handleError(sessionTask: task, error: error)
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        NSLog("[iOS-Downloader] Background session events finished")
        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }
}

// MARK: - BackgroundDownloadTask
class BackgroundDownloadTask {
    let taskId: String
    let url: String
    let savePath: String
    let headers: [String: String]
    let threadCount: Int
    let onProgress: (DownloadProgress) -> Void
    let displayName: String?
    var enableLiveActivity: Bool = true

    private weak var session: URLSession?
    private var urlSessionTasks: [Int: URLSessionDownloadTask] = [:]
    private var chunkInfo: [Int: ChunkInfo] = [:]
    private var totalBytes: Int64 = 0
    private var downloadedBytes: Int64 = 0
    private var completedChunks: Int = 0
    private var totalChunks: Int = 0
    private var cancelled = false
    private(set) var isPaused = false
    private(set) var isFinished = false
    private var lastUpdateTime: Date?
    private var lastBytes: Int64 = 0
    private var smoothedSpeed: Double = 0
    private let lock = NSLock()
    private var progressTimer: Timer?
    private var tempDirectory: String = ""

    private var is115Link: Bool {
        return url.contains("115cdn.net") || url.contains("cdnfhnfile") || url.contains("115.com")
    }

    private var effectiveThreadCount: Int {
        return is115Link ? 1 : threadCount
    }

    private var liveActivityFileName: String {
        return displayName ?? (savePath as NSString).lastPathComponent
    }

    struct ChunkInfo {
        let index: Int
        let start: Int64
        let end: Int64
        var downloadedBytes: Int64 = 0
        var completed: Bool = false
        var tempFile: String = ""
    }

    init(taskId: String, url: String, savePath: String, headers: [String: String],
         threadCount: Int, session: URLSession, displayName: String? = nil, onProgress: @escaping (DownloadProgress) -> Void) {
        self.taskId = taskId
        self.url = url
        self.savePath = savePath
        self.headers = headers
        self.threadCount = threadCount
        self.session = session
        self.displayName = displayName
        self.onProgress = onProgress
    }

    func hasURLSessionTask(_ taskId: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return urlSessionTasks[taskId] != nil
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.doDownload()
        }
    }

    func pause() {
        lock.lock()
        isPaused = true
        let tasks = Array(urlSessionTasks.values)
        lock.unlock()

        for task in tasks {
            task.suspend()
        }

        updateLiveActivity(status: "paused")
    }

    func resume() {
        lock.lock()
        isPaused = false
        let tasks = Array(urlSessionTasks.values)
        lock.unlock()

        for task in tasks {
            task.resume()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let tasks = Array(urlSessionTasks.values)
        lock.unlock()

        for task in tasks {
            task.cancel()
        }

        DispatchQueue.main.async { [weak self] in
            self?.progressTimer?.invalidate()
        }

        if enableLiveActivity {
            DownloadActivityManagerWrapper.shared.removeTask(taskId: taskId)
        }

        cleanupTempFiles()
    }

    private func doDownload() {
        var effectiveHeaders = headers
        if effectiveHeaders["User-Agent"] == nil {
            effectiveHeaders["User-Agent"] = MultiThreadDownloader.defaultUserAgent
        }

        guard let fileSize = getFileSize(url: url, headers: effectiveHeaders) else {
            onProgress(DownloadProgress(taskId: taskId, downloadedBytes: 0, totalBytes: 0,
                                        speed: 0, activeThreads: 0, status: "failed", error: "Cannot get file size"))
            return
        }

        totalBytes = fileSize
        NSLog("[iOS-Downloader] File size: %lld, threads: %d (is115: %@)", fileSize, effectiveThreadCount, is115Link ? "true" : "false")

        if enableLiveActivity {
            DownloadActivityManagerWrapper.shared.addTask(taskId: taskId, displayName: liveActivityFileName, totalBytes: fileSize)
        }

        let fileManager = FileManager.default
        let directory = (savePath as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)

        tempDirectory = (directory as NSString).appendingPathComponent(".download_\(taskId)")
        try? fileManager.createDirectory(atPath: tempDirectory, withIntermediateDirectories: true)

        let chunkSize = (fileSize + Int64(effectiveThreadCount) - 1) / Int64(effectiveThreadCount)
        var offset: Int64 = 0
        var index = 0

        while offset < fileSize {
            let end = min(offset + chunkSize - 1, fileSize - 1)
            var info = ChunkInfo(index: index, start: offset, end: end)
            info.tempFile = (tempDirectory as NSString).appendingPathComponent("chunk_\(index).tmp")

            lock.lock()
            chunkInfo[index] = info
            lock.unlock()

            offset = end + 1
            index += 1
        }

        totalChunks = index
        NSLog("[iOS-Downloader] Created %d chunks", totalChunks)

        DispatchQueue.main.async { [weak self] in
            self?.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.reportProgress()
            }
        }

        for i in 0..<totalChunks {
            lock.lock()
            let isCancelled = cancelled
            lock.unlock()

            if isCancelled { break }
            startChunkDownload(index: i, headers: effectiveHeaders)
        }
    }

    private func startChunkDownload(index: Int, headers: [String: String]) {
        guard let urlObj = URL(string: url),
              let session = session else {
            markChunkCompleted(index: index, success: false)
            return
        }

        lock.lock()
        guard let info = chunkInfo[index] else {
            lock.unlock()
            return
        }
        lock.unlock()

        var request = URLRequest(url: urlObj)
        request.setValue("bytes=\(info.start)-\(info.end)", forHTTPHeaderField: "Range")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let task = session.downloadTask(with: request)

        lock.lock()
        urlSessionTasks[task.taskIdentifier] = task
        chunkInfo[index]?.downloadedBytes = 0
        lock.unlock()

        task.taskDescription = "\(taskId)|\(index)"
        task.resume()

        NSLog("[iOS-Downloader] Started chunk %d, task %d", index, task.taskIdentifier)
    }

    func handleProgress(downloadTask: URLSessionDownloadTask, bytesWritten: Int64, totalBytesWritten: Int64) {
        guard let desc = downloadTask.taskDescription,
              let index = parseChunkIndex(from: desc) else { return }

        lock.lock()
        if var info = chunkInfo[index] {
            let prevBytes = info.downloadedBytes
            info.downloadedBytes = totalBytesWritten
            chunkInfo[index] = info
            downloadedBytes += (totalBytesWritten - prevBytes)
        }
        let currentBytes = downloadedBytes
        let total = totalBytes
        lock.unlock()

        updateLiveActivityFromDelegate(downloadedBytes: currentBytes, totalBytes: total)
    }

    private var lastDelegateUpdateTime: Date?

    private func updateLiveActivityFromDelegate(downloadedBytes: Int64, totalBytes: Int64) {
        guard enableLiveActivity, totalBytes > 0 else { return }

        let now = Date()
        if let lastUpdate = lastDelegateUpdateTime, now.timeIntervalSince(lastUpdate) < 1.0 {
            return
        }
        lastDelegateUpdateTime = now

        DownloadActivityManagerWrapper.shared.updateTask(
            taskId: taskId,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            speed: smoothedSpeed,
            status: "downloading"
        )
    }

    func handleDownloadComplete(downloadTask: URLSessionDownloadTask, location: URL) {
        guard let desc = downloadTask.taskDescription,
              let index = parseChunkIndex(from: desc) else { return }

        lock.lock()
        guard var info = chunkInfo[index] else {
            lock.unlock()
            return
        }

        let tempFile = info.tempFile
        lock.unlock()

        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: tempFile) {
                try fileManager.removeItem(atPath: tempFile)
            }
            try fileManager.moveItem(at: location, to: URL(fileURLWithPath: tempFile))

            lock.lock()
            info.completed = true
            chunkInfo[index] = info
            lock.unlock()

            NSLog("[iOS-Downloader] Chunk %d completed, saved to %@", index, tempFile)
            markChunkCompleted(index: index, success: true)
        } catch {
            NSLog("[iOS-Downloader] Chunk %d failed to save: %@", index, error.localizedDescription)
            markChunkCompleted(index: index, success: false)
        }
    }

    func handleError(sessionTask: URLSessionTask, error: Error) {
        guard let desc = sessionTask.taskDescription,
              let index = parseChunkIndex(from: desc) else { return }

        NSLog("[iOS-Downloader] Chunk %d error: %@", index, error.localizedDescription)
        markChunkCompleted(index: index, success: false)
    }

    private func parseChunkIndex(from description: String) -> Int? {
        let parts = description.split(separator: "|")
        guard parts.count == 2, let index = Int(parts[1]) else { return nil }
        return index
    }

    private func markChunkCompleted(index: Int, success: Bool) {
        lock.lock()
        completedChunks += 1
        let allDone = completedChunks >= totalChunks
        let finished = isFinished
        lock.unlock()

        if allDone && !finished {
            finishDownload()
        }
    }

    private func finishDownload() {
        lock.lock()
        if isFinished {
            lock.unlock()
            return
        }
        isFinished = true
        let isCancelled = cancelled
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.progressTimer?.invalidate()
        }

        if isCancelled {
            onProgress(DownloadProgress(taskId: taskId, downloadedBytes: downloadedBytes, totalBytes: totalBytes,
                                        speed: 0, activeThreads: 0, status: "cancelled", error: nil))
            if enableLiveActivity {
                DownloadActivityManagerWrapper.shared.removeTask(taskId: taskId)
            }
            cleanupTempFiles()
            MultiThreadDownloader.shared.removeTask(taskId)
            return
        }

        let success = mergeChunks()

        if success {
            onProgress(DownloadProgress(taskId: taskId, downloadedBytes: totalBytes, totalBytes: totalBytes,
                                        speed: 0, activeThreads: 0, status: "completed", error: nil))
            if enableLiveActivity {
                DownloadActivityManagerWrapper.shared.removeTask(taskId: taskId)
            }
        } else {
            onProgress(DownloadProgress(taskId: taskId, downloadedBytes: downloadedBytes, totalBytes: totalBytes,
                                        speed: 0, activeThreads: 0, status: "failed", error: "Failed to merge chunks"))
            if enableLiveActivity {
                DownloadActivityManagerWrapper.shared.removeTask(taskId: taskId)
            }
        }

        cleanupTempFiles()
        MultiThreadDownloader.shared.removeTask(taskId)
    }

    private func mergeChunks() -> Bool {
        let fileManager = FileManager.default

        lock.lock()
        let chunks = chunkInfo.sorted { $0.key < $1.key }
        lock.unlock()

        for (_, info) in chunks {
            if !info.completed || !fileManager.fileExists(atPath: info.tempFile) {
                NSLog("[iOS-Downloader] Chunk %d not completed or missing", info.index)
                return false
            }
        }

        do {
            if fileManager.fileExists(atPath: savePath) {
                try fileManager.removeItem(atPath: savePath)
            }

            fileManager.createFile(atPath: savePath, contents: nil)
            guard let outputHandle = FileHandle(forWritingAtPath: savePath) else {
                NSLog("[iOS-Downloader] Cannot open output file")
                return false
            }

            defer { outputHandle.closeFile() }

            for (_, info) in chunks {
                let data = try Data(contentsOf: URL(fileURLWithPath: info.tempFile))
                outputHandle.write(data)
            }

            NSLog("[iOS-Downloader] Merged %d chunks to %@", chunks.count, savePath)
            return true
        } catch {
            NSLog("[iOS-Downloader] Merge error: %@", error.localizedDescription)
            return false
        }
    }

    private func cleanupTempFiles() {
        let fileManager = FileManager.default
        if !tempDirectory.isEmpty && fileManager.fileExists(atPath: tempDirectory) {
            try? fileManager.removeItem(atPath: tempDirectory)
        }
    }

    private func reportProgress() {
        let now = Date()

        lock.lock()
        let currentBytes = downloadedBytes
        let paused = isPaused
        let total = totalBytes
        let activeCount = urlSessionTasks.count
        lock.unlock()

        guard let lastTime = lastUpdateTime else {
            lastUpdateTime = now
            lastBytes = currentBytes
            onProgress(DownloadProgress(
                taskId: taskId,
                downloadedBytes: currentBytes,
                totalBytes: total,
                speed: 0,
                activeThreads: activeCount,
                status: paused ? "paused" : "downloading",
                error: nil
            ))
            return
        }

        let elapsed = now.timeIntervalSince(lastTime)
        if elapsed >= 0.4 {
            let bytesDiff = currentBytes - lastBytes
            let instantSpeed = Double(bytesDiff) / elapsed

            if smoothedSpeed == 0 {
                smoothedSpeed = instantSpeed
            } else {
                smoothedSpeed = 0.3 * instantSpeed + 0.7 * smoothedSpeed
            }

            lastUpdateTime = now
            lastBytes = currentBytes

            onProgress(DownloadProgress(
                taskId: taskId,
                downloadedBytes: currentBytes,
                totalBytes: total,
                speed: smoothedSpeed,
                activeThreads: activeCount,
                status: paused ? "paused" : "downloading",
                error: nil
            ))

            updateLiveActivity(status: paused ? "paused" : "downloading")
        }
    }

    private func updateLiveActivity(status: String) {
        if enableLiveActivity {
            DownloadActivityManagerWrapper.shared.updateTask(
                taskId: taskId,
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes,
                speed: status == "paused" ? 0 : smoothedSpeed,
                status: status
            )
        }
    }

    private func getFileSize(url: String, headers: [String: String]) -> Int64? {
        guard let urlObj = URL(string: url) else { return nil }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        let tempSession = URLSession(configuration: config)

        var request = URLRequest(url: urlObj)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var fileSize: Int64?

        let task = tempSession.dataTask(with: request) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse,
               let contentRange = httpResponse.allHeaderFields["Content-Range"] as? String {
                if let match = contentRange.range(of: #"/(\d+)"#, options: .regularExpression) {
                    let sizeStr = String(contentRange[match]).dropFirst()
                    fileSize = Int64(sizeStr)
                }
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        tempSession.finishTasksAndInvalidate()

        if fileSize != nil { return fileSize }

        var headRequest = URLRequest(url: urlObj)
        headRequest.httpMethod = "HEAD"
        for (key, value) in headers {
            headRequest.setValue(value, forHTTPHeaderField: key)
        }

        let tempSession2 = URLSession(configuration: config)
        let headTask = tempSession2.dataTask(with: headRequest) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                fileSize = httpResponse.expectedContentLength
            }
            semaphore.signal()
        }
        headTask.resume()
        semaphore.wait()
        tempSession2.finishTasksAndInvalidate()

        return fileSize
    }
}
