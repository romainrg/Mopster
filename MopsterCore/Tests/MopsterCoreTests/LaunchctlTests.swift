import XCTest

@testable import MopsterCore

final class LaunchctlTests: XCTestCase {
    func testLaunchctlArgumentsKeepLabelWithSpacesAndQuotesIntact() {
        let label = "com.we ird.\"quoted\" $(touch x); `x` 'y'"
        let plist = URL(fileURLWithPath: "/Users/me/Library/LaunchAgents/we ird \"x\".plist")
        XCTAssertEqual(
            Launchctl.disableArguments(label: label, uid: 501),
            [["bootout", "gui/501/\(label)"], ["disable", "gui/501/\(label)"]])
        XCTAssertEqual(
            Launchctl.enableArguments(label: label, plist: plist, uid: 501),
            [["enable", "gui/501/\(label)"], ["bootstrap", "gui/501", plist.path]])
    }

    func testParseDisabled() {
        let modern = """
            disabled services = {
            \t"com.apple.thing" => enabled
            \t"com.example.off" => disabled
            \t"com.example.with space" => disabled
            }
            """
        XCTAssertEqual(Launchctl.parseDisabled(modern), ["com.example.off", "com.example.with space"])
        let older = """
            {
            \t"com.old.off" = true;
            \t"com.old.on" = false;
            \t"com.old.arrow" => true
            \t"com.old.arrowon" => false
            }
            """
        XCTAssertEqual(Launchctl.parseDisabled(older), ["com.old.off", "com.old.arrow"])
        XCTAssertEqual(Launchctl.parseDisabled(""), [])
    }
}
