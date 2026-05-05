#if os(iOS)
import Foundation

struct SavedMeasurement: Identifiable, Equatable {
    let id: UUID
    let points: [SIMD3<Float>]

    init(id: UUID = UUID(), points: [SIMD3<Float>]) {
        self.id = id
        self.points = points
    }
}
#endif
