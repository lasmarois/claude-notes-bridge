# Goal-11: Findings

## Current CLI State

### Existing Arguments (main.swift)
- `--test-encoder` - Run encoder roundtrip test
- `--test-create` - Create a test note
- `--list-folders` - List available folders
- (default) - Start MCP server

### Issues with Current Approach
1. No `--help` or `--version`
2. Ad-hoc `if CommandLine.arguments.contains()` checks
3. No proper error handling structure
4. Test commands mixed with production code
5. No subcommand organization

## Swift Argument Parser

### Package
```swift
.package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
```

### Basic Structure
```swift
@main
struct NotesTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notes-bridge",
        abstract: "Apple Notes bridge for Claude/MCP",
        version: "0.1.0",
        subcommands: [Serve.self, Search.self, List.self, Export.self]
    )
}
```

## Exit Codes Convention
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Permission denied (Full Disk Access) |
| 3 | Not found |
| 64 | Usage error (EX_USAGE) |

## Terminal Colors (ANSI)
```swift
let red = "\u{001B}[31m"
let green = "\u{001B}[32m"
let yellow = "\u{001B}[33m"
let bold = "\u{001B}[1m"
let reset = "\u{001B}[0m"
```
