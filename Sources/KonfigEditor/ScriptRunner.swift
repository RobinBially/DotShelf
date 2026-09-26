import Foundation
import Darwin

/// Führt einen Befehl in einer echten PTY-Sitzung aus. Das Programm sieht ein
/// Terminal (Farben, Fortschrittszeilen, Zeilenumbruchbreite), DotShelf liest
/// die Ausgabe, kann Eingaben schicken und den Prozess stoppen.
final class ScriptRunner {

    enum StartError: LocalizedError {
        case alreadyRunning
        case ptyUnavailable
        case spawnFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRunning:
                return L10n.text("This terminal is already running.")
            case .ptyUnavailable:
                return L10n.text("Could not open a terminal.")
            case .spawnFailed(let reason):
                return L10n.format("Could not start: %@", reason)
            }
        }
    }

    /// Womit der Prozess geendet hat.
    enum Termination: Equatable {
        case exited(Int32)
        case signaled(Int32)
    }

    var onOutput: ((Data) -> Void)?
    var onExit: ((Termination) -> Void)?

    private let queue = DispatchQueue(label: "ai.robin.dotshelf.script-runner")
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var didFinish = false
    private var stopRequested = false
    /// Wird nur auf der Runner-Queue benutzt.
    private var masterFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var processSource: DispatchSourceProcess?
    private var streamEnded = false
    /// Tastendrücke, die eintreffen, während der Prozess noch startet. Sie
    /// gehen nicht verloren, sondern werden nachgereicht.
    private var pendingInput = Data()

    var isRunning: Bool { currentPID() > 0 }

    /// Ob gerade Kindprozesse laufen. Bei einer Shell heißt das: Dort arbeitet
    /// ein Befehl. Eine Shell an der Eingabeaufforderung hat keine Kinder und
    /// wartet nur.
    var hasRunningChildren: Bool {
        let current = currentPID()
        guard current > 0 else { return false }
        var children = [pid_t](repeating: 0, count: 64)
        let bytes = Int32(children.count * MemoryLayout<pid_t>.size)
        let count = children.withUnsafeMutableBytes { buffer -> Int32 in
            proc_listchildpids(current, buffer.baseAddress, bytes)
        }
        return count > 0
    }

    /// Ob der letzte Stopp auf Wunsch des Nutzers passierte.
    var stoppedByUser: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }

    // MARK: - Starten

    func start(command: String, workingDirectory: URL, columns: Int, rows: Int,
               environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard !isRunning else { throw StartError.alreadyRunning }
        guard let pty = Self.openPTY() else { throw StartError.ptyUnavailable }
        Self.setWindowSize(pty.master, columns: columns, rows: rows)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addopen(&actions, 0, pty.slave, O_RDWR, 0)
        posix_spawn_file_actions_addopen(&actions, 1, pty.slave, O_RDWR, 0)
        posix_spawn_file_actions_addopen(&actions, 2, pty.slave, O_RDWR, 0)
        posix_spawn_file_actions_addclose(&actions, pty.master)
        if FileManager.default.fileExists(atPath: workingDirectory.path) {
            posix_spawn_file_actions_addchdir_np(&actions, workingDirectory.path)
        }
        defer { posix_spawn_file_actions_destroy(&actions) }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes,
            Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        for signal in [SIGINT, SIGQUIT, SIGTERM, SIGHUP, SIGPIPE, SIGTSTP, SIGTTIN, SIGTTOU, SIGCONT] {
            sigaddset(&defaultSignals, signal)
        }
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        var signalMask = sigset_t()
        sigemptyset(&signalMask)
        posix_spawnattr_setsigmask(&attributes, &signalMask)
        defer { posix_spawnattr_destroy(&attributes) }

        // Eine Login-Shell kennt den PATH der Nutzerumgebung – wichtig für
        // Programme wie docker, die nur in /usr/local/bin o. Ä. liegen.
        var commandEnvironment = environment
        commandEnvironment["TERM"] = "xterm-256color"
        commandEnvironment["COLORTERM"] = "truecolor"
        commandEnvironment["PWD"] = workingDirectory.path
        if commandEnvironment["LANG"] == nil { commandEnvironment["LANG"] = "en_US.UTF-8" }
        commandEnvironment.removeValue(forKey: "TERM_PROGRAM")
        commandEnvironment.removeValue(forKey: "TERM_PROGRAM_VERSION")
        commandEnvironment.removeValue(forKey: "TERM_SESSION_ID")

        var arguments: [UnsafeMutablePointer<CChar>?] = [
            strdup("/bin/zsh"), strdup("-l"), strdup("-c"), strdup(command), nil
        ]
        var environmentStrings: [UnsafeMutablePointer<CChar>?] =
            commandEnvironment.map { strdup($0.key + "=" + $0.value) }
        environmentStrings.append(nil)
        defer {
            arguments.compactMap { $0 }.forEach { free($0) }
            environmentStrings.compactMap { $0 }.forEach { free($0) }
        }

        var spawned: pid_t = 0
        let status = posix_spawn(&spawned, "/bin/zsh", &actions, &attributes,
                                 &arguments, &environmentStrings)
        guard status == 0, spawned > 0 else {
            close(pty.master)
            throw StartError.spawnFailed(String(cString: strerror(status)))
        }

        lock.lock()
        pid = spawned
        didFinish = false
        stopRequested = false
        lock.unlock()
        masterFD = pty.master
        Self.setNonBlocking(pty.master)

        // Was vor dem Start getippt wurde, gehört dem neuen Prozess.
        queue.async { [weak self] in
            guard let self else { return }
            let buffered = self.pendingInput
            self.pendingInput = Data()
            if !buffered.isEmpty { self.writeAll(buffered) }
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: pty.master, queue: queue)
        source.setEventHandler { [weak self] in self?.streamReadable() }
        readSource = source
        source.resume()

        // Zusätzlich das Prozessende beobachten: Schließt der Prozess seine
        // Dateien, endet auch der Lesekanal (Hauptweg). Beendet er sich, ohne
        // dass ein Nachfolger das Terminal offen hält, greift diese Quelle.
        let process = DispatchSource.makeProcessSource(identifier: spawned,
                                                       eventMask: .exit, queue: queue)
        process.setEventHandler { [weak self] in self?.processExited() }
        processSource = process
        process.resume()
    }

    deinit {
        readSource?.cancel()
        processSource?.cancel()
    }

    // MARK: - Steuerung

    /// Schreibt Eingaben an das Terminal (Tastatur, Einfügen, Zeilenende).
    func send(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            guard self.masterFD >= 0 else {
                self.pendingInput.append(data)
                return
            }
            self.writeAll(data)
        }
    }

    /// Schreibt die Bytes vollständig; läuft auf der Runner-Queue.
    private func writeAll(_ data: Data) {
        guard masterFD >= 0 else { return }
        let bytes = [UInt8](data)
        var offset = 0
        var stalls = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return write(masterFD, base + offset, bytes.count - offset)
            }
            if written > 0 {
                offset += written
                stalls = 0
                continue
            }
            if written < 0, errno == EINTR { continue }
            if written < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                stalls += 1
                if stalls > 40 { break }
                usleep(5_000)
                continue
            }
            break   // Terminal geschlossen
        }
    }

    /// Meldet dem Terminal eine neue Fenstergröße.
    func resize(columns: Int, rows: Int) {
        queue.async { [weak self] in
            guard let self, self.masterFD >= 0 else { return }
            Self.setWindowSize(self.masterFD, columns: columns, rows: rows)
        }
    }

    /// Bittet den Prozessbaum zu beenden und eskaliert zügig, wenn er nicht
    /// folgt. Interaktive Shells fangen SIGINT und SIGTERM ab – ohne den
    /// letzten Schritt ließe sich so ein Lauf gar nicht stoppen.
    func stop() {
        guard isRunning else { return }
        lock.lock()
        stopRequested = true
        lock.unlock()
        signalGroup(SIGINT)
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.isRunning else { return }
            self.signalGroup(SIGTERM)
            self.queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.isRunning else { return }
                self.signalGroup(SIGKILL)
            }
        }
    }

    // MARK: - Interna

    private func signalGroup(_ signal: Int32) {
        let current = currentPID()
        guard current > 0 else { return }
        // Der Prozess führt die Gruppe an (POSIX_SPAWN_SETPGROUP), daher
        // erreicht das Signal auch die Kinder – etwa docker compose.
        if Darwin.kill(-current, signal) != 0 {
            _ = Darwin.kill(current, signal)
        }
    }

    /// Liest verfügbare Ausgabe. Rückgabe: true, wenn die Gegenseite das
    /// Terminal geschlossen hat – dann ist die Ausgabe vollständig.
    private func drain() -> Bool {
        guard masterFD >= 0 else { return true }
        var storage = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = storage.withUnsafeMutableBytes { buffer -> Int in
                read(masterFD, buffer.baseAddress, buffer.count)
            }
            if count > 0 {
                onOutput?(Data(storage[0..<count]))
                continue
            }
            if count < 0, errno == EINTR { continue }
            if count < 0, errno == EAGAIN || errno == EWOULDBLOCK { return false }
            return true
        }
    }

    private func streamReadable() {
        guard !streamEnded else { return }
        if drain() {
            streamEnded = true
            reapAndFinish()
        }
    }

    private func processExited() {
        if !streamEnded { streamEnded = drain() }
        reapAndFinish()
    }

    /// Räumt den Kindprozess ab und meldet das Ende. Wichtig: erst auslesen,
    /// dann abräumen – macOS verwirft ungelesene Terminal-Daten beim Abräumen.
    private func reapAndFinish() {
        let current = currentPID()
        guard current > 0 else { return }
        let deadline = Date().addingTimeInterval(10)
        while true {
            var raw: Int32 = 0
            let result = waitpid(current, &raw, WNOHANG)
            if result > 0 {
                finish(status: raw)
                return
            }
            if result < 0 {
                finish(status: 0)
                return
            }
            // Der Prozess lebt noch (etwa ein Daemon ohne Terminal): nicht warten.
            if Date() > deadline || !streamEnded {
                finish(status: 0)
                return
            }
            usleep(10_000)
        }
    }

    private func finish(status: Int32) {
        lock.lock()
        guard !didFinish else { lock.unlock(); return }
        didFinish = true
        pid = 0
        lock.unlock()

        _ = drain()
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        readSource?.cancel()
        readSource = nil
        processSource?.cancel()
        processSource = nil

        let termination: Termination =
            (status & 0x7f) != 0 ? .signaled(status & 0x7f) : .exited((status >> 8) & 0xff)
        DispatchQueue.main.async { [weak self] in
            self?.onExit?(termination)
        }
    }

    private func currentPID() -> pid_t {
        lock.lock()
        defer { lock.unlock() }
        return pid
    }

    private static func openPTY() -> (master: Int32, slave: String)? {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else { return nil }
        guard grantpt(master) == 0, unlockpt(master) == 0, let name = ptsname(master) else {
            close(master)
            return nil
        }
        return (master, String(cString: name))
    }

    private static func setNonBlocking(_ descriptor: Int32) {
        let flags = fcntl(descriptor, F_GETFL, 0)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
    }

    private static func setWindowSize(_ descriptor: Int32, columns: Int, rows: Int) {
        var size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns),
                           ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(descriptor, TIOCSWINSZ, &size)
    }
}
