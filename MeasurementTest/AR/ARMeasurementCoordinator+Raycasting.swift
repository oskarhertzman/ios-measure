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

    func stabilizePoint(_ newPoint: SIMD3<Float>, baseConfidence: SurfaceConfidence) -> RaycastHit {
        recentHits.append(newPoint)

        if recentHits.count > maxRecentHits {
            recentHits.removeFirst()
        }

        guard recentHits.count >= 3 else {
            return RaycastHit(point: newPoint, confidence: cappedConfidence(baseConfidence, maximum: .medium))
        }

        let provisionalCenter = averagePoint(for: recentHits)
        let filteredHits = recentHits.filter { simd_distance($0, provisionalCenter) <= 0.02 }
        let stableHits = filteredHits.count >= 3 ? filteredHits : recentHits
        let stabilizedPoint = averagePoint(for: stableHits)
        let maxSpread = stableHits
            .map { simd_distance($0, stabilizedPoint) }
            .max() ?? 0

        return RaycastHit(
            point: stabilizedPoint,
            confidence: adjustedConfidence(
                from: baseConfidence,
                maxSpread: maxSpread,
                sampleCount: stableHits.count
            )
        )
    }

    func averagePoint(for points: [SIMD3<Float>]) -> SIMD3<Float> {
        let sum = points.reduce(SIMD3<Float>.zero, +)
        return sum / Float(points.count)
    }

    func adjustedConfidence(from baseConfidence: SurfaceConfidence, maxSpread: Float, sampleCount: Int) -> SurfaceConfidence {
        let spreadConfidence: SurfaceConfidence
        switch maxSpread {
        case ..<0.006:
            spreadConfidence = .high
        case ..<0.014:
            spreadConfidence = .medium
        default:
            spreadConfidence = .low
        }

        let sampleConfidence: SurfaceConfidence = sampleCount >= 4 ? .high : .medium

        if spreadConfidence == .low {
            if baseConfidence == .high, maxSpread < 0.02 {
                return .medium
            }
            return minimumConfidence(baseConfidence, .medium, sampleConfidence)
        }

        if spreadConfidence == .medium {
            return minimumConfidence(baseConfidence, .high, sampleConfidence)
        }

        return minimumConfidence(baseConfidence, spreadConfidence, sampleConfidence)
    }

    func cappedConfidence(_ confidence: SurfaceConfidence, maximum: SurfaceConfidence) -> SurfaceConfidence {
        minimumConfidence(confidence, maximum)
    }

    func minimumConfidence(_ confidences: SurfaceConfidence...) -> SurfaceConfidence {
        confidences.min(by: { confidenceRank($0) < confidenceRank($1) }) ?? .unknown
    }

    func confidenceRank(_ confidence: SurfaceConfidence) -> Int {
        switch confidence {
        case .unknown:
            return 0
        case .low:
            return 1
        case .medium:
            return 2
        case .high:
            return 3
        }
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
