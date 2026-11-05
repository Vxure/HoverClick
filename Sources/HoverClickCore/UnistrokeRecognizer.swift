import Foundation

/// A point in a single-stroke gesture, expressed in screen coordinates.
public struct GesturePoint: Codable, Equatable, Sendable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// A small, rotation- and scale-tolerant unistroke recognizer inspired by the
/// $1 recognizer. It intentionally recognizes one-stroke paths only.
public enum UnistrokeRecognizer {
  private static let sampleCount = 64
  private static let normalizedSize = 250.0
  private static let halfDiagonal = sqrt(2.0) * normalizedSize / 2.0

  /// Returns a confidence-like score in [0, 1]. Higher is a closer match.
  public static func score(_ candidate: [GesturePoint], against template: [GesturePoint]) -> Double
  {
    guard
      let normalizedCandidate = normalize(candidate),
      let normalizedTemplate = normalize(template)
    else { return 0 }

    let averageDistance =
      zip(normalizedCandidate, normalizedTemplate)
      .reduce(0.0) { partial, pair in partial + distance(pair.0, pair.1) }
      / Double(sampleCount)
    return max(0, min(1, 1 - averageDistance / halfDiagonal))
  }

  /// A canonical C-shaped path, drawn from the upper-right endpoint around
  /// the open left side to the lower-right endpoint.
  public static func cTemplate() -> [GesturePoint] {
    (0..<sampleCount).map { index in
      let fraction = Double(index) / Double(sampleCount - 1)
      let degrees = 300.0 - (240.0 * fraction)
      let radians = degrees * .pi / 180.0
      return GesturePoint(
        x: 125.0 + 92.0 * cos(radians),
        y: 125.0 + 105.0 * sin(radians)
      )
    }
  }

  private static func normalize(_ points: [GesturePoint]) -> [GesturePoint]? {
    guard points.count >= 5 else { return nil }
    let resampled = resample(points, count: sampleCount)
    guard resampled.count == sampleCount else { return nil }

    let center = centroid(resampled)
    let first = resampled[0]
    let indicativeAngle = atan2(first.y - center.y, first.x - center.x)
    let cosine = cos(-indicativeAngle)
    let sine = sin(-indicativeAngle)

    let rotated = resampled.map { point -> GesturePoint in
      let dx = point.x - center.x
      let dy = point.y - center.y
      return GesturePoint(
        x: dx * cosine - dy * sine,
        y: dx * sine + dy * cosine
      )
    }

    let minX = rotated.map(\.x).min() ?? 0
    let maxX = rotated.map(\.x).max() ?? 0
    let minY = rotated.map(\.y).min() ?? 0
    let maxY = rotated.map(\.y).max() ?? 0
    let width = maxX - minX
    let height = maxY - minY
    guard width > 0.0001, height > 0.0001 else { return nil }

    // The $1 algorithm uses independent X/Y scaling into a square.
    let scaled = rotated.map { point in
      GesturePoint(
        x: (point.x - minX) * normalizedSize / width,
        y: (point.y - minY) * normalizedSize / height
      )
    }
    let scaledCenter = centroid(scaled)
    return scaled.map {
      GesturePoint(x: $0.x - scaledCenter.x, y: $0.y - scaledCenter.y)
    }
  }

  private static func resample(_ points: [GesturePoint], count: Int) -> [GesturePoint] {
    guard points.count > 1, count > 1 else { return points }
    let totalLength = pathLength(points)
    guard totalLength > 0.0001 else { return [] }

    let interval = totalLength / Double(count - 1)
    var result = [points[0]]
    var distanceSinceLastSample = 0.0

    for index in 1..<points.count {
      var segmentStart = points[index - 1]
      let segmentEnd = points[index]
      var remaining = distance(segmentStart, segmentEnd)
      if remaining <= 0.000001 { continue }

      while distanceSinceLastSample + remaining >= interval {
        let needed = interval - distanceSinceLastSample
        let fraction = min(1, max(0, needed / remaining))
        let sample = GesturePoint(
          x: segmentStart.x + (segmentEnd.x - segmentStart.x) * fraction,
          y: segmentStart.y + (segmentEnd.y - segmentStart.y) * fraction
        )
        result.append(sample)
        segmentStart = sample
        remaining = distance(segmentStart, segmentEnd)
        distanceSinceLastSample = 0
        if remaining <= 0.000001 { break }
      }
      distanceSinceLastSample += remaining
    }

    if result.count == count - 1, let last = points.last { result.append(last) }
    guard let last = result.last else { return [] }
    while result.count < count { result.append(last) }
    if result.count > count { result = Array(result.prefix(count)) }
    return result
  }

  private static func centroid(_ points: [GesturePoint]) -> GesturePoint {
    let sums = points.reduce(into: (x: 0.0, y: 0.0)) { partial, point in
      partial.x += point.x
      partial.y += point.y
    }
    let divisor = Double(points.count)
    return GesturePoint(x: sums.x / divisor, y: sums.y / divisor)
  }

  private static func pathLength(_ points: [GesturePoint]) -> Double {
    guard points.count > 1 else { return 0 }
    return zip(points, points.dropFirst()).reduce(0.0) { $0 + distance($1.0, $1.1) }
  }

  private static func distance(_ lhs: GesturePoint, _ rhs: GesturePoint) -> Double {
    hypot(lhs.x - rhs.x, lhs.y - rhs.y)
  }
}
