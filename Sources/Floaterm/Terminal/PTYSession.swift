import Foundation

protocol PTYSessionProtocol: AnyObject {
    func write(_ data: Data)
    func resize(cols: Int, rows: Int)
    var onOutput: ((Data) -> Void)? { get set }
    var scrollback: String { get }
    var alive: Bool { get }
}

final class PTYSession: PTYSessionProtocol {
    private var masterFD: Int32 = -1
    private var childPID: pid_t = 0
    private var readSource: DispatchSourceRead?
    private var _scrollback = ""
    private let scrollbackLimit = Dimensions.scrollbackLimit
    private(set) var alive = true

    var onOutput: ((Data) -> Void)?
    var scrollback: String { _scrollback }

    init(cols: Int = 80, rows: Int = 24, command: String? = nil) {
        spawnPTY(cols: cols, rows: rows, command: command)
    }

    deinit {
        kill()
    }

    private func spawnPTY(cols: Int, rows: Int, command: String? = nil) {
        var ws = winsize()
        ws.ws_col = UInt16(cols)
        ws.ws_row = UInt16(rows)
        ws.ws_xpixel = 0
        ws.ws_ypixel = 0

        var slaveFD: Int32 = 0
        childPID = forkpty(&masterFD, nil, nil, &ws)

        guard childPID >= 0 else {
            alive = false
            return
        }

        if childPID == 0 {
            // Child process — exec the shell
            let env = Self.makePTYEnv()
            for (key, val) in env {
                setenv(key, val, 1)
            }

            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            if let cmd = command {
                let args = [shell, "-l", "-c", cmd]
                let cArgs = args.map { strdup($0) } + [nil]
                execv(shell, cArgs)
            } else {
                let args = [shell, "-l"]
                let cArgs = args.map { strdup($0) } + [nil]
                execv(shell, cArgs)
            }
            _exit(1) // only reached if exec fails
        }

        // Parent process — set up read loop
        startReadLoop()
    }

    private func startReadLoop() {
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: .global(qos: .userInteractive))
        source.setEventHandler { [weak self] in
            guard let self, self.alive else { return }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let bytesRead = read(self.masterFD, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                // Append to scrollback
                if let str = String(data: data, encoding: .utf8) {
                    self._scrollback.append(str)
                    if self._scrollback.count > self.scrollbackLimit {
                        let excess = self._scrollback.count - self.scrollbackLimit
                        self._scrollback.removeFirst(excess)
                    }
                }
                DispatchQueue.main.async {
                    self.onOutput?(data)
                }
            } else if bytesRead <= 0 {
                self.alive = false
                source.cancel()
            }
        }
        source.setCancelHandler { [weak self] in
            self?.alive = false
        }
        source.resume()
        readSource = source
    }

    func write(_ data: Data) {
        guard alive, masterFD >= 0 else { return }
        data.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress {
                Darwin.write(masterFD, base, data.count)
            }
        }
    }

    func resize(cols: Int, rows: Int) {
        guard alive, masterFD >= 0 else { return }
        var ws = winsize()
        ws.ws_col = UInt16(cols)
        ws.ws_row = UInt16(rows)
        ioctl(masterFD, TIOCSWINSZ, &ws)
    }

    func kill() {
        guard alive else { return }
        alive = false
        readSource?.cancel()
        readSource = nil
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        if childPID > 0 {
            Darwin.kill(childPID, SIGHUP)
            childPID = 0
        }
    }

    // MARK: - Environment

    private static func makePTYEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        // Strip terminal integration vars (same as server.js lines 16-34)
        let stripPrefixes = ["ITERM_", "KITTY_", "KONSOLE_", "WEZTERM_", "WT_", "ALACRITTY_"]
        let stripExact: Set = [
            "LC_TERMINAL", "LC_TERMINAL_VERSION", "TERM_PROGRAM", "TERM_PROGRAM_VERSION",
            "TERMINAL_EMULATOR", "COLORTERM", "VTE_VERSION", "WINDOWID",
            "__CFBundleIdentifier", "SECURITYSESSIONID", "TERMINFO_DIRS"
        ]

        for key in env.keys {
            if stripExact.contains(key) || stripPrefixes.contains(where: { key.hasPrefix($0) }) {
                env.removeValue(forKey: key)
            }
        }

        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "floaterm"

        return env
    }
}
