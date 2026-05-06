#if os(iOS)
import RealityKit
import UIKit

extension ARMeasurementCoordinator {
    private static let whiteDotMaterial = UnlitMaterial(color: .white)
    private static let tickMaterial = UnlitMaterial(color: .white.withAlphaComponent(0.9))
    private static let textMaterial = UnlitMaterial(color: .white)
    private static let fillMaterial = SimpleMaterial(color: .white.withAlphaComponent(0.18), isMetallic: false)
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
        container.components.set(
            DistanceScaledVisualComponent(
                referenceDistance: 0.7,
                minScale: 0.55,
                maxScale: 1.8,
                baseScale: SIMD3<Float>(repeating: 1),
                scaleAxes: SIMD3<Float>(repeating: 1)
            )
        )
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
        container.components.set(
            DistanceScaledVisualComponent(
                referenceDistance: 0.8,
                minScale: 0.75,
                maxScale: 2.0,
                baseScale: SIMD3<Float>(repeating: 1),
                scaleAxes: SIMD3<Float>(repeating: 1)
            )
        )
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
        container.components.set(
            DistanceScaledVisualComponent(
                referenceDistance: 0.8,
                minScale: 0.8,
                maxScale: 2.2,
                baseScale: SIMD3<Float>(repeating: 1),
                scaleAxes: SIMD3<Float>(repeating: 1)
            )
        )
        return container
    }

    static func makeLineEntity(length: Float) -> ModelEntity {
        let mesh = cachedLineMesh(length: length)
        let model = ModelEntity(mesh: mesh, materials: [whiteDotMaterial])
        model.components.set(
            DistanceScaledVisualComponent(
                referenceDistance: 0.8,
                minScale: 0.8,
                maxScale: 2.4,
                baseScale: SIMD3<Float>(repeating: 1),
                scaleAxes: SIMD3<Float>(1, 0, 1)
            )
        )
        return model
    }

    static func makeFilledShapeEntity(points: [SIMD3<Float>]) -> ModelEntity? {
        guard let mesh = filledShapeMesh(points: points) else { return nil }
        return ModelEntity(mesh: mesh, materials: [fillMaterial])
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

    private static func filledShapeMesh(points: [SIMD3<Float>]) -> MeshResource? {
        guard points.count == 3 || points.count == 4 else { return nil }

        var descriptor = MeshDescriptor(name: "identified-shape")
        descriptor.positions = MeshBuffers.Positions(points)

        if points.count == 3 {
            descriptor.primitives = .triangles([0, 1, 2])
        } else {
            descriptor.primitives = .triangles([0, 1, 2, 0, 2, 3])
        }

        return try? MeshResource.generate(from: [descriptor])
    }
}
#endif
