import XCTest

@testable import MopsterCore

final class CodeSignatureTests: XCTestCase {
    func testAppleBinaryIsApple() {
        XCTAssertEqual(CodeSignatureInspector.inspect("/bin/ls"), .apple)
    }

    func testAdHocCopy() throws {
        let dir = try makeTemporaryTree(["d/": 0])
        let copy = dir.appendingPathComponent("d/true-copy")
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: copy.path)
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["-f", "-s", "-", copy.path]
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        XCTAssertEqual(codesign.terminationStatus, 0)
        XCTAssertEqual(CodeSignatureInspector.inspect(copy.path), .adHoc)
    }

    func testPlainScriptIsUnsigned() throws {
        let dir = try makeTemporaryTree(["script.sh": 0])
        let script = dir.appendingPathComponent("script.sh")
        try "#!/bin/sh\necho hi\n".write(to: script, atomically: true, encoding: .utf8)
        XCTAssertEqual(CodeSignatureInspector.inspect(script.path), .unsigned)
    }

    func testMissingPathIsMissing() {
        XCTAssertEqual(CodeSignatureInspector.inspect("/nonexistent/\(UUID().uuidString)"), .missing)
    }

    func testWeirdPathsNeverCrash() throws {
        let dir = try makeTemporaryTree(["d/": 0])
        _ = CodeSignatureInspector.inspect(dir.appendingPathComponent("d").path)
        _ = CodeSignatureInspector.inspect("")
        _ = CodeSignatureInspector.inspect("/dev/null")
        _ = CodeSignatureInspector.inspect("/var/run/syslog")
    }
}
