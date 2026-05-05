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
        viewModel.isLidarAvailable = lidarSupported

        guard lidarSupported else {
            viewModel.setAvailability(
                isLidarAvailable: false,
                message: "This app requires LiDAR for precise surface measurement."
            )
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic

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

        if viewModel.endPoint != nil {
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
            let stabilizedPoint = stabilizePoint(hitPoint)
            didUpdateLivePoint = viewModel.updateLivePoint(stabilizedPoint, confidence: confidence)
        } else {
            recentHits.removeAll()
            didUpdateLivePoint = viewModel.updateLivePoint(nil, confidence: .unknown)
        }

        guard didUpdateLivePoint else { return }
        syncSceneContent()
    }
}
#endif
