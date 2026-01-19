import Foundation
import NotesLib

// Benchmark search performance with and without content search

func benchmark(_ label: String, iterations: Int = 5, _ block: () throws -> Void) -> (avg: Double, min: Double, max: Double) {
    var times: [Double] = []

    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        try? block()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        times.append(elapsed)
    }

    let avg = times.reduce(0, +) / Double(times.count)
    return (avg, times.min() ?? 0, times.max() ?? 0)
}

func formatTime(_ t: Double) -> String {
    if t < 0.001 {
        return String(format: "%.2fms", t * 1000)
    } else if t < 1.0 {
        return String(format: "%.0fms", t * 1000)
    } else {
        return String(format: "%.2fs", t)
    }
}

print("🔍 Apple Notes Search Benchmark")
print("================================\n")

let db = NotesDatabase()

do {
    // Count total notes (db auto-opens on first query)
    let allNotes = try db.listNotes(limit: 10000)
    print("Total notes in database: \(allNotes.count)\n")

    let queries = [
        ("grep", "Common term in titles"),
        ("kubectl", "Technical term"),
        ("ansible", "Should have many matches"),
        ("configuration", "Generic term likely in bodies"),
        ("cmsg", "Only in note body, not title"),
        ("sudo", "Common in bodies"),
        ("xyznotexist123", "No matches - worst case for content search")
    ]

    print("Running 5 iterations per test...\n")
    print(String(repeating: "-", count: 80))

    for (query, description) in queries {
        print("\nQuery: \"\(query)\" (\(description))")

        // Without content search
        var resultCount1 = 0
        let t1 = benchmark("without") {
            let results = try db.searchNotes(query: query, limit: 20, searchContent: false)
            resultCount1 = results.count
        }

        // With content search
        var resultCount2 = 0
        let t2 = benchmark("with content") {
            let results = try db.searchNotes(query: query, limit: 20, searchContent: true)
            resultCount2 = results.count
        }

        print("  Index only:    \(formatTime(t1.avg)) avg (\(formatTime(t1.min))-\(formatTime(t1.max))) → \(resultCount1) results")
        print("  With content:  \(formatTime(t2.avg)) avg (\(formatTime(t2.min))-\(formatTime(t2.max))) → \(resultCount2) results")

        if t1.avg > 0 {
            let ratio = t2.avg / t1.avg
            let extraResults = resultCount2 - resultCount1
            print("  Δ Slowdown: \(String(format: "%.1f", ratio))x | Extra results: +\(extraResults)")
        }
    }

    print("\n" + String(repeating: "-", count: 80))
    print("\nDone!")

} catch {
    print("Error: \(error)")
}
