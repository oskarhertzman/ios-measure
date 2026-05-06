#if os(iOS)
import ARKit
import RealityKit
import UIKit

extension ARMeasurementCoordinator {
    func invalidateRenderedSceneState() {
        lastRenderedSignature = ""
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
            invalidateRenderedSceneState()
            return
        }

        let signature = measurementSignature(
            fixedPoints: viewModel.fixedPoints,
            livePoint: viewModel.shouldShowLiveSegment ? viewModel.livePoint : nil
        )
        if lastRenderedSignature == signature {
            return
        }

        lastRenderedSignature = signature
        let anchorEntity = lineAnchor ?? AnchorEntity(world: .zero)
        anchorEntity.children.removeAll()

        if viewModel.fixedPoints.count >= 2 {
            if let identifiedShapeKind = viewModel.identifiedShapeKind {
                populateIdentifiedShape(into: anchorEntity, points: viewModel.fixedPoints, kind: identifiedShapeKind)
            } else {
                populateLockedMeasurement(into: anchorEntity, points: viewModel.fixedPoints)
            }
        }

        if viewModel.shouldShowLiveSegment,
           let start = viewModel.fixedPoints.last,
           let end = viewModel.livePoint {
            populateLiveSegment(into: anchorEntity, start: start, end: end)
        }

        if lineAnchor == nil {
            arView.scene.addAnchor(anchorEntity)
            lineAnchor = anchorEntity
        }

        updateBillboards()
    }

    func syncSavedMeasurements(in arView: ARView) {
        for (id, anchor) in savedMeasurementAnchors {
            arView.scene.removeAnchor(anchor)
            savedMeasurementAnchors.removeValue(forKey: id)
        }
    }

    func populateLockedMeasurement(into anchorEntity: AnchorEntity, points: [SIMD3<Float>]) {
        guard points.count >= 2 else { return }

        let startDot = Self.makeDotEntity(radius: 0.0035)
        startDot.position = points[0]
        anchorEntity.addChild(startDot)

        for index in 1..<points.count {
            populateLockedSegment(into: anchorEntity, start: points[index - 1], end: points[index])
        }

        let endDot = Self.makeDotEntity(radius: 0.0035)
        endDot.position = points[points.count - 1]
        anchorEntity.addChild(endDot)
    }

    func populateIdentifiedShape(into anchorEntity: AnchorEntity, points: [SIMD3<Float>], kind: IdentifiedShapeKind) {
        if let fillEntity = Self.makeFilledShapeEntity(points: points) {
            anchorEntity.addChild(fillEntity)
        }

        populateLockedMeasurement(into: anchorEntity, points: points)
        populateLockedSegment(into: anchorEntity, start: points[points.count - 1], end: points[0])
    }

    func populateLockedSegment(into anchorEntity: AnchorEntity, start: SIMD3<Float>, end: SIMD3<Float>) {
        let delta = end - start
        let distance = simd_length(delta)
        guard distance > 0.002 else { return }

        let direction = simd_normalize(delta)

        let startDot = Self.makeDotEntity(radius: 0.0035)
        startDot.position = start
        anchorEntity.addChild(startDot)

        let endDot = Self.makeDotEntity(radius: 0.0035)
        endDot.position = end
        anchorEntity.addChild(endDot)

        let lineModel = Self.makeLineEntity(length: distance)
        lineModel.position = start + (delta / 2)
        lineModel.look(at: end, from: lineModel.position, relativeTo: nil)
        lineModel.orientation *= simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        anchorEntity.addChild(lineModel)

        let cmSpacing: Float = 0.01
        let totalCm = Int(distance / cmSpacing)

        guard totalCm > 0 else { return }

        for index in 1...totalCm {
            let offset = Float(index) * cmSpacing
            let position = start + (direction * offset)

            var tickHeight: Float = 0.005
            if index % 10 == 0 {
                tickHeight = 0.014
                let label = Self.makeTextEntity("\(index)")
                label.position = position
                anchorEntity.addChild(label)
            } else if index % 5 == 0 {
                tickHeight = 0.009
            }

            let tick = Self.makeTickEntity(height: tickHeight)
            tick.position = position
            anchorEntity.addChild(tick)
        }
    }

    func populateLiveSegment(into anchorEntity: AnchorEntity, start: SIMD3<Float>, end: SIMD3<Float>) {
        let delta = end - start
        let distance = simd_length(delta)
        guard distance > 0.002 else { return }

        let direction = simd_normalize(delta)
        let dotSpacing: Float = 0.010
        let dotCount = Int(distance / dotSpacing)

        for index in 0...dotCount {
            let offset = Float(index) * dotSpacing
            let position = start + (direction * offset)
            let dot = Self.makeDotEntity(radius: 0.0022)
            dot.position = position
            anchorEntity.addChild(dot)
        }
    }

    func measurementSignature(fixedPoints: [SIMD3<Float>], livePoint: SIMD3<Float>?) -> String {
        let fixedSignature = fixedPoints
            .map { point in
                "\(Int((point.x * 1000).rounded())):\(Int((point.y * 1000).rounded())):\(Int((point.z * 1000).rounded()))"
            }
            .joined(separator: "|")

        let liveSignature: String
        if let livePoint {
            liveSignature = "\(Int((livePoint.x * 1000).rounded())):\(Int((livePoint.y * 1000).rounded())):\(Int((livePoint.z * 1000).rounded()))"
        } else {
            liveSignature = "nil"
        }

        return "\(fixedSignature)#\(liveSignature)"
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
    }
}
#endif
