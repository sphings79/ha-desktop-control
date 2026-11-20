import XCTest
@testable import DesktopControlCore

@MainActor
final class RuleEngineTests: XCTestCase {
    private func makeEngine(
        config: AppConfig = AppConfig(resumeDelaySeconds: 10),
        media: FakeMedia = FakeMedia(),
        windows: FakeWindows = FakeWindows(),
        gate: SleepGate = SleepGate()
    ) -> (RuleEngine, FakeMedia, FakeWindows, SleepGate) {
        let engine = RuleEngine(config: config, media: media, windows: windows, sleep: gate.sleep)
        return (engine, media, windows, gate)
    }

    func testOpenPausesMediaOnce() async {
        let (engine, media, _, _) = makeEngine()
        await engine.setContact(source: "a", open: true)
        await engine.setContact(source: "b", open: true)
        XCTAssertEqual(media.pauseCalls, 1)
        XCTAssertEqual(engine.status, .pausedByContact)
        XCTAssertEqual(engine.openSources, ["a", "b"])
    }

    func testRepeatedOpenMessageIsIgnored() async {
        let (engine, media, _, _) = makeEngine()
        await engine.setContact(source: "a", open: true)
        await engine.setContact(source: "a", open: true)
        XCTAssertEqual(media.pauseCalls, 1)
    }

    func testRestoreOnlyAfterLastSourceClosesAndDelay() async {
        let (engine, media, _, gate) = makeEngine()
        await engine.setContact(source: "a", open: true)
        await engine.setContact(source: "b", open: true)
        await engine.setContact(source: "a", open: false)
        XCTAssertTrue(media.resumed.isEmpty)

        await engine.setContact(source: "b", open: false)
        XCTAssertTrue(media.resumed.isEmpty, "must wait for the delay")
        XCTAssertEqual(engine.status, .pausedByContact)

        gate.release()
        let done = await waitUntil { engine.status == .idle }
        XCTAssertTrue(done)
        XCTAssertEqual(media.resumed.count, 1)
        XCTAssertEqual(media.resumed.first, media.playing)
        XCTAssertEqual(gate.requested, [10])
    }

    func testReopenDuringDelayCancelsRestore() async {
        let (engine, media, _, gate) = makeEngine()
        await engine.setContact(source: "a", open: true)
        await engine.setContact(source: "a", open: false)
        await engine.setContact(source: "a", open: true)
        gate.release()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(media.resumed.isEmpty)
        XCTAssertEqual(engine.status, .pausedByContact)
        XCTAssertEqual(media.pauseCalls, 1, "same episode, no second pause")
    }

    func testZeroDelayRestoresImmediately() async {
        let (engine, media, _, _) = makeEngine(config: AppConfig(resumeDelaySeconds: 0))
        await engine.setContact(source: "a", open: true)
        await engine.setContact(source: "a", open: false)
        XCTAssertEqual(media.resumed.count, 1)
        XCTAssertEqual(engine.status, .idle)
    }

    func testDisabledIgnoresContacts() async {
        let (engine, media, _, _) = makeEngine()
        await engine.setEnabled(false)
        await engine.setContact(source: "a", open: true)
        XCTAssertEqual(media.pauseCalls, 0)
        XCTAssertEqual(engine.status, .idle)
    }

    func testDisablingWhilePausedRestoresNow() async {
        let (engine, media, _, _) = makeEngine()
        await engine.setContact(source: "a", open: true)
        await engine.setEnabled(false)
        XCTAssertEqual(media.resumed.count, 1)
        XCTAssertEqual(engine.status, .idle)
    }

    func testSourceRulesSelectActions() async {
        var config = AppConfig(resumeDelaySeconds: 0)
        config.sources = [
            "balcony": SourceRule(actions: [.pauseMedia]),
            "front": SourceRule(actions: [.pauseMedia, .windows])
        ]
        config.apps = [
            AppRule(bundleId: "x.keep", name: "Keep", action: .minimize, restore: true),
            AppRule(bundleId: "x.quit", name: "Quit", action: .quit, restore: false)
        ]
        let windows = FakeWindows()
        windows.running = ["x.keep", "x.quit"]
        let (engine, _, _, _) = makeEngine(config: config, windows: windows)

        await engine.setContact(source: "balcony", open: true)
        XCTAssertTrue(windows.applied.isEmpty)

        await engine.setContact(source: "front", open: true)
        XCTAssertEqual(windows.applied, ["x.keep", "x.quit"])

        await engine.setContact(source: "front", open: false)
        await engine.setContact(source: "balcony", open: false)
        XCTAssertEqual(windows.restored, ["x.keep"], "restore=false stays untouched")
    }

    func testUnknownSourceUsesFallbackPauseOnly() async {
        let (engine, media, windows, _) = makeEngine()
        windows.running = ["x"]
        await engine.setContact(source: "unknown", open: true)
        XCTAssertEqual(media.pauseCalls, 1)
        XCTAssertTrue(windows.applied.isEmpty)
    }

    func testManualPauseAndRestore() async {
        let (engine, media, _, _) = makeEngine()
        await engine.manualPause()
        XCTAssertEqual(engine.status, .pausedByContact)
        await engine.manualRestore()
        XCTAssertEqual(media.resumed.count, 1)
        XCTAssertEqual(engine.status, .idle)
    }

    func testSnapshotCallbackFiresOnlyOnChange() async {
        let (engine, _, _, _) = makeEngine()
        var snapshots: [RuleEngine.Snapshot] = []
        engine.onChange = { snapshots.append($0) }
        await engine.setContact(source: "a", open: true)
        await engine.setContact(source: "a", open: true)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.openSources, ["a"])
    }
}
