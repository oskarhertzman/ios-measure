#if os(iOS)
import ARKit
import Combine
import SwiftUI

@MainActor
final class MeasurementViewModel: ObservableObject {
    @Published private(set) var fixedPoints: [SIMD3<Float>] = []
    @Published private(set) var livePoint: SIMD3<Float>?
    @Published private(set) var savedMeasurements: [SavedMeasurement] = []
    @Published private(set) var identifiedShapeKind: IdentifiedShapeKind?
    @Published private(set) var distanceText = "--"
    @Published private(set) var instructionText = "Move the device slowly to scan surfaces, then align the reticle."
    @Published private(set) var confidenceLevel: SurfaceConfidence = .unknown
    @Published var isLidarAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    @Published var isSceneUpdatesSuspended = false
    @Published private(set) var isAwaitingAdditionalPoint = false

    var startPoint: SIMD3<Float>? {
        fixedPoints.first
    }

    var endPoint: SIMD3<Float>? {
        fixedPoints.count >= 2 ? fixedPoints.last : nil
    }

    var currentTargetPoint: SIMD3<Float>? {
        shouldShowLiveSegment ? livePoint : endPoint
    }

    var shouldShowLiveSegment: Bool {
        fixedPoints.count == 1 || isAwaitingAdditionalPoint
    }

    var hasCompletedMeasurement: Bool {
        fixedPoints.count >= 2 && !isAwaitingAdditionalPoint
    }

    var canAddAdditionalPoint: Bool {
        hasCompletedMeasurement && identifiedShapeKind == nil && livePoint != nil && confidenceLevel != .low
    }

    var canSaveMeasurement: Bool {
        hasCompletedMeasurement
    }

    var canPlacePoint: Bool {
        isLidarAvailable && livePoint != nil && confidenceLevel != .low && !hasCompletedMeasurement
    }

    var confidenceText: String {
        switch confidenceLevel {
        case .unknown: return ""
        case .low: return "Low confidence – move closer"
        case .medium: return "Medium confidence"
        case .high: return "High confidence"
        }
    }

    var confidenceColor: Color {
        switch confidenceLevel {
        case .unknown: return .gray
        case .low: return .red
        case .medium: return .yellow
        case .high: return .green
        }
    }

    @discardableResult
    func updateLivePoint(_ point: SIMD3<Float>?, confidence: SurfaceConfidence) -> Bool {
        if let point, let oldPoint = livePoint, simd_distance(point, oldPoint) < 0.001 {
            return false
        }

        guard !hasCompletedMeasurement else { return false }

        livePoint = point
        confidenceLevel = confidence

        if fixedPoints.isEmpty {
            instructionText = point == nil
                ? "Point at a surface until the reticle locks on."
                : "Tap to place the first point."
        } else if shouldShowLiveSegment {
            instructionText = point == nil
                ? "Move slowly until the next point locks."
                : "Tap to place the next point."
        } else {
            instructionText = "Measurement complete. Add a point or start a new measure."
        }

        refreshDistance()
        return true
    }

    func placeCurrentPoint() {
        guard isLidarAvailable else {
            instructionText = "LiDAR scanner required for this feature."
            return
        }

        guard let livePoint else {
            instructionText = "No surface detected at the reticle."
            return
        }

        guard confidenceLevel != .low else {
            instructionText = "Surface confidence too low. Move closer or hold steady."
            return
        }

        if fixedPoints.isEmpty {
            fixedPoints = [livePoint]
            instructionText = "First point placed. Move to the second point."
        } else {
            if let identifiedShapeKind = identifyClosedShapeIfNeeded(with: livePoint) {
                self.identifiedShapeKind = identifiedShapeKind
                isAwaitingAdditionalPoint = false
                instructionText = "\(identifiedShapeKind.title) detected. Save it to continue."
            } else {
                fixedPoints.append(livePoint)
                isAwaitingAdditionalPoint = false
                instructionText = "Measurement complete. Save it or add another point."
            }
        }

        refreshDistance()
    }

    func beginAdditionalPoint() {
        guard fixedPoints.count >= 2 else { return }
        guard identifiedShapeKind == nil else { return }
        isAwaitingAdditionalPoint = true
        instructionText = livePoint == nil
            ? "Move slowly until the next point locks."
            : "Tap to place the next point."
        refreshDistance()
    }

    func saveCurrentMeasurement(named name: String) {
        guard fixedPoints.count >= 2 else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? defaultMeasurementName : trimmedName
        savedMeasurements.append(SavedMeasurement(name: finalName, points: fixedPoints))
        resetMeasurement()
    }

    func clearSavedMeasurements() {
        savedMeasurements.removeAll()
    }

    func resetMeasurement() {
        fixedPoints = []
        livePoint = nil
        identifiedShapeKind = nil
        distanceText = "--"
        confidenceLevel = .unknown
        isAwaitingAdditionalPoint = false
        instructionText = "Move the device slowly to scan surfaces, then align the reticle."
    }

    func setAvailability(isLidarAvailable: Bool, message: String) {
        self.isLidarAvailable = isLidarAvailable
        instructionText = message
    }

    private func refreshDistance() {
        guard !fixedPoints.isEmpty else {
            distanceText = "--"
            return
        }

        if let identifiedShapeKind, fixedPoints.count >= 3 {
            let area = area(for: fixedPoints, shapeKind: identifiedShapeKind)
            distanceText = area > 0 ? Self.formatArea(area) : "--"
            return
        }

        var meters: Float = 0

        if fixedPoints.count >= 2 {
            for index in 1..<fixedPoints.count {
                meters += simd_distance(fixedPoints[index - 1], fixedPoints[index])
            }
        }

        if shouldShowLiveSegment,
           let lastPoint = fixedPoints.last,
           let livePoint {
            meters += simd_distance(lastPoint, livePoint)
        }

        distanceText = meters > 0 ? Self.formatDistance(meters) : "--"
    }

    private static func formatDistance(_ meters: Float) -> String {
        if meters >= 1 {
            return String(format: "%.2f m", meters)
        }
        return String(format: "%.1f cm", meters * 100)
    }

    var defaultMeasurementName: String {
        identifiedShapeKind?.title ?? "Measurement \(savedMeasurements.count + 1)"
    }

    private static func formatArea(_ squareMeters: Float) -> String {
        if squareMeters >= 0.1 {
            return String(format: "%.2f m²", squareMeters)
        }
        let squareCentimeters = squareMeters * 10_000
        return String(format: "%.1f cm²", squareCentimeters)
    }

    private func area(for points: [SIMD3<Float>], shapeKind: IdentifiedShapeKind) -> Float {
        switch shapeKind {
        case .triangle:
            return polygonArea(points: points)
        case .rectangle:
            return rectangleArea(points: points)
        }
    }

    private func polygonArea(points: [SIMD3<Float>]) -> Float {
        guard points.count >= 3 else { return 0 }

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

    private func identifyClosedShapeIfNeeded(with point: SIMD3<Float>) -> IdentifiedShapeKind? {
        guard let firstPoint = fixedPoints.first else { return nil }
        guard simd_distance(point, firstPoint) <= 0.001 else { return nil }

        switch fixedPoints.count {
        case 3:
            return .triangle
        case 4:
            return isValidRectangle(points: fixedPoints) ? .rectangle : nil
        default:
            return nil
        }
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
