//  SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
//  SPDX-License-Identifier: LGPL-3.0-or-later

@testable import NextcloudFileProviderKit
import NextcloudFileProviderKitMocks
import XCTest

///
/// Common base class for all tests in this target.
///
class NextcloudFileProviderKitTestCase: XCTestCase {
    func setUpDatabase(_ dbManager: FilesDatabaseManager) {
        try! dbManager.removeAllRowsForTesting()
    }

    ///
    /// Whether this test expects its production code to log `.error` or `.fault` messages.
    ///
    /// Left `false`, ``tearDown()`` fails the test when anything was logged at those levels. Several
    /// code paths log and carry on where they cannot throw, so without this a test can fail on a
    /// downstream assertion — or worse, pass — while the real complaint sits invisible in a log nobody
    /// reads. Override and return `true` in a test class that deliberately exercises failure paths.
    ///
    var expectsLoggedErrors: Bool {
        false
    }

    private var testDrivesAFailurePath = false

    ///
    /// Declare that *this* test drives a failure path, so the `.error` messages its production code
    /// logs are the point of the test rather than a defect.
    ///
    /// Prefer this to overriding ``expectsLoggedErrors``: it keeps the check live for every other test
    /// in the same class, and it documents at the top of the test that failure handling is what is
    /// under test.
    ///
    func expectLoggedErrors() {
        testDrivesAFailurePath = true
    }

    ///
    /// Drop process-wide state that would otherwise leak from the previous test.
    ///
    /// `InsufficientQuotaReporter` dedups its per-domain summary on a singleton actor, so a test
    /// that reports a summary leaves the next test using that domain deduped into silence. That is
    /// invisible in a normal run, where each class happens to use its own domain string, and shows
    /// up the moment a test runs twice in the same process — under `-test-iterations`, every repeat
    /// after the first failed on the missing summary (XNT-127).
    ///
    /// Resetting here rather than in each class is deliberate: it makes the whole bug class
    /// impossible instead of fixed once per class.
    ///
    override func setUp() async throws {
        try await super.setUp()
        await InsufficientQuotaReporter.resetSummaryDedupForTesting()
        // Tests reuse accounts while advertising different server capabilities.
        await RetrievedCapabilitiesActor.shared.reset()
    }

    override func setUp() {
        super.setUp()
        FileProviderLogProblemRecorder.reset()
    }

    override func tearDown() {
        super.tearDown()

        guard expectsLoggedErrors == false, testDrivesAFailurePath == false else {
            return
        }

        let problems = FileProviderLogProblemRecorder.problems

        if problems.isEmpty == false {
            XCTFail(
                """
                Production code logged \(problems.count) error(s) during this test:
                \(problems.map(\.description).joined(separator: "\n"))
                """
            )
        }
    }

    ///
    /// Create a unique and temporary directory for database testing purposes.
    ///
    /// - Returns: A URL pointing to a temporary directory which also contains a UUID to distinguish it clearly from any other calls.
    ///
    static func makeDatabaseDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        return url
    }

    ///
    /// Instance wrapper for ``makeDatabaseDirectory`` for convenience and brevity.
    ///
    func makeDatabaseDirectory() -> URL {
        Self.makeDatabaseDirectory()
    }
}
