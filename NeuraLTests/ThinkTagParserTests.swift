import XCTest
@testable import NeuraL

final class ThinkTagParserTests: XCTestCase {
    func testNoTags() {
        let p = ThinkTagParser.parse("Hello </think> world")
        XCTAssertEqual(p.answer, "Hello  world")
        XCTAssertNil(p.reasoningTrace)
    }

    func testClosedTags() {
        let p = ThinkTagParser.parse("<think>reasoning</think>answer")
        XCTAssertEqual(p.reasoningTrace, "reasoning")
        XCTAssertEqual(p.answer, "answer")
        XCTAssertTrue(p.didCloseThought)
    }

    func testUnclosedTags() {
        let p = ThinkTagParser.parse("<think>reasoning")
        XCTAssertTrue(p.isInsideThought)
        XCTAssertEqual(p.reasoningTrace, "reasoning")
    }

    func testLooseClosingTag() {
        let p = ThinkTagParser.parse("abc</think>def")
        XCTAssertEqual(p.answer, "abcdef")
    }
}
