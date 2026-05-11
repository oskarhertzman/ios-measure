#if os(iOS)
import ARKit
import RealityKit
import UIKit

extension ARMeasurementCoordinator: ARSessionDelegate {
    func configureSession(for arView: ARView) {
        guard ARWorldTrackingConfiguration.isSupported else {
            viewModel.setAvailability(
                isLidarAvailable: false,
                message: "ARKit world tracking is unavailable on this device."
            )
            return
        }

        let lidarSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
		
		Task { @MainActor in
			if !lidarSupported {
				viewModel.setAvailability(
					isLidarAvailable: false,
					message: "This app requires LiDAR for precise surface measurement."
				)
			}
		}

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .none

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        } else {
            configuration.sceneReconstruction = .mesh
        }

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }

        currentSessionConfiguration = configuration
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        arView.environment.sceneUnderstanding.options = [.occlusion, .physics, .collision]
        arView.renderOptions.insert(.disableMotionBlur)
    }

    func configureCoaching(for arView: ARView) {
        let coachingView = ARCoachingOverlayView()
        coachingView.session = arView.session
        coachingView.goal = .anyPlane
        coachingView.activatesAutomatically = true
        coachingView.translatesAutoresizingMaskIntoConstraints = false

        arView.addSubview(coachingView)
        NSLayoutConstraint.activate([
            coachingView.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coachingView.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
            coachingView.topAnchor.constraint(equalTo: arView.topAnchor),
            coachingView.bottomAnchor.constraint(equalTo: arView.bottomAnchor)
        ])
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    addMeshEntity(for: meshAnchor)
                }
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    updateMeshEntity(for: meshAnchor)
                }
            }
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    removeMeshEntity(for: meshAnchor)
                }
            }
        }
    }

    func addMeshEntity(for meshAnchor: ARMeshAnchor) {
        guard let arView else { return }

        let entity = ModelEntity()
        entity.transform = Transform(matrix: meshAnchor.transform)

        Task(priority: .low) { [weak self, weak entity] in
            guard let self, let entity else { return }
            guard let shape = try? await ShapeResource.generateStaticMesh(from: meshAnchor) else { return }

            await MainActor.run {
                guard self.meshEntities[meshAnchor.identifier] === entity else { return }
                entity.collision = CollisionComponent(shapes: [shape], isStatic: true)
                entity.physicsBody = PhysicsBodyComponent(shapes: [shape], mass: 0, mode: .static)
            }
        }

        meshEntities[meshAnchor.identifier] = entity
        let anchorEntity = AnchorEntity(world: meshAnchor.transform)
        anchorEntity.addChild(entity)
        arView.scene.addAnchor(anchorEntity)
    }

    func updateMeshEntity(for meshAnchor: ARMeshAnchor) {
        guard let entity = meshEntities[meshAnchor.identifier] else {
            addMeshEntity(for: meshAnchor)
            return
        }

        entity.transform = Transform(matrix: meshAnchor.transform)

        Task(priority: .low) { [weak self, weak entity] in
            guard let self, let entity else { return }
            guard let shape = try? await ShapeResource.generateStaticMesh(from: meshAnchor) else { return }

            await MainActor.run {
                guard self.meshEntities[meshAnchor.identifier] === entity else { return }
                entity.collision = CollisionComponent(shapes: [shape], isStatic: true)
            }
        }
    }

    func removeMeshEntity(for meshAnchor: ARMeshAnchor) {
        meshEntities[meshAnchor.identifier]?.removeFromParent()
        meshEntities.removeValue(forKey: meshAnchor.identifier)
    }

    @objc
    func handleTap() {
        viewModel.placeCurrentPoint()
        invalidateRenderedSceneState()
        syncSceneContent()
    }

    @objc
    func updateLiveMeasurement() {
        frameCounter += 1
        guard frameCounter % 2 == 0 else { return }

        guard let arView, viewModel.isLidarAvailable else { return }
        defer { updateBillboards() }

        if arView.bounds.size == .zero {
            return
        }

        if viewModel.isSceneUpdatesSuspended {
            return
        }

        if viewModel.hasCompletedMeasurement {
            return
        }

        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)

        var hitPoint: SIMD3<Float>?
        var confidence: SurfaceConfidence = .unknown

        if let result = performSceneRaycast(from: center, in: arView) {
            hitPoint = result.point
            confidence = result.confidence
        } else if let result = arView.raycast(from: center, allowing: .existingPlaneGeometry, alignment: .any).first {
            hitPoint = Self.worldPoint(from: result)
            confidence = .medium
        } else if let result = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first {
            hitPoint = Self.worldPoint(from: result)
            confidence = .low
        }

        let didUpdateLivePoint: Bool
        if let hitPoint {
            let stabilizedHit = stabilizePoint(hitPoint, baseConfidence: confidence)
            let rightAngleSnappedPoint = snapToRightAngleIfNeeded(stabilizedHit.point)
            let rectangleSnappedPoint = snapToRectangleCompletionIfNeeded(rightAngleSnappedPoint)
            let snappedPoint = snapToExistingPointIfNeeded(rectangleSnappedPoint)
            didUpdateLivePoint = viewModel.updateLivePoint(snappedPoint, confidence: stabilizedHit.confidence)
        } else {
            recentHits.removeAll()
            currentSnapTarget = nil
            currentRectangleSnapTarget = nil
            isRightAngleSnapActive = false
            didUpdateLivePoint = viewModel.updateLivePoint(nil, confidence: .unknown)
        }

        guard didUpdateLivePoint else { return }
        syncSceneContent()
    }

    func snapToExistingPointIfNeeded(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let snapThreshold: Float = 0.02
        let candidatePoints = viewModel.fixedPoints + viewModel.savedMeasurements.flatMap(\.points)

        guard let nearestPoint = candidatePoints.min(by: {
            simd_distance($0, point) < simd_distance($1, point)
        }) else {
            currentSnapTarget = nil
            return point
        }

        guard simd_distance(nearestPoint, point) <= snapThreshold else {
            currentSnapTarget = nil
            return point
        }

        if shouldTriggerSnapFeedback(for: nearestPoint) {
            snapFeedbackGenerator.impactOccurred()
            snapFeedbackGenerator.prepare()
        }

        currentSnapTarget = nearestPoint
        return nearestPoint
    }

    func snapToRightAngleIfNeeded(_ point: SIMD3<Float>) -> SIMD3<Float> {
        guard viewModel.fixedPoints.count >= 2 else {
            isRightAngleSnapActive = false
            return point
        }

        let segmentStart = viewModel.fixedPoints[viewModel.fixedPoints.count - 1]
        let previousPoint = viewModel.fixedPoints[viewModel.fixedPoints.count - 2]
        let previousSegment = segmentStart - previousPoint
        let previousLength = simd_length(previousSegment)
        guard previousLength > 0.0001 else {
            isRightAngleSnapActive = false
            return point
        }

        let rawSegment = point - segmentStart
        let rawLength = simd_length(rawSegment)
        guard rawLength > 0.0001 else {
            isRightAngleSnapActive = false
            return point
        }

        let previousDirection = previousSegment / previousLength
        let alignment = abs(simd_dot(rawSegment / rawLength, previousDirection))
        let rightAngleThreshold: Float = 0.18
        guard alignment <= rightAngleThreshold else {
            isRightAngleSnapActive = false
            return point
        }

        let perpendicularSegment = rawSegment - simd_dot(rawSegment, previousDirection) * previousDirection
        guard simd_length_squared(perpendicularSegment) > 0.000001 else {
            isRightAngleSnapActive = false
            return point
        }

        isRightAngleSnapActive = true
        return segmentStart + perpendicularSegment
    }

    func snapToRectangleCompletionIfNeeded(_ point: SIMD3<Float>) -> SIMD3<Float> {
        guard viewModel.fixedPoints.count == 3 else {
            currentRectangleSnapTarget = nil
            return point
        }

        let a = viewModel.fixedPoints[0]
        let b = viewModel.fixedPoints[1]
        let c = viewModel.fixedPoints[2]

        let firstEdge = b - a
        let secondEdge = c - b
        let firstEdgeLength = simd_length(firstEdge)
        let secondEdgeLength = simd_length(secondEdge)
        guard firstEdgeLength > 0.001, secondEdgeLength > 0.001 else {
            currentRectangleSnapTarget = nil
            return point
        }

        let normalizedFirstEdge = firstEdge / firstEdgeLength
        let normalizedSecondEdge = secondEdge / secondEdgeLength
        let rightAngleTolerance: Float = 0.2
        guard abs(simd_dot(normalizedFirstEdge, normalizedSecondEdge)) <= rightAngleTolerance else {
            currentRectangleSnapTarget = nil
            return point
        }

        let targetCorner = a + secondEdge
        let snapThreshold: Float = 0.035
        guard simd_distance(point, targetCorner) <= snapThreshold else {
            currentRectangleSnapTarget = nil
            return point
        }

        if shouldTriggerRectangleSnapFeedback(for: targetCorner) {
            snapFeedbackGenerator.impactOccurred()
            snapFeedbackGenerator.prepare()
        }

        currentRectangleSnapTarget = targetCorner
        return targetCorner
    }

    func shouldTriggerSnapFeedback(for point: SIMD3<Float>) -> Bool {
        guard let currentSnapTarget else { return true }
        return simd_distance(currentSnapTarget, point) > 0.001
    }

    func shouldTriggerRectangleSnapFeedback(for point: SIMD3<Float>) -> Bool {
        guard let currentRectangleSnapTarget else { return true }
        return simd_distance(currentRectangleSnapTarget, point) > 0.001
    }
}
#endif
