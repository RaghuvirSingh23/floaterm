import Darwin
import Dispatch
import Foundation

struct TerminalGridSize: Equatable {
    var columns: Int
    var rows: Int
}

enum TerminalSessionError: LocalizedError {
    case openPTY(errno: Int32)

    var errorDescription: String? {
        switch self {
        case let .openPTY(code):
            return "Failed to allocate a pseudo terminal (\(String(cString: strerror(code))))."
        }
    }
}

final class TerminalSession: @unchecked Sendable {
    var onData: ((Data) -> Void)?
    var onExit: (() -> Void)?

    private let ioQueue = DispatchQueue(label: "com.raghusi.floaterm.terminal")
    private var readSource: DispatchSourceRead?
    private var isClosed = false
    private(set) var masterFD: Int32 = -1
    private(set) var pid: pid_t = 0

    init(initialSize: TerminalGridSize = TerminalGridSize(columns: 100, rows: 30)) throws {
        try start(initialSize: initialSize)
    }

    deinit {
        finish(sendSignal: true)
    }

    func write(_ data: Data) {
        ioQueue.async { [weak self] in
            guard let self, !self.isClosed, self.masterFD >= 0 else {
                return
            }

            _ = data.withUnsafeBytes { buffer in
                Darwin.write(self.masterFD, buffer.baseAddress, buffer.count)
            }
        }
    }

    func resize(_ size: TerminalGridSize) {
        ioQueue.async { [weak self] in
            guard let self, !self.isClosed, self.masterFD >= 0 else {
                return
            }

            var winsize = winsize(
                ws_row: UInt16(max(size.rows, 2)),
                ws_col: UInt16(max(size.columns, 2)),
                ws_xpixel: 0,
                ws_ypixel: 0
            )

            _ = ioctl(self.masterFD, TIOCSWINSZ, &winsize)
        }
    }

    func close() {
        ioQueue.async { [weak self] in
            self?.finish(sendSignal: true)
        }
    }

    private func start(initialSize: TerminalGridSize) throws {
        var master: Int32 = -1
        var terminalSize = winsize(
            ws_row: UInt16(max(initialSize.rows, 2)),
            ws_col: UInt16(max(initialSize.columns, 2)),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let pid = forkpty(&master, nil, nil, &terminalSize)

        guard pid != -1 else {
            throw TerminalSessionError.openPTY(errno: errno)
        }

        if pid == 0 {
            launchChild(shellPath: shellPath)
        }

        masterFD = master
        self.pid = pid
        _ = fcntl(masterFD, F_SETFL, O_NONBLOCK)

        startReadLoop()
    }

    private func startReadLoop() {
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: ioQueue)
        source.setEventHandler { [weak self] in
            self?.drainOutput()
        }
        source.setCancelHandler { [fd = masterFD] in
            if fd >= 0 {
                Darwin.close(fd)
            }
        }

        readSource = source
        source.resume()
    }

    private func drainOutput() {
        guard !isClosed, masterFD >= 0 else {
            return
        }

        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let readCount = Darwin.read(masterFD, &buffer, buffer.count)

            if readCount > 0 {
                let chunk = Data(buffer.prefix(readCount))
                DispatchQueue.main.async { [weak self] in
                    self?.onData?(chunk)
                }
                continue
            }

            if readCount == 0 {
                finish(sendSignal: false)
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }

            finish(sendSignal: false)
            return
        }
    }

    private func finish(sendSignal: Bool) {
        guard !isClosed else {
            return
        }

        isClosed = true

        if sendSignal, pid > 0 {
            kill(pid, SIGHUP)
        }

        readSource?.cancel()
        readSource = nil
        masterFD = -1

        if pid > 0 {
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            pid = 0
        }

        DispatchQueue.main.async { [weak self] in
            self?.onExit?()
        }
    }

    private func launchChild(shellPath: String) -> Never {
        let environment = ProcessInfo.processInfo.environment
        setenv("TERM", "xterm-256color", 1)
        setenv("COLORTERM", "truecolor", 1)
        setenv("LANG", environment["LANG"] ?? "en_US.UTF-8", 1)
        chdir(NSHomeDirectory())

        let shellName = URL(fileURLWithPath: shellPath).lastPathComponent
        var arguments: [UnsafeMutablePointer<CChar>?] = [
            strdup(shellName),
            strdup("-il"),
            nil,
        ]

        _ = arguments.withUnsafeMutableBufferPointer { buffer in
            shellPath.withCString { executable in
                execv(executable, buffer.baseAddress)
            }
        }

        _exit(1)
    }
}
