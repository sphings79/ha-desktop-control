import XCTest
@testable import DesktopControlCore

final class LocalizationTests: XCTestCase {
    private func appSources() throws -> String {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/HADesktopControl")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    private func placeholders(_ text: String) -> Int {
        text.components(separatedBy: "%@").count - 1
    }

    func testEveryKeyUsedInTheAppHasAGermanTranslation() throws {
        let source = try appSources()
        let regex = try NSRegularExpression(pattern: #"\bt\(\s*"((?:[^"\\]|\\.)*)""#)
        let range = NSRange(source.startIndex..., in: source)
        var keys = Set(regex.matches(in: source, range: range).compactMap { match -> String? in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        })
        keys.formUnion(["Overview", "Triggers", "Programs", "MQTT", "General"]) // page titles live in an enum
        XCTAssertGreaterThan(keys.count, 50, "key scan found suspiciously few strings")
        let missing = keys.filter { L10n.de[$0] == nil }.sorted()
        XCTAssertTrue(missing.isEmpty, "missing German translations: \(missing)")
    }

    func testNoStaleTranslations() throws {
        let source = try appSources()
        let stale = L10n.de.keys.filter { !source.contains("\"\($0)\"") }.sorted()
        XCTAssertTrue(stale.isEmpty, "translations no longer used: \(stale)")
    }

    func testPlaceholderCountsMatch() {
        for (key, value) in L10n.de {
            XCTAssertEqual(placeholders(key), placeholders(value), "placeholder mismatch in “\(key)”")
        }
    }

    func testFormatting() {
        XCTAssertEqual(L10n.tr("Active: %@", ["door"], language: .en), "Active: door")
        XCTAssertEqual(L10n.tr("Active: %@", ["door"], language: .de), "Aktiv: door")
        XCTAssertEqual(L10n.tr("%@:%@ · device “%@”", ["h", "1883", "mac"], language: .de), "h:1883 · Gerät „mac“")
        XCTAssertEqual(L10n.tr("Unknown key", language: .de), "Unknown key")
    }

    func testResolve() {
        XCTAssertEqual(L10n.resolve(.system, preferred: ["de-DE", "en"]), .de)
        XCTAssertEqual(L10n.resolve(.system, preferred: ["fr-FR"]), .en)
        XCTAssertEqual(L10n.resolve(.system, preferred: []), .en)
        XCTAssertEqual(L10n.resolve(.en, preferred: ["de"]), .en)
        XCTAssertEqual(L10n.resolve(.de, preferred: ["en"]), .de)
    }
}

final class VersionTests: XCTestCase {
    func testOrdering() {
        XCTAssertLessThan(AppVersion("0.1.0")!, AppVersion("0.2.0")!)
        XCTAssertLessThan(AppVersion("v1.9")!, AppVersion("v1.10")!)
        XCTAssertEqual(AppVersion("0.1")!, AppVersion("0.1.0")!)
        XCTAssertEqual(AppVersion("0.2.0-rc.1")!, AppVersion("0.2.0")!)
        XCTAssertNil(AppVersion("dev"))
        XCTAssertNil(AppVersion(""))
    }

    func testReleaseParsing() {
        let good = #"{"tag_name":"v0.2.0","html_url":"https://github.com/sphings79/ha-desktop-control/releases/tag/v0.2.0"}"#
        XCTAssertEqual(ReleaseInfo.parse(Data(good.utf8))?.version, AppVersion("0.2.0"))
        let foreign = #"{"tag_name":"v9.9.9","html_url":"https://evil.example/download"}"#
        XCTAssertNil(ReleaseInfo.parse(Data(foreign.utf8)), "links outside the repository must be rejected")
        XCTAssertNil(ReleaseInfo.parse(Data(#"{"tag_name":"nightly","html_url":"https://github.com/sphings79/ha-desktop-control/x"}"#.utf8)))
        XCTAssertNil(ReleaseInfo.parse(Data("not json".utf8)))
    }
}

final class AutomationExampleTests: XCTestCase {
    func testEntityValidation() {
        XCTAssertTrue(AutomationExample.isValidEntityId("binary_sensor.office_door_contact"))
        XCTAssertTrue(AutomationExample.isValidEntityId("input_boolean.1st_floor"))
        XCTAssertFalse(AutomationExample.isValidEntityId("binary_sensor.x\ninjected: true"))
        XCTAssertFalse(AutomationExample.isValidEntityId("Binary_Sensor.Door"))
        XCTAssertFalse(AutomationExample.isValidEntityId("nodot"))
        XCTAssertFalse(AutomationExample.isValidEntityId(""))
    }

    func testYAMLContainsTopicsAndEntity() {
        let yaml = AutomationExample.yaml(deviceId: "Mac Mini", source: "office_door", entity: "binary_sensor.door")
        XCTAssertTrue(yaml.contains("topic: ha-desktop-control/mac_mini/contact/office_door"))
        XCTAssertTrue(yaml.contains("entity_id: binary_sensor.door"))
        XCTAssertTrue(yaml.contains("payload: open"))
        XCTAssertTrue(yaml.contains("payload: closed"))
        XCTAssertEqual(yaml.components(separatedBy: "retain: true").count - 1, 2)
    }

    func testInvalidEntityFallsBackToPlaceholder() {
        let yaml = AutomationExample.yaml(deviceId: "mac", source: "x", entity: "evil\n  - action: shell")
        XCTAssertTrue(yaml.contains(AutomationExample.placeholderEntity))
        XCTAssertFalse(yaml.contains("shell"))
    }
}
