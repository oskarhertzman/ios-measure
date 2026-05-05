#if os(iOS)
import Foundation
import simd

struct SavedMeasurement: Identifiable, Equatable {
    let id: UUID
    let name: String
    let points: [SIMD3<Float>]

    init(id: UUID = UUID(), name: String, points: [SIMD3<Float>]) {
        self.id = id
        self.name = name
        self.points = points
    }

    var lengthMeters: Float {
        guard points.count >= 2 else { return 0 }

        var meters: Float = 0
        for index in 1..<points.count {
            meters += simd_distance(points[index - 1], points[index])
        }
        return meters
    }

    var lengthText: String {
        if lengthMeters >= 1 {
            return String(format: "%.2f m", lengthMeters)
        }
        return String(format: "%.1f cm", lengthMeters * 100)
    }
}
#endif
