import XCTest
@testable import DesktopControlCore

final class PopupTests: XCTestCase {
    private let base = "http://192.168.1.10:8123"

    func testParseFields() {
        let r = PopupRequest.parse(#"{"title":"Front","image":"/api/camera_proxy/camera.x?token=abc","duration":999,"sound":"Ping","pause":true}"#)
        XCTAssertEqual(r?.title, "Front")
        XCTAssertEqual(r?.duration, 300)
        XCTAssertEqual(r?.sound, .named("Ping"))
        XCTAssertEqual(r?.pause, true)
        XCTAssertEqual(PopupRequest.parse("")?.title, "")
        XCTAssertNil(PopupRequest.parse("[1]"))
        XCTAssertEqual(PopupRequest.parse(#"{"sound":"../../x"}"#)?.sound, .setting)
        XCTAssertEqual(PopupRequest.parse(#"{"sound":true}"#)?.sound, .on)
    }

    func testImageURLOnlyAcceptsCameraPathsOnConfiguredHost() {
        func url(_ image: String, _ base: String? = nil) -> String? {
            PopupRequest(image: image).imageURL(base: base ?? self.base)?.absoluteString
        }
        XCTAssertEqual(url("/api/camera_proxy/camera.x?token=abc"), "http://192.168.1.10:8123/api/camera_proxy/camera.x?token=abc")
        XCTAssertEqual(url("http://192.168.1.10:8123/local/haustur.jpg"), "http://192.168.1.10:8123/local/haustur.jpg")
        XCTAssertNil(url("http://evil.example/api/camera_proxy/camera.x"))
        XCTAssertNil(url("http://192.168.1.10:9999/api/camera_proxy/camera.x"))
        XCTAssertNil(url("/api/states"))
        XCTAssertNil(url("/local/../api/states"))
        XCTAssertNil(url("/api/camera_proxy/camera.x", ""))
        XCTAssertNil(url("/api/camera_proxy/camera.x", "file:///etc"))
        XCTAssertNil(PopupRequest().imageURL(base: base))
    }

    func testSoundAndPauseResolution() {
        var config = PopupConfig(sound: "Glass", pauseMedia: false)
        XCTAssertEqual(PopupRequest().soundName(config: config), "Glass")
        XCTAssertNil(PopupRequest(sound: .off).soundName(config: config))
        XCTAssertEqual(PopupRequest(sound: .named("Ping")).soundName(config: config), "Ping")
        config.sound = ""
        XCTAssertNil(PopupRequest().soundName(config: config))
        XCTAssertEqual(PopupRequest(sound: .on).soundName(config: config), PopupConfig.fallbackSound)
        XCTAssertFalse(PopupRequest().shouldPause(config: config))
        XCTAssertTrue(PopupRequest(pause: true).shouldPause(config: config))
        XCTAssertEqual(PopupRequest().displaySeconds(config: config), 30)
    }

    func testOldConfigWithoutPopupFieldsStillLoads() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(config.popup, PopupConfig())
        XCTAssertEqual(config.haBaseURL, "")
    }

    func testPopupYAMLUsesTopicAndRejectsBadEntities() {
        let yaml = AutomationExample.popupYAML(deviceId: "mini", trigger: "x\ninjected: 1", camera: "camera.einfahrt")
        XCTAssertTrue(yaml.contains("topic: ha-desktop-control/mini/popup"))
        XCTAssertTrue(yaml.contains("state_attr('camera.einfahrt', 'entity_picture')"))
        XCTAssertFalse(yaml.contains("injected"))
    }

    func testParseStackingLevelActionsAndLimits() {
        let r = PopupRequest.parse("""
        {"id":"window-kids","level":"critical","sticky":true,"url":"/dashboard-home/home",
         "actions":[{"id":"ignore","label":"Ignore"},{"id":"bad id","label":"x"},{"id":"a","label":""},
                    {"id":"b","label":"B"},{"id":"c","label":"C"},{"id":"d","label":"D"}]}
        """)
        XCTAssertEqual(r?.id, "window-kids")
        XCTAssertEqual(r?.level, .critical)
        XCTAssertEqual(r?.sticky, true)
        XCTAssertEqual(r?.actions.map(\.id), ["ignore", "b", "c"]) // invalid entries dropped, max 3
        XCTAssertNil(r?.autoCloseSeconds(config: PopupConfig()))
        XCTAssertEqual(PopupRequest().autoCloseSeconds(config: PopupConfig()), 30)
        XCTAssertEqual(PopupRequest.parse(#"{"level":"nope","id":"a b"}"#)?.level, .info)
        XCTAssertNil(PopupRequest.parse(#"{"id":"a b"}"#)?.id)
    }

    func testOpenURLStaysOnTheHomeAssistantHost() {
        func open(_ url: String) -> String? { PopupRequest(url: url).openURL(base: base)?.absoluteString }
        XCTAssertEqual(open("/dashboard-home/home#haustuer"), "http://192.168.1.10:8123/dashboard-home/home#haustuer")
        XCTAssertEqual(open("http://192.168.1.10:8123/lovelace/0"), "http://192.168.1.10:8123/lovelace/0")
        XCTAssertNil(open("https://evil.example/x"))
        XCTAssertNil(open("//evil.example/x"))
        XCTAssertNil(open("file:///etc/passwd"))
        XCTAssertNil(open("http://192.168.1.10:9999/x"))
        XCTAssertNil(PopupRequest(url: "/x").openURL(base: ""))
    }

    func testActionYAMLRejectsUnsafeIds() {
        let yaml = AutomationExample.popupActionYAML(deviceId: "mini", popupId: "x'\nbad: 1", action: "ok")
        XCTAssertTrue(yaml.contains("topic: ha-desktop-control/mini/action"))
        XCTAssertTrue(yaml.contains("'window-kids'"))
        XCTAssertFalse(yaml.contains("bad: 1"))
    }
}

final class ImageCropTests: XCTestCase {
    func testParsesLikeAdvancedSnapshot() {
        let r = PopupRequest.parse(#"{"crop":[200,0,1000,700],"crop_aspect_ratio":"4:3"}"#)
        XCTAssertEqual(r?.crop?.rect(imageWidth: 2560, imageHeight: 1440).map { [$0.x, $0.y, $0.width, $0.height] }, [200, 0, 1000, 750])
        let plain = PopupRequest.parse(#"{"crop":[10,20,300,200]}"#)
        XCTAssertEqual(plain?.crop?.rect(imageWidth: 640, imageHeight: 480).map { [$0.x, $0.y, $0.width, $0.height] }, [10, 20, 300, 200])
    }

    func testRejectsBadValues() {
        for payload in [#"{"crop":[1,2]}"#, #"{"crop":[-1,0,10,10]}"#, #"{"crop":[0,0,0,10]}"#,
                        #"{"crop":[true,0,10,10]}"#, #"{"crop":"1,2,3"}"#,
                        #"{"crop":[0,0,10],"crop_aspect_ratio":"x"}"#, #"{"crop":[0,0,10],"crop_aspect_ratio":"0:3"}"#] {
            XCTAssertNil(PopupRequest.parse(payload)?.crop, payload)
        }
        XCTAssertNil(PopupRequest.parse(#"{"title":"x"}"#)?.crop)
    }

    func testRectNeedsToFitImage() {
        let crop = ImageCrop(x: 200, y: 0, width: 1000, aspect: (4, 3))
        XCTAssertNil(crop.rect(imageWidth: 1000, imageHeight: 1440))
        XCTAssertNil(crop.rect(imageWidth: 2560, imageHeight: 700))
        XCTAssertNil(ImageCrop(x: 0, y: 0, width: 10).rect(imageWidth: 100, imageHeight: 100)) // no height, no ratio
    }
}
