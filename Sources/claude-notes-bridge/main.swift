import Foundation

// Check Full Disk Access first
guard Permissions.hasFullDiskAccess() else {
    Permissions.printAccessInstructions()
    exit(1)
}

// Start MCP server
let server = MCPServer()

// Run the async main loop
let semaphore = DispatchSemaphore(value: 0)
Task {
    await server.run()
    semaphore.signal()
}
semaphore.wait()
