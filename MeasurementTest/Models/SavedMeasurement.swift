#if os(iOS)
import Foundation
import simd

struct SavedMeasurement: Identifiable, Equatable {
    let id: UUID
    let name: String
    let points: [SIMD3<Float>]

    init(id: UUID = UUID(), name: String, points: [SIMD3<Float>]) {
        self.id = id
        self.name = name
        self.points = points
    }

    var lengthMeters: Float {
        guard points.count >= 2 else { return 0 }

        var meters: Float = 0
        for index in 1..<points.count {
            meters += simd_distance(points[index - 1], points[index])
        }
        return meters
    }

    var lengthText: String {
        if identifiedShapeKind != nil {
            if areaSquareMeters >= 0.1 {
                return String(format: "%.2f m²", areaSquareMeters)
            }
            let squareCentimeters = areaSquareMeters * 10_000
            return String(format: "%.1f cm²", squareCentimeters)
        }

        if lengthMeters >= 1 {
            return String(format: "%.2f m", lengthMeters)
        }
        return String(format: "%.1f cm", lengthMeters * 100)
    }

    var identifiedShapeKind: IdentifiedShapeKind? {
        switch points.count {
        case 3:
            return .triangle
        case 4:
            return isValidRectangle(points: points) ? .rectangle : nil
        default:
            return nil
        }
    }

    var areaSquareMeters: Float {
        guard let identifiedShapeKind else { return 0 }

        switch identifiedShapeKind {
        case .triangle:
            return polygonArea(points: points)
        case .rectangle:
            return rectangleArea(points: points)
        }
    }

    private func polygonArea(points: [SIMD3<Float>]) -> Float {
        let normal = polygonNormal(points: points)
        guard simd_length(normal) > 0.0001 else { return 0 }

        let projectedPoints = projected2DPoints(for: points, normal: simd_normalize(normal))
        guard projectedPoints.count >= 3 else { return 0 }

        var twiceArea: Float = 0
        for index in 0..<projectedPoints.count {
            let current = projectedPoints[index]
            let next = projectedPoints[(index + 1) % projectedPoints.count]
            twiceArea += (current.x * next.y) - (next.x * current.y)
        }

        return abs(twiceArea) * 0.5
    }

    private func rectangleArea(points: [SIMD3<Float>]) -> Float {
        guard points.count == 4 else { return 0 }

        let width = (simd_distance(points[0], points[1]) + simd_distance(points[2], points[3])) * 0.5
        let height = (simd_distance(points[1], points[2]) + simd_distance(points[3], points[0])) * 0.5
        return width * height
    }

    private func isValidRectangle(points: [SIMD3<Float>]) -> Bool {
        guard points.count == 4 else { return false }

        let edge0 = points[1] - points[0]
        let edge1 = points[2] - points[1]
        let edge2 = points[3] - points[2]
        let edge3 = points[0] - points[3]

        let edges = [edge0, edge1, edge2, edge3]
        guard edges.allSatisfy({ simd_length($0) > 0.001 }) else { return false }

        let normal = simd_cross(edge0, edge1)
        guard simd_length(normal) > 0.0001 else { return false }
        let normalizedNormal = simd_normalize(normal)

        let planarTolerance: Float = 0.01
        for point in points.dropFirst(2) {
            let distanceFromPlane = abs(simd_dot(point - points[0], normalizedNormal))
            if distanceFromPlane > planarTolerance {
                return false
            }
        }

        let rightAngleTolerance: Float = 0.25
        for index in 0..<4 {
            let first = simd_normalize(edges[index])
            let second = simd_normalize(edges[(index + 1) % 4])
            if abs(simd_dot(first, second)) > rightAngleTolerance {
                return false
            }
        }

        let parallelTolerance: Float = 0.9
        if abs(simd_dot(simd_normalize(edge0), simd_normalize(edge2))) < parallelTolerance {
            return false
        }
        if abs(simd_dot(simd_normalize(edge1), simd_normalize(edge3))) < parallelTolerance {
            return false
        }

        let oppositeLengthTolerance: Float = 0.2
        let horizontalLengthRatio = abs(simd_length(edge0) - simd_length(edge2)) / max(simd_length(edge0), simd_length(edge2))
        let verticalLengthRatio = abs(simd_length(edge1) - simd_length(edge3)) / max(simd_length(edge1), simd_length(edge3))
        guard horizontalLengthRatio < oppositeLengthTolerance,
              verticalLengthRatio < oppositeLengthTolerance else {
            return false
        }

        let projected = projected2DPoints(for: points, normal: normalizedNormal)
        return !segmentsIntersect(projected[0], projected[1], projected[2], projected[3]) &&
            !segmentsIntersect(projected[1], projected[2], projected[3], projected[0])
    }

    private func polygonNormal(points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard points.count >= 3 else { return .zero }

        var normal = SIMD3<Float>.zero
        for index in 0..<points.count {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            normal.x += (current.y - next.y) * (current.z + next.z)
            normal.y += (current.z - next.z) * (current.x + next.x)
            normal.z += (current.x - next.x) * (current.y + next.y)
        }
        return normal
    }

    private func projected2DPoints(for points: [SIMD3<Float>], normal: SIMD3<Float>) -> [SIMD2<Float>] {
        let reference = abs(normal.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let tangent = simd_normalize(simd_cross(reference, normal))
        let bitangent = simd_normalize(simd_cross(normal, tangent))
        let origin = points[0]

        return points.map { point in
            let offset = point - origin
            return SIMD2<Float>(simd_dot(offset, tangent), simd_dot(offset, bitangent))
        }
    }

    private func segmentsIntersect(_ a1: SIMD2<Float>, _ a2: SIMD2<Float>, _ b1: SIMD2<Float>, _ b2: SIMD2<Float>) -> Bool {
        func cross(_ lhs: SIMD2<Float>, _ rhs: SIMD2<Float>) -> Float {
            lhs.x * rhs.y - lhs.y * rhs.x
        }

        let r = a2 - a1
        let s = b2 - b1
        let denominator = cross(r, s)
        guard abs(denominator) > 0.0001 else { return false }

        let diff = b1 - a1
        let t = cross(diff, s) / denominator
        let u = cross(diff, r) / denominator
        return t > 0 && t < 1 && u > 0 && u < 1
    }
}
#endif
