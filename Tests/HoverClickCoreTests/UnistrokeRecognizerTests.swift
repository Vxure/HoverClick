import XCTest

@testable import HoverClickCore

final class UnistrokeRecognizerTests: XCTestCase {
  func testCanonicalCTemplateRecognizesItself() {
    let template = UnistrokeRecognizer.cTemplate()
    XCTAssertGreaterThan(UnistrokeRecognizer.score(template, against: template), 0.98)
  }

  func testRecognizerIsScaleAndRotationTolerant() {
    let template = UnistrokeRecognizer.cTemplate()
    let rotatedAndScaled = template.map { point in
      let angle = Double.pi / 3
      return GesturePoint(
        x: 42 + (point.x * cos(angle) - point.y * sin(angle)) * 1.8,
        y: 27 + (point.x * sin(angle) + point.y * cos(angle)) * 1.8
      )
    }
    XCTAssertGreaterThan(UnistrokeRecognizer.score(rotatedAndScaled, against: template), 0.90)
  }

  func testUnevenlySampledNoisyCIsRecognized() {
    let template = UnistrokeRecognizer.cTemplate()
    let unevenAndNoisy = (0..<37).map { index in
      let fraction = pow(Double(index) / 36.0, 1.25)
      let sourceIndex = min(template.count - 1, Int(fraction * Double(template.count - 1)))
      let point = template[sourceIndex]
      return GesturePoint(
        x: point.x + sin(Double(index) * 0.7) * 1.5,
        y: point.y + cos(Double(index) * 0.43) * 1.5
      )
    }
    XCTAssertGreaterThan(
      UnistrokeRecognizer.score(unevenAndNoisy, against: template),
      0.85
    )
  }

  func testClosedCircleIsNotStronglyRecognizedAsC() {
    let circle = (0..<64).map { index in
      let angle = Double(index) / 63.0 * 2 * Double.pi
      return GesturePoint(x: 120 * cos(angle), y: 120 * sin(angle))
    }
    XCTAssertLessThan(
      UnistrokeRecognizer.score(circle, against: UnistrokeRecognizer.cTemplate()), 0.72)
  }

  func testTooFewPointsAreRejected() {
    let shortStroke = [
      GesturePoint(x: 0, y: 0), GesturePoint(x: 1, y: 1), GesturePoint(x: 2, y: 1),
    ]
    XCTAssertEqual(
      UnistrokeRecognizer.score(shortStroke, against: UnistrokeRecognizer.cTemplate()), 0)
  }
}
