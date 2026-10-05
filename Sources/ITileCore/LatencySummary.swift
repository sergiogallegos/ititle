/// Descriptive measurements, not a deadline guarantee. Nonfinite/negative samples are rejected.
public struct LatencySummary: Sendable {
    public let count: Int
    public let minimum: Double
    public let median: Double
    public let p95: Double
    public let maximum: Double

    public init?(_ samples: [Double]) {
        guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        let sorted = samples.sorted()
        count = sorted.count
        minimum = sorted[0]; maximum = sorted[count - 1]
        median = count.isMultiple(of: 2)
            ? sorted[count / 2 - 1] / 2 + sorted[count / 2] / 2 : sorted[count / 2]
        // Nearest-rank empirical percentile. Small sample counts are reported explicitly.
        p95 = sorted[Int((Double(count) * 0.95).rounded(.up)) - 1]
    }
}
