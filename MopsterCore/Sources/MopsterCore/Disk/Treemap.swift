import CoreGraphics
import Foundation

public enum Treemap {
    /// Squarified layout (Bruls, Huizing, van Wijk). `sizes` should be sorted descending.
    /// Returns one rect per input, in input order; zero or negative sizes get `.zero`.
    public static func squarify(_ sizes: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: sizes.count)
        let indices = sizes.indices.filter { sizes[$0] > 0 }
        let total = indices.reduce(0.0) { $0 + sizes[$1] }
        let area = Double(rect.width) * Double(rect.height)
        guard !indices.isEmpty, total > 0, area > 0 else { return result }

        let scale = area / total
        let areas = indices.map { sizes[$0] * scale }
        var remaining = rect
        var start = 0

        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            var rowSum = areas[start]
            var worst = worstRatio(areas[start..<end], sum: rowSum, side: side)
            while end < areas.count {
                let candidateSum = rowSum + areas[end]
                let candidate = worstRatio(areas[start...end], sum: candidateSum, side: side)
                if candidate > worst { break }
                rowSum = candidateSum
                worst = candidate
                end += 1
            }

            let isLastRow = end == areas.count
            let horizontal = remaining.width >= remaining.height
            let thickness = isLastRow
                ? (horizontal ? remaining.width : remaining.height)
                : CGFloat(rowSum / side)
            var offset: CGFloat = 0
            for position in start..<end {
                let isLastItem = isLastRow && position == end - 1
                let origin = horizontal
                    ? CGPoint(x: remaining.minX, y: remaining.minY + offset)
                    : CGPoint(x: remaining.minX + offset, y: remaining.minY)
                let full = horizontal ? remaining.height : remaining.width
                let length = isLastItem ? full - offset : CGFloat(areas[position] / Double(thickness))
                result[indices[position]] = horizontal
                    ? CGRect(x: origin.x, y: origin.y, width: thickness, height: length)
                    : CGRect(x: origin.x, y: origin.y, width: length, height: thickness)
                offset += length
            }

            if horizontal {
                remaining = CGRect(
                    x: remaining.minX + thickness, y: remaining.minY,
                    width: remaining.width - thickness, height: remaining.height)
            } else {
                remaining = CGRect(
                    x: remaining.minX, y: remaining.minY + thickness,
                    width: remaining.width, height: remaining.height - thickness)
            }
            start = end
        }
        return result
    }

    private static func worstRatio(_ row: ArraySlice<Double>, sum: Double, side: Double) -> Double {
        guard let largest = row.max(), let smallest = row.min(), sum > 0, side > 0 else { return .infinity }
        let squared = side * side
        let sumSquared = sum * sum
        return max(squared * largest / sumSquared, sumSquared / (squared * smallest))
    }
}
