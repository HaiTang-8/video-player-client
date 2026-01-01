import Foundation

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

class DownloadChunk {
    let index: Int
    let start: Int64
    let end: Int64
    var downloaded: Int64 = 0
    var currentOffset: Int64
    var completed: Bool = false
    var failed: Bool = false
    var taskIdentifier: Int = 0

    init(index: Int, start: Int64, end: Int64) {
        self.index = index
        self.start = start
        self.end = end
        self.currentOffset = start
    }

    var length: Int64 { end - start + 1 }
}

class MultiThreadDownloader: NSObject {
    static let defaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36 Edg/87.0.664.57"

    private let threadCount: Int
    private var downloadTasks: [String: DownloadTask] = [:]

    init(threadCount: Int = 8) {
        self.threadCount = threadCount
        super.init()
    }

    func startDownload(
        taskId: String,
        url: String,
        savePath: String,
        headers: [String: String],
        onProgress: @escaping (DownloadProgress) -> Void
    ) {
        let task = DownloadTask(
            taskId: taskId,
            url: url,
            savePath: savePath,
            headers: headers,
            threadCount: threadCount,
            onProgress: onProgress
        )
        downloadTasks[taskId] = task
        task.start()
    }

    func pauseDownload(taskId: String) {
        downloadTasks[taskId]?.pause()
    }

    func resumeDownload(taskId: String) {
        downloadTasks[taskId]?.resume()
    }

    func cancelDownload(taskId: String) {
        downloadTasks[taskId]?.cancel()
        downloadTasks.removeValue(forKey: taskId)
    }
}

class DownloadTask: NSObject, URLSessionDataDelegate {
    let taskId: String
    let url: String
    let savePath: String
    let headers: [String: String]
    let threadCount: Int
    let onProgress: (DownloadProgress) -> Void

    private var fileHandle: FileHandle?
    private var chunks: [DownloadChunk] = []
    private var chunkByTaskId: [Int: DownloadChunk] = [:]
    private var totalBytes: Int64 = 0
    private var downloadedBytes: Int64 = 0
    private var activeThreads: Int = 0
    private var completedChunks: Int = 0
    private var cancelled = false
    private var paused = false
    private var finished = false
    private var lastUpdateTime: Date?
    private var lastBytes: Int64 = 0
    private var smoothedSpeed: Double = 0
    private var progressTimer: Timer?
    private let lock = NSLock()
    private var session: URLSession?
    private var dataTasks: [URLSessionDataTask] = []

    // 检测是否是 115 链接
    private var is115Link: Bool {
        return url.contains("115cdn.net") || url.contains("cdnfhnfile") || url.contains("115.com")
    }

    // 115 链接只能用单线程
    private var effectiveThreadCount: Int {
        return is115Link ? 1 : threadCount
    }

    init(taskId: String, url: String, savePath: String, headers: [String: String],
         threadCount: Int, onProgress: @escaping (DownloadProgress) -> Void) {
        self.taskId = taskId
        self.url = url
        self.savePath = savePath
        self.headers = headers
        self.threadCount = threadCount
        self.onProgress = onProgress
        super.init()
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.doDownload()
        }
    }

    func pause() {
        lock.lock()
        paused = true
        let tasks = dataTasks
        lock.unlock()
        tasks.forEach { $0.suspend() }
    }

    func resume() {
        lock.lock()
        paused = false
        let tasks = dataTasks
        lock.unlock()
        tasks.forEach { $0.resume() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let tasks = dataTasks
        let sess = session
        lock.unlock()

        tasks.forEach { $0.cancel() }

        DispatchQueue.main.async { [weak self] in
            self?.progressTimer?.invalidate()
        }

        lock.lock()
        fileHandle?.closeFile()
        fileHandle = nil
        lock.unlock()

        sess?.invalidateAndCancel()
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

        let fileManager = FileManager.default
        let directory = (savePath as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: savePath) {
            fileManager.createFile(atPath: savePath, contents: nil)
        }

        guard let handle = FileHandle(forWritingAtPath: savePath) else {
            onProgress(DownloadProgress(taskId: taskId, downloadedBytes: 0, totalBytes: fileSize,
                                        speed: 0, activeThreads: 0, status: "failed", error: "Cannot open file"))
            return
        }

        lock.lock()
        fileHandle = handle
        lock.unlock()

        handle.truncateFile(atOffset: UInt64(fileSize))

        let chunkSize = (fileSize + Int64(effectiveThreadCount) - 1) / Int64(effectiveThreadCount)
        var offset: Int64 = 0
        var index = 0

        while offset < fileSize {
            let end = min(offset + chunkSize - 1, fileSize - 1)
            chunks.append(DownloadChunk(index: index, start: offset, end: end))
            offset = end + 1
            index += 1
        }

        NSLog("[iOS-Downloader] Created %d chunks", chunks.count)

        // Create session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 7200
        config.httpMaximumConnectionsPerHost = effectiveThreadCount

        lock.lock()
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.reportProgress()
            }
        }

        // Start all chunks simultaneously using shared session
        for chunk in chunks {
            lock.lock()
            let isCancelled = cancelled
            lock.unlock()

            if isCancelled { break }
            startChunkDownload(chunk: chunk, headers: effectiveHeaders)
        }
    }

    private func startChunkDownload(chunk: DownloadChunk, headers: [String: String]) {
        guard let urlObj = URL(string: url) else {
            markChunkCompleted(chunk: chunk, success: false)
            return
        }

        var request = URLRequest(url: urlObj)
        request.setValue("bytes=\(chunk.start)-\(chunk.end)", forHTTPHeaderField: "Range")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        lock.lock()
        guard let sess = session else {
            lock.unlock()
            markChunkCompleted(chunk: chunk, success: false)
            return
        }

        let task = sess.dataTask(with: request)
        chunk.taskIdentifier = task.taskIdentifier
        chunkByTaskId[task.taskIdentifier] = chunk
        activeThreads += 1
        dataTasks.append(task)
        lock.unlock()

        task.resume()
    }

    private func markChunkCompleted(chunk: DownloadChunk, success: Bool) {
        lock.lock()

        // Prevent double completion
        if chunk.completed || chunk.failed {
            lock.unlock()
            return
        }

        if success {
            chunk.completed = true
        } else {
            chunk.failed = true
        }

        activeThreads = max(0, activeThreads - 1)
        completedChunks += 1
        let allDone = completedChunks >= chunks.count
        let isFinished = finished
        lock.unlock()

        NSLog("[iOS-Downloader] Chunk %d completed: %@, downloaded: %lld/%lld",
              chunk.index, success ? "true" : "false", chunk.downloaded, chunk.length)

        if allDone && !isFinished {
            finishDownload()
        }
    }

    private func finishDownload() {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let finalBytes = downloadedBytes
        let isCancelled = cancelled
        let sess = session
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.progressTimer?.invalidate()
        }

        lock.lock()
        fileHandle?.closeFile()
        fileHandle = nil
        lock.unlock()

        sess?.finishTasksAndInvalidate()

        if isCancelled {
            onProgress(DownloadProgress(taskId: taskId, downloadedBytes: finalBytes, totalBytes: totalBytes,
                                        speed: 0, activeThreads: 0, status: "cancelled", error: nil))
            return
        }

        let tolerance = Int64(Double(totalBytes) * 0.01)
        let allCompleted = finalBytes >= (totalBytes - tolerance)

        if allCompleted {
            onProgress(DownloadProgress(taskId: taskId, downloadedBytes: totalBytes, totalBytes: totalBytes,
                                        speed: 0, activeThreads: 0, status: "completed", error: nil))
        } else {
            NSLog("[iOS-Downloader] Download incomplete: %lld/%lld", finalBytes, totalBytes)
            var debugInfo = "Downloaded \(finalBytes)/\(totalBytes). "
            for chunk in chunks {
                NSLog("[iOS-Downloader] Chunk %d: downloaded=%lld, expected=%lld, completed=%@",
                      chunk.index, chunk.downloaded, chunk.length, chunk.completed ? "true" : "false")
                if !chunk.completed {
                    debugInfo += "Chunk\(chunk.index):\(chunk.downloaded)/\(chunk.length) "
                }
            }
            onProgress(DownloadProgress(taskId: taskId, downloadedBytes: finalBytes, totalBytes: totalBytes,
                                        speed: 0, activeThreads: 0, status: "failed", error: debugInfo))
        }
    }

    private func reportProgress() {
        let now = Date()

        lock.lock()
        let currentBytes = downloadedBytes
        let threads = activeThreads
        let isPaused = paused
        let total = totalBytes
        lock.unlock()

        guard let lastTime = lastUpdateTime else {
            lastUpdateTime = now
            lastBytes = currentBytes
            onProgress(DownloadProgress(
                taskId: taskId,
                downloadedBytes: currentBytes,
                totalBytes: total,
                speed: 0,
                activeThreads: threads,
                status: isPaused ? "paused" : "downloading",
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
                activeThreads: threads,
                status: isPaused ? "paused" : "downloading",
                error: nil
            ))
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

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        let chunk = chunkByTaskId[dataTask.taskIdentifier]
        lock.unlock()

        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            if statusCode != 200 && statusCode != 206 {
                NSLog("[iOS-Downloader] Chunk %d got status %d", chunk?.index ?? -1, statusCode)
                completionHandler(.cancel)
                return
            }
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard let chunk = chunkByTaskId[dataTask.taskIdentifier],
              let handle = fileHandle else {
            lock.unlock()
            return
        }

        handle.seek(toFileOffset: UInt64(chunk.currentOffset))
        handle.write(data)
        chunk.currentOffset += Int64(data.count)
        chunk.downloaded += Int64(data.count)
        downloadedBytes += Int64(data.count)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard let chunk = chunkByTaskId[task.taskIdentifier] else {
            lock.unlock()
            return
        }
        chunkByTaskId.removeValue(forKey: task.taskIdentifier)
        lock.unlock()

        if let error = error {
            // Ignore cancellation errors
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                NSLog("[iOS-Downloader] Chunk %d cancelled", chunk.index)
            } else {
                NSLog("[iOS-Downloader] Chunk %d error: %@", chunk.index, error.localizedDescription)
            }
            markChunkCompleted(chunk: chunk, success: false)
        } else {
            let success = chunk.downloaded >= chunk.length
            if !success {
                NSLog("[iOS-Downloader] Chunk %d incomplete: got %lld, expected %lld", chunk.index, chunk.downloaded, chunk.length)
            }
            markChunkCompleted(chunk: chunk, success: success)
        }
    }
}
