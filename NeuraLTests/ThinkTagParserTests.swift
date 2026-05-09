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

    // MARK: - Delimiter stripping

    func testStripsImEndDelimiter() {
        let p = ThinkTagParser.parse("<think>ok</think>Here is the answer<|im_end|>")
        XCTAssertEqual(p.answer, "Here is the answer")
        XCTAssertEqual(p.reasoningTrace, "ok")
    }

    func testStripsEndoftextDelimiter() {
        let p = ThinkTagParser.parse("<think>ok</think>Done<|endoftext|>")
        XCTAssertEqual(p.answer, "Done")
    }

    func testStripsClosingSlashSDelimiter() {
        let p = ThinkTagParser.parse("<think>ok</think>Result</s>")
        XCTAssertEqual(p.answer, "Result")
    }

    func testStripsLeadingImStartAssistant() {
        let p = ThinkTagParser.parse("<think>ok</think><|im_start|>assistant\nHello")
        XCTAssertEqual(p.answer, "Hello")
    }

    func testStripsRepeatedDelimiters() {
        let p = ThinkTagParser.parse("<think>ok</think>Text<|im_end|><|im_end|>")
        XCTAssertEqual(p.answer, "Text")
    }

    func testPreservesNormalText() {
        let p = ThinkTagParser.parse("This is a normal response without any special tokens.")
        XCTAssertEqual(p.answer, "This is a normal response without any special tokens.")
        XCTAssertNil(p.reasoningTrace)
        XCTAssertFalse(p.isInsideThought)
    }

    func testPreservesTextWithAngleBrackets() {
        let p = ThinkTagParser.parse("Use <div> tags for HTML. x < y for all y > 3.")
        XCTAssertTrue(p.answer.contains("<div>"))
        XCTAssertTrue(p.answer.contains("x < y"))
    }
}
