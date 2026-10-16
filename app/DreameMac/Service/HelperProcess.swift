import Foundation

/// Runs `dreame_helper.py` as a subprocess and exchanges JSON lines with it over stdin/stdout.
/// The process is started lazily and restarted on the next call if it exits.
actor HelperProcess {
    private let pythonURL: URL
    private let scriptURL: URL
    private let timeout: Duration

    private var process: Process?
    private var input: FileHandle?
    private var pending: [Int: CheckedContinuation<Data, any Error>] = [:]
    private var nextID = 1

    init(pythonURL: URL, scriptURL: URL, timeout: Duration = .seconds(60)) {
        self.pythonURL = pythonURL
        self.scriptURL = scriptURL
        self.timeout = timeout
    }

    func call<Params: Encodable & Sendable, Output: Decodable>(
        _ method: String,
        params: Params,
        as _: Output.Type = Output.self
    ) async throws -> Output {
        try startIfNeeded()
        let id = nextID
        nextID += 1
        var line = try JSONEncoder().encode(Request(id: id, method: method, params: params))
        line.append(0x0A)

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try input?.write(contentsOf: line)
            } catch {
                fail(id, with: .helperUnavailable(error.localizedDescription))
                return
            }
            Task { [timeout] in
                try? await Task.sleep(for: timeout)
                self.fail(id, with: .timeout)
            }
        }

        let response = try JSONDecoder().decode(Response<Output>.self, from: data)
        if let error = response.error {
            throw RobotError(code: error.code, message: error.message)
        }
        guard let result = response.result else {
            throw RobotError.other(code: "invalid_response", message: "The helper sent an empty response.")
        }
        return result
    }

    func stop() {
        process?.terminate()
    }

    private func startIfNeeded() throws {
        guard process == nil else { return }

        let process = Process()
        process.executableURL = pythonURL
        // -I: isolated mode, so nothing from the environment or working directory is imported.
        process.arguments = ["-I", scriptURL.path]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Self.logFile() ?? FileHandle.standardError

        let processID = ObjectIdentifier(process)
        process.terminationHandler = { [weak self] _ in
            Task { await self?.didTerminate(processID) }
        }
        do {
            try process.run()
        } catch {
            throw RobotError.helperUnavailable(error.localizedDescription)
        }
        self.process = process
        input = stdin.fileHandleForWriting

        // readabilityHandler runs on a background queue; the stream keeps the chunks in order.
        let (chunks, continuation) = AsyncStream.makeStream(of: Data.self)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
        Task { [weak self] in
            var buffer = Data()
            for await chunk in chunks {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<newline]
                    buffer.removeSubrange(buffer.startIndex...newline)
                    await self?.receive(Data(line))
                }
            }
        }
    }

    /// Helper log (commands sent to the robot, errors): ~/Library/Logs/R2D2 Command Center/helper.log
    private static func logFile() -> FileHandle? {
        let directory = URL.libraryDirectory.appending(path: "Logs/\(AppInfo.name)")
        let url = directory.appending(path: "helper.log")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        _ = try? handle.seekToEnd()
        return handle
    }

    private func receive(_ data: Data) {
        guard let header = try? JSONDecoder().decode(ResponseHeader.self, from: data), let id = header.id else {
            return
        }
        pending.removeValue(forKey: id)?.resume(returning: data)
    }

    private func fail(_ id: Int, with error: RobotError) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func didTerminate(_ processID: ObjectIdentifier) {
        guard let process, ObjectIdentifier(process) == processID else { return }
        self.process = nil
        input = nil
        let calls = pending
        pending = [:]
        for continuation in calls.values {
            continuation.resume(throwing: RobotError.helperUnavailable("The helper exited."))
        }
    }
}

struct NoParams: Codable, Sendable {}

private struct Request<Params: Encodable>: Encodable {
    let id: Int
    let method: String
    let params: Params
}

private struct ResponseHeader: Decodable {
    let id: Int?
}

private struct Response<Output: Decodable>: Decodable {
    struct Failure: Decodable {
        let code: String
        let message: String
    }

    let result: Output?
    let error: Failure?
}
