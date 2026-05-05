#if os(iOS)
import ARKit
import RealityKit

extension ARMeasurementCoordinator {
    struct RaycastHit {
        let point: SIMD3<Float>
        let confidence: SurfaceConfidence
    }

    func performSceneRaycast(from screenPoint: CGPoint, in arView: ARView) -> RaycastHit? {
        guard let ray = arView.ray(through: screenPoint) else { return nil }

        let maxDistance: Float = 5.0
        let results = arView.scene.raycast(
            origin: ray.origin,
            direction: ray.direction,
            length: maxDistance,
            query: .nearest,
            mask: .all,
            relativeTo: nil
        )

        guard let hit = results.first else { return nil }

        let confidence: SurfaceConfidence
        if hit.distance < 2.0 {
            confidence = .high
        } else if hit.distance < 4.0 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return RaycastHit(point: hit.position, confidence: confidence)
    }

    func stabilizePoint(_ newPoint: SIMD3<Float>) -> SIMD3<Float> {
        recentHits.append(newPoint)

        if recentHits.count > maxRecentHits {
            recentHits.removeFirst()
        }

        guard recentHits.count >= 3 else {
            return newPoint
        }

        let sorted = recentHits.sorted { simd_length($0) < simd_length($1) }
        let trimmed = Array(sorted.dropFirst().dropLast())
        guard !trimmed.isEmpty else { return newPoint }

        let sum = trimmed.reduce(SIMD3<Float>.zero, +)
        return sum / Float(trimmed.count)
    }

    static func worldPoint(from result: ARRaycastResult) -> SIMD3<Float> {
        SIMD3<Float>(
            result.worldTransform.columns.3.x,
            result.worldTransform.columns.3.y,
            result.worldTransform.columns.3.z
        )
    }
}
#endif
