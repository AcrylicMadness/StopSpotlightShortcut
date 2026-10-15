import Foundation

/// Follows GeForce NOW's streaming-engine log (`geronimo.log`) to tell whether a game is
/// actually being streamed.
///
/// The stream runs inside the main GeForce NOW process, so nothing about the process list or
/// the frontmost app distinguishes browsing the library or waiting in the queue from playing.
/// The streaming engine does log when the video stream connects and when it is torn down.
@MainActor
final class StreamLogWatcher {
    // Written by GeForce NOW 2.0.x when the stream connects, and when it ends (leaving the
    // game, session timeout, or network drop).
    private static let startMarkers = ["onStreamingBegin", "onStreamerConnected:"]
    private static let endMarkers = ["onStreamerDisconnected", "Streamer Disconnected.", "nvbStopStreaming("]

    private struct FileID: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private let url: URL
    private var fileID: FileID?
    private var offset: UInt64 = 0
    private var partialLine = Data()

    private(set) var isStreaming = false
    private(set) var streamStart: Date?
    private(set) var isReadable = false

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/NVIDIA/GeForceNOW/geronimo.log")) {
        self.url = url
    }

    /// Forgets the session state. With `skipExisting`, whatever is already in the log is ignored
    /// because it was written by an earlier GeForce NOW run.
    func reset(skipExisting: Bool) {
        setStreaming(false)
        partialLine.removeAll()
        var info = stat()
        if skipExisting, stat(url.path, &info) == 0 {
            fileID = FileID(device: info.st_dev, inode: info.st_ino)
            offset = UInt64(info.st_size)
        } else {
            fileID = nil
            offset = 0
        }
    }

    /// Reads whatever was appended since the last poll.
    func poll() {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            isReadable = false
            setStreaming(false)
            return
        }
        defer { try? handle.close() }
        isReadable = true

        var info = stat()
        guard fstat(handle.fileDescriptor, &info) == 0 else { return }
        let id = FileID(device: info.st_dev, inode: info.st_ino)
        let size = UInt64(info.st_size)
        // GeForce NOW moves the old log to geronimo.log.bak on launch; start over on a new file.
        if id != fileID || size < offset {
            fileID = id
            offset = 0
            partialLine.removeAll()
            setStreaming(false)
        }
        guard size > offset,
              (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty
        else { return }
        offset += UInt64(data.count)
        consume(data)
    }

    private func consume(_ data: Data) {
        partialLine.append(data)
        guard let newline = partialLine.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let text = String(decoding: partialLine[..<newline], as: UTF8.self)
        partialLine = Data(partialLine[(newline + 1)...])

        // `isNewline` rather than "\n": some entries end in "\r\n", which is a single Character.
        for line in text.split(whereSeparator: \.isNewline) where line.contains("Stream") {
            if Self.startMarkers.contains(where: { line.contains($0) }) {
                if !isStreaming { setStreaming(true, since: Self.timestamp(of: line)) }
            } else if Self.endMarkers.contains(where: { line.contains($0) }) {
                setStreaming(false)
            }
        }
    }

    private func setStreaming(_ streaming: Bool, since start: Date? = nil) {
        isStreaming = streaming
        streamStart = streaming ? start : nil
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
        return formatter
    }()

    /// Lines start with `[2026-10-15 20:57:51,983]=23:57:51=`; the bracketed time is UTC.
    private static func timestamp(of line: Substring) -> Date {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]"),
              let date = timestampFormatter.date(from: String(line[line.index(after: line.startIndex)..<close]))
        else { return Date() }
        return date
    }
}
