#if os(iOS)
import RealityKit
import UIKit

extension ARMeasurementCoordinator {
    private static let whiteDotMaterial = UnlitMaterial(color: .white)
    private static let tickMaterial = UnlitMaterial(color: .white.withAlphaComponent(0.9))
    private static let textMaterial = UnlitMaterial(color: .white)
    private static var dotMeshCache: [Float: MeshResource] = [:]
    private static var tickMeshCache: [Float: MeshResource] = [:]
    private static var lineMeshCache: [Int: MeshResource] = [:]

    static func makeDotEntity(radius: Float) -> Entity {
        let mesh = cachedDotMesh(radius: radius)
        let model = ModelEntity(mesh: mesh, materials: [whiteDotMaterial])
        model.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])

        let container = Entity()
        container.addChild(model)
        container.components.set(BillboardComponent())
        return container
    }

    static func makeTickEntity(height: Float) -> Entity {
        let width: Float = 0.0012
        let mesh = cachedTickMesh(height: height, width: width)
        let model = ModelEntity(mesh: mesh, materials: [tickMaterial])
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

        let model = ModelEntity(mesh: mesh, materials: [textMaterial])
        model.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        let bounds = model.visualBounds(relativeTo: nil)
        let width = bounds.max.x - bounds.min.x
        model.position.x = -(width / 2)
        model.position.y = -0.018

        let container = Entity()
        container.addChild(model)
        container.components.set(BillboardComponent())
        return container
    }

    static func makeLineEntity(length: Float) -> ModelEntity {
        let mesh = cachedLineMesh(length: length)
        return ModelEntity(mesh: mesh, materials: [whiteDotMaterial])
    }

    private static func cachedDotMesh(radius: Float) -> MeshResource {
        if let mesh = dotMeshCache[radius] {
            return mesh
        }

        let mesh = MeshResource.generateCylinder(height: 0.00001, radius: radius)
        dotMeshCache[radius] = mesh
        return mesh
    }

    private static func cachedTickMesh(height: Float, width: Float) -> MeshResource {
        if let mesh = tickMeshCache[height] {
            return mesh
        }

        let mesh = MeshResource.generateBox(size: [width, height, 0.00035])
        tickMeshCache[height] = mesh
        return mesh
    }

    private static func cachedLineMesh(length: Float) -> MeshResource {
        let quantizedLength = Int((length * 1_000).rounded())
        if let mesh = lineMeshCache[quantizedLength] {
            return mesh
        }

        let mesh = MeshResource.generateCylinder(height: Float(quantizedLength) / 1_000, radius: 0.0008)
        lineMeshCache[quantizedLength] = mesh
        return mesh
    }
}
#endif
