import XCTest
@testable import Gophy

final class LanguageDetectorTests: XCTestCase {
    var detector: LanguageDetector!

    override func setUp() async throws {
        try await super.setUp()
        detector = LanguageDetector()
    }

    override func tearDown() async throws {
        detector = nil
        try await super.tearDown()
    }

    func testDetectEnglishText() {
        let result = detector.detect(text: "Hello, how are you doing today?")
        XCTAssertEqual(result, .english)
    }

    func testDetectSpanishText() {
        let result = detector.detect(text: "Hola, como estas hoy? Estoy muy bien gracias.")
        XCTAssertEqual(result, .spanish)
    }

    func testDetectRussianText() {
        let result = detector.detect(text: "Привет, как у тебя дела сегодня?")
        XCTAssertEqual(result, .russian)
    }

    func testDetectEmptyStringReturnsNil() {
        let result = detector.detect(text: "")
        XCTAssertNil(result)
    }

    func testDetectShortTextReturnsNil() {
        let result = detector.detect(text: "Hi")
        XCTAssertNil(result)
    }

    func testDetectWithConfidenceReturnsMultipleHypotheses() {
        let results = detector.detectWithConfidence(text: "Hello, how are you doing today? I am fine, thank you.", maxHypotheses: 3)
        XCTAssertFalse(results.isEmpty)

        // First result should be English
        if let first = results.first {
            XCTAssertEqual(first.0, .english)
            XCTAssertGreaterThan(first.1, 0.0)
        }
    }

    func testDetectWithConfidenceEmptyStringReturnsEmpty() {
        let results = detector.detectWithConfidence(text: "", maxHypotheses: 3)
        XCTAssertTrue(results.isEmpty)
    }

    func testISOCodeEnglish() {
        XCTAssertEqual(AppLanguage.english.isoCode, "en")
    }

    func testISOCodeRussian() {
        XCTAssertEqual(AppLanguage.russian.isoCode, "ru")
    }

    func testISOCodeSpanish() {
        XCTAssertEqual(AppLanguage.spanish.isoCode, "es")
    }

    func testISOCodeAutoIsNil() {
        XCTAssertNil(AppLanguage.auto.isoCode)
    }
}
