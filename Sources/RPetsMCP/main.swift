import Foundation

// Session ID resolution: --session <id>  >  RPETS_SESSION env  >  error
var sessionId: String?

var argIndex = 1
while argIndex < CommandLine.arguments.count {
    let arg = CommandLine.arguments[argIndex]
    if arg == "--session", argIndex + 1 < CommandLine.arguments.count {
        sessionId = CommandLine.arguments[argIndex + 1]
        argIndex += 2
    } else {
        argIndex += 1
    }
}

if sessionId == nil {
    sessionId = ProcessInfo.processInfo.environment["RPETS_SESSION"]
}

guard let sessionId else {
    fputs("RPetsMCP: --session <id> is required\n", stderr)
    exit(1)
}

MCPServer(sessionId: sessionId).run()
