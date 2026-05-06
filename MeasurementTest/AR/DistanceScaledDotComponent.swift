#if os(iOS)
import RealityKit

struct DistanceScaledVisualComponent: Component {
    let referenceDistance: Float
    let minScale: Float
    let maxScale: Float
    let baseScale: SIMD3<Float>
    let scaleAxes: SIMD3<Float>
}
#endif
