import Quickshell.Io

Socket {
  id: root
  required property string runtimeDir
  readonly property string socketFileName: "hyprmoncfgd.sock"
  path: runtimeDir + "/" + socketFileName
  connected: false
  onError: connected = false
  signal directoryChanged()

  property Process existingSocketCheck: Process {
    command: ["test", "-S", root.path]
    onExited: function(exitCode) { if (exitCode === 0 && !root.connected) root.connected = true }
  }

  property Process directoryEvents: Process {
    running: root.runtimeDir !== ""
    command: ["env", "LC_ALL=C", "inotifywait", "--monitor", "--event", "create,delete,moved_to,moved_from",
      "--format", "%e %f", root.runtimeDir]
    stdout: SplitParser {
      onRead: function(line) {
        var fields = line.split(" ")
        if (fields[1] !== root.socketFileName) return
        root.connected = fields[0] === "CREATE" || fields[0] === "MOVED_TO"
        root.directoryChanged()
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        if (line !== "Watches established.") return
        root.existingSocketCheck.running = true
        root.directoryChanged()
      }
    }
  }
}
