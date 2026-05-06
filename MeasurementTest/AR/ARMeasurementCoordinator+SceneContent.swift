#if os(iOS)
import ARKit
import RealityKit
import UIKit

extension ARMeasurementCoordinator {
    func invalidateRenderedSceneState() {
        lastLockedSignature = ""
        lastLiveSignature = ""
    }

    func updatePointAnchor(_ anchor: inout AnchorEntity?, point: SIMD3<Float>?, in arView: ARView) {
        guard let point else {
            if let anchor { arView.scene.removeAnchor(anchor) }
            anchor = nil
            return
        }

        let anchorEntity = anchor ?? AnchorEntity(world: .zero)
        if anchorEntity.children.isEmpty {
            anchorEntity.addChild(Self.makeDotEntity(radius: 0.0035))
        }

        anchorEntity.position = point

        if anchor == nil {
            arView.scene.addAnchor(anchorEntity)
            anchor = anchorEntity
        }
    }

    func updateLine(in arView: ARView) {
        guard !viewModel.fixedPoints.isEmpty else {
            lineAnchor?.removeFromParent()
            lineAnchor = nil
            lockedContentEntity = Entity()
            liveContentEntity = Entity()
            liveDotPool.removeAll()
            invalidateRenderedSceneState()
            return
        }

        let anchorEntity = lineAnchor ?? AnchorEntity(world: .zero)
        if lineAnchor == nil {
            anchorEntity.addChild(lockedContentEntity)
            anchorEntity.addChild(liveContentEntity)
            arView.scene.addAnchor(anchorEntity)
            lineAnchor = anchorEntity
        }

        let lockedSignature = lockedMeasurementSignature(
            fixedPoints: viewModel.fixedPoints,
            identifiedShapeKind: viewModel.identifiedShapeKind
        )
        if lastLockedSignature != lockedSignature {
            lastLockedSignature = lockedSignature
            clearChildren(from: lockedContentEntity)

            if viewModel.fixedPoints.count >= 2 {
                if let identifiedShapeKind = viewModel.identifiedShapeKind {
                    populateIdentifiedShape(into: lockedContentEntity, points: viewModel.fixedPoints, kind: identifiedShapeKind)
                } else {
                    populateLockedMeasurement(into: lockedContentEntity, points: viewModel.fixedPoints)
                }
            }
        }

        let liveSignature = liveMeasurementSignature(
            start: viewModel.fixedPoints.last,
            livePoint: viewModel.shouldShowLiveSegment ? viewModel.livePoint : nil
        )
        if lastLiveSignature != liveSignature {
            lastLiveSignature = liveSignature

            if viewModel.shouldShowLiveSegment,
               let start = viewModel.fixedPoints.last,
               let end = viewModel.livePoint {
                populateLiveSegment(into: liveContentEntity, start: start, end: end)
            } else {
                hideLiveDotPool()
            }
        }

        updateBillboards()
    }

    func syncSavedMeasurements(in arView: ARView) {
        for (id, anchor) in savedMeasurementAnchors {
            arView.scene.removeAnchor(anchor)
            savedMeasurementAnchors.removeValue(forKey: id)
        }
    }

    func populateLockedMeasurement(into anchorEntity: Entity, points: [SIMD3<Float>]) {
        guard points.count >= 2 else { return }

        for index in 1..<points.count {
            populateLockedSegment(into: anchorEntity, start: points[index - 1], end: points[index])
        }

        for point in points {
            let dot = Self.makeDotEntity(radius: 0.0035)
            dot.position = point
            anchorEntity.addChild(dot)
        }
    }

    func populateIdentifiedShape(into anchorEntity: Entity, points: [SIMD3<Float>], kind: IdentifiedShapeKind) {
        if let fillEntity = Self.makeFilledShapeEntity(points: points) {
            anchorEntity.addChild(fillEntity)
        }

        populateLockedMeasurement(into: anchorEntity, points: points)
        populateLockedSegment(into: anchorEntity, start: points[points.count - 1], end: points[0])
    }

    func populateLockedSegment(into anchorEntity: Entity, start: SIMD3<Float>, end: SIMD3<Float>) {
        let delta = end - start
        let distance = simd_length(delta)
        guard distance > 0.002 else { return }

        let direction = simd_normalize(delta)

        let lineModel = Self.makeLineEntity(length: distance)
        lineModel.position = start + (delta / 2)
        lineModel.look(at: end, from: lineModel.position, relativeTo: nil)
        lineModel.orientation *= simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        anchorEntity.addChild(lineModel)

        let cmSpacing = tickSpacing(for: distance)
        let totalTicks = Int(distance / cmSpacing)

        guard totalTicks > 0 else { return }

        for index in 1...totalTicks {
            let offset = Float(index) * cmSpacing
            guard offset < distance else { break }
            let position = start + (direction * offset)

            var tickHeight: Float = 0.005
            if index % majorTickInterval(for: cmSpacing) == 0 {
                tickHeight = 0.014
                let labelValue = Int((offset * 100).rounded())
                let label = Self.makeTextEntity("\(labelValue)")
                label.position = position
                anchorEntity.addChild(label)
            } else if index % minorTickInterval(for: cmSpacing) == 0 {
                tickHeight = 0.009
            }

            let tick = Self.makeTickEntity(height: tickHeight)
            tick.position = position
            anchorEntity.addChild(tick)
        }
    }

    func populateLiveSegment(into anchorEntity: Entity, start: SIMD3<Float>, end: SIMD3<Float>) {
        let delta = end - start
        let distance = simd_length(delta)
        guard distance > 0.002 else {
            hideLiveDotPool()
            return
        }

        let direction = simd_normalize(delta)
        let midpoint = start + (delta * 0.5)
        let targetDotSpacing = dotSpacing(for: midpoint)
        let segmentCount = min(max(Int((distance / targetDotSpacing).rounded()), 1), 48)
        let dotSpacing = distance / Float(segmentCount)
        let dotCount = segmentCount + 1
        ensureLiveDotPool(count: dotCount, in: anchorEntity)

        for index in 0..<dotCount {
            let offset = Float(index) * dotSpacing
            let position = start + (direction * offset)
            let dot = liveDotPool[index]
            dot.position = position
            dot.isEnabled = true
        }

        if liveDotPool.count > dotCount {
            for index in dotCount..<liveDotPool.count {
                liveDotPool[index].isEnabled = false
            }
        }
    }

    func clearChildren(from entity: Entity) {
        for child in Array(entity.children) {
            clearChildren(from: child)
            child.removeFromParent()
        }
    }

    func tickSpacing(for distance: Float) -> Float {
        if distance < 0.5 {
            return 0.01
        }
        if distance < 1.5 {
            return 0.02
        }
        return 0.05
    }

    func minorTickInterval(for spacing: Float) -> Int {
        switch spacing {
        case ..<0.015:
            return 5
        case ..<0.03:
            return 5
        default:
            return 2
        }
    }

    func majorTickInterval(for spacing: Float) -> Int {
        switch spacing {
        case ..<0.015:
            return 10
        case ..<0.03:
            return 5
        default:
            return 2
        }
    }

    func dotSpacing(for point: SIMD3<Float>) -> Float {
        guard let cameraPosition = currentCameraPosition() else { return 0.015 }
        let distanceToCamera = simd_distance(point, cameraPosition)
        return min(max(distanceToCamera * 0.018, 0.010), 0.035)
    }

    func currentCameraPosition() -> SIMD3<Float>? {
        guard let cameraTransform = arView?.session.currentFrame?.camera.transform else { return nil }
        return SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
    }

    func lockedMeasurementSignature(fixedPoints: [SIMD3<Float>], identifiedShapeKind: IdentifiedShapeKind?) -> String {
        let fixedSignature = fixedPoints
            .map { point in
                "\(Int((point.x * 1000).rounded())):\(Int((point.y * 1000).rounded())):\(Int((point.z * 1000).rounded()))"
            }
            .joined(separator: "|")
        let shapeSignature = identifiedShapeKind.map(\.title) ?? "none"
        return "\(fixedSignature)#\(shapeSignature)"
    }

    func liveMeasurementSignature(start: SIMD3<Float>?, livePoint: SIMD3<Float>?) -> String {
        let startSignature: String
        if let start {
            startSignature = "\(Int((start.x * 1000).rounded())):\(Int((start.y * 1000).rounded())):\(Int((start.z * 1000).rounded()))"
        } else {
            startSignature = "nil"
        }

        let liveSignature: String
        if let livePoint {
            liveSignature = "\(Int((livePoint.x * 1000).rounded())):\(Int((livePoint.y * 1000).rounded())):\(Int((livePoint.z * 1000).rounded()))"
        } else {
            liveSignature = "nil"
        }

        return "\(startSignature)#\(liveSignature)"
    }

    func ensureLiveDotPool(count: Int, in anchorEntity: Entity) {
        guard liveDotPool.count < count else { return }

        for _ in liveDotPool.count..<count {
            let dot = Self.makeDotEntity(radius: 0.0022)
            dot.isEnabled = false
            liveDotPool.append(dot)
            anchorEntity.addChild(dot)
        }
    }

    func hideLiveDotPool() {
        for dot in liveDotPool {
            dot.isEnabled = false
        }
    }

    func updateBillboards() {
        guard let arView, let frame = arView.session.currentFrame else { return }

        let cameraTransform = frame.camera.transform
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        let query = EntityQuery(where: .has(BillboardComponent.self))
        arView.scene.performQuery(query).forEach { entity in
            entity.look(
                at: cameraPosition,
                from: entity.position(relativeTo: nil),
                relativeTo: nil
            )
        }

        let scalingQuery = EntityQuery(where: .has(DistanceScaledVisualComponent.self))
        arView.scene.performQuery(scalingQuery).forEach { entity in
            guard let component = entity.components[DistanceScaledVisualComponent.self] else { return }
            let distanceToCamera = simd_distance(entity.position(relativeTo: nil), cameraPosition)
            let factor = min(
                max(distanceToCamera / component.referenceDistance, component.minScale),
                component.maxScale
            )
            let scaleFactor = SIMD3<Float>(
                x: (1 - component.scaleAxes.x) + component.scaleAxes.x * factor,
                y: (1 - component.scaleAxes.y) + component.scaleAxes.y * factor,
                z: (1 - component.scaleAxes.z) + component.scaleAxes.z * factor
            )
            entity.scale = component.baseScale * scaleFactor
        }
    }
}
#endif
