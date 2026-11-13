import Foundation

// Smoke tests for pure logic — compiled ad hoc, no test target needed:
//   xcrun --sdk macosx swiftc -parse-as-library -O -o /tmp/NeoCraftSmoke \
//     Sources/NeoCraft/Core/NBT.swift Sources/NeoCraft/Models/MinecraftModels.swift \
//     Tests/Smoke/main.swift && /tmp/NeoCraftSmoke

@main
struct Smoke {
    static func main() {
        var failures = 0
        func check(_ cond: Bool, _ name: String) {
            print("\(cond ? "PASS" : "FAIL") \(name)")
            if !cond { failures += 1 }
        }

        // CommandLineSplitter
        check(CommandLineSplitter.split(#"java -Dfoo="a b" -jar x.jar"#) == ["java", "-Dfoo=a b", "-jar", "x.jar"], "split basic")
        check(CommandLineSplitter.split("a   b  c") == ["a", "b", "c"], "split whitespace")
        check(CommandLineSplitter.split("") == [], "split empty")

        // GZip (lives in NBT.swift)
        let payload = Data("hello neocraft".utf8)
        if let zipped = GZip.compress(payload), let back = GZip.decompress(zipped) {
            check(back == payload, "gzip roundtrip")
        } else {
            check(false, "gzip roundtrip")
        }

        // NBT: serialize → parse round trip
        let value: NBTValue = .compound([
            "DataVersion": .int(4189),
            "LevelName": .string("Test World"),
            "Pos": .list([.double(1), .double(2), .double(3)]),
        ])
        do {
            let data = NBTWriter.serialize(rootName: "", value)
            let back = try NBTReader.parse(data)
            check(back["DataVersion"]?.intValue == 4189, "NBT int roundtrip")
            check(back["LevelName"]?.stringValue == "Test World", "NBT string roundtrip")
            if case .list(let items) = back["Pos"] {
                check(items.count == 3, "NBT list roundtrip")
            } else {
                check(false, "NBT list roundtrip")
            }
        } catch {
            check(false, "NBT roundtrip threw \(error)")
        }

        print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURES")
        if failures > 0 { exit(1) }
    }
}
