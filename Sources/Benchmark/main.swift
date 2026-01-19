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
let ftsIndex = SearchIndex(notesDB: db)

do {
    // Count total notes (db auto-opens on first query)
    let allNotes = try db.listNotes(limit: 10000)
    print("Total notes in database: \(allNotes.count)")
    print("FTS index: \(ftsIndex.isIndexed ? "\(ftsIndex.indexedCount) notes" : "not built")\n")

    let queries = [
        ("grep", "Common term in titles"),
        ("kubectl", "Technical term"),
        ("ansible", "Should have many matches"),
        ("cmsg", "Only in note body, not title"),
        ("sudo", "Common in bodies")
    ]

    print("Running 5 iterations per test...\n")
    print(String(repeating: "-", count: 90))

    for (query, description) in queries {
        print("\nQuery: \"\(query)\" (\(description))")

        // Index only (title/snippet/folder)
        var resultCount1 = 0
        let t1 = benchmark("index") {
            let results = try db.searchNotes(query: query, limit: 20, searchContent: false)
            resultCount1 = results.count
        }

        // With content search (slow)
        var resultCount2 = 0
        let t2 = benchmark("content") {
            let results = try db.searchNotes(query: query, limit: 20, searchContent: true)
            resultCount2 = results.count
        }

        // FTS5 search (fast)
        var resultCount3 = 0
        let t3 = benchmark("FTS5") {
            let results = try ftsIndex.search(query: query, limit: 20)
            resultCount3 = results.count
        }

        print("  Index only:    \(formatTime(t1.avg)) avg → \(resultCount1) results")
        print("  Content scan:  \(formatTime(t2.avg)) avg → \(resultCount2) results")
        print("  FTS5:          \(formatTime(t3.avg)) avg → \(resultCount3) results")

        if t2.avg > 0 && t3.avg > 0 {
            let speedup = t2.avg / t3.avg
            print("  ⚡ FTS5 is \(String(format: "%.0f", speedup))x faster than content scan")
        }
    }

    print("\n" + String(repeating: "-", count: 90))
    print("\nDone!")

} catch {
    print("Error: \(error)")
}
