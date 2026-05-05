#if os(iOS)
import RealityKit
import UIKit

extension ARMeasurementCoordinator {
    static func pointMaterial(color: UIColor) -> UnlitMaterial {
        UnlitMaterial(color: color)
    }

    static func makeDotEntity(radius: Float) -> Entity {
        let mesh = MeshResource.generateCylinder(height: 0.00001, radius: radius)
        let material = UnlitMaterial(color: .white)
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])

        let container = Entity()
        container.addChild(model)
        container.components.set(BillboardComponent())
        return container
    }

    static func makeTickEntity(height: Float) -> Entity {
        let width: Float = 0.0012
        let mesh = MeshResource.generatePlane(width: width, depth: height)
        let material = UnlitMaterial(color: .white.withAlphaComponent(0.9))
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        model.position.y = -(height / 2)

        let container = Entity()
        container.addChild(model)
        container.components.set(BillboardComponent())
        return container
    }

    static func makeTextEntity(_ text: String) -> Entity {
        let mesh: MeshResource
        if let cached = textCache[text] {
            mesh = cached
        } else {
            let font = UIFont.systemFont(ofSize: 0.008, weight: .bold)
            mesh = MeshResource.generateText(text, extrusionDepth: 0.0001, font: font)
            textCache[text] = mesh
        }

        let model = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        let bounds = model.visualBounds(relativeTo: nil)
        let width = bounds.max.x - bounds.min.x
        model.position.x = -(width / 2)
        model.position.y = -0.018

        let container = Entity()
        container.addChild(model)
        container.components.set(BillboardComponent())
        return container
    }
}
#endif
