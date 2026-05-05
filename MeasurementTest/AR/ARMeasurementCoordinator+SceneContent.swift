#if os(iOS)
import ARKit
import RealityKit
import UIKit

extension ARMeasurementCoordinator {
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
        guard let start = viewModel.startPoint, let end = viewModel.endPoint ?? viewModel.livePoint else {
            lineAnchor?.removeFromParent()
            lineAnchor = nil
            return
        }

        let delta = end - start
        let distance = simd_length(delta)
        guard distance > 0.002 else { return }

        let direction = simd_normalize(delta)
        let anchorEntity = lineAnchor ?? AnchorEntity(world: .zero)
        anchorEntity.children.removeAll()

        if viewModel.endPoint == nil {
            let dotSpacing: Float = 0.010
            let dotCount = Int(distance / dotSpacing)

            for index in 0...dotCount {
                let offset = Float(index) * dotSpacing
                let position = start + (direction * offset)
                let dot = Self.makeDotEntity(radius: 0.0022)
                dot.position = position
                anchorEntity.addChild(dot)
            }
        } else {
            let lineMesh = MeshResource.generateCylinder(height: distance, radius: 0.0008)
            let lineModel = ModelEntity(mesh: lineMesh, materials: [UnlitMaterial(color: .white)])
            lineModel.position = start + (delta / 2)
            lineModel.look(at: end, from: lineModel.position, relativeTo: nil)
            lineModel.orientation *= simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            anchorEntity.addChild(lineModel)

            let cmSpacing: Float = 0.01
            let totalCm = Int(distance / cmSpacing)

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

        if lineAnchor == nil {
            arView.scene.addAnchor(anchorEntity)
            lineAnchor = anchorEntity
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
    }
}
#endif
