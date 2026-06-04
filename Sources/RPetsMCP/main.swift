import Foundation

// Session ID resolution: --session <id>  >  RPETS_SESSION  >  CLAUDE_CODE_SESSION_ID  >  bail
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

let env = ProcessInfo.processInfo.environment
sessionId = sessionId ?? env["RPETS_SESSION"] ?? env["CLAUDE_CODE_SESSION_ID"]

guard let sessionId else {
    fputs("RPetsMCP: no session ID — pass --session <id>, set RPETS_SESSION, or run inside Claude Code\n", stderr)
    exit(1)
}

MCPServer(sessionId: sessionId).run()
