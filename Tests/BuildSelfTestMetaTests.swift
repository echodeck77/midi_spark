import XCTest

// Validates the IN-APP MIDI self-tests (BuildSelfTest) off-device: every case must PASS against the real engine, so
// the on-device suite's expected values are proven correct here (a wrong expectation would surface as a red row in
// the app, but this catches it in CI/seconds). BuildSelfTest is #if DEBUG; the test target builds Debug.
final class BuildSelfTestMetaTests: XCTestCase {
    func testEveryInAppSelfTestPasses() {
        let results = BuildSelfTest.runAll()
        XCTAssertFalse(results.isEmpty, "the self-test suite produced no results")
        let failures = results.filter { !$0.passed }
        XCTAssertTrue(failures.isEmpty, "in-app self-tests failed:\n" + failures.map { "  ✗ \($0.name) — \($0.detail)" }.joined(separator: "\n"))
    }
}
