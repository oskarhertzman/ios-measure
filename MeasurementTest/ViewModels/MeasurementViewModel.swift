#if os(iOS)
import ARKit
import Combine
import SwiftUI

@MainActor
final class MeasurementViewModel: ObservableObject {
    @Published private(set) var fixedPoints: [SIMD3<Float>] = []
    @Published private(set) var livePoint: SIMD3<Float>?
    @Published private(set) var savedMeasurements: [SavedMeasurement] = []
    @Published private(set) var distanceText = "--"
    @Published private(set) var instructionText = "Move the device slowly to scan surfaces, then align the reticle."
    @Published private(set) var confidenceLevel: SurfaceConfidence = .unknown
    @Published var isLidarAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
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
        hasCompletedMeasurement && livePoint != nil && confidenceLevel != .low
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
        if hasCompletedMeasurement {
            startNewMeasurement()
            return
        }

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
            fixedPoints.append(livePoint)
            isAwaitingAdditionalPoint = false
            instructionText = "Measurement complete. Add a point or start a new measure."
        }

        refreshDistance()
    }

    func startNewMeasurement() {
        if hasCompletedMeasurement {
            archiveCurrentMeasurement()
        }
        resetMeasurement()
    }

    func beginAdditionalPoint() {
        guard fixedPoints.count >= 2 else { return }
        isAwaitingAdditionalPoint = true
        instructionText = livePoint == nil
            ? "Move slowly until the next point locks."
            : "Tap to place the next point."
        refreshDistance()
    }

    func archiveCurrentMeasurement() {
        guard fixedPoints.count >= 2 else { return }
        savedMeasurements.append(SavedMeasurement(points: fixedPoints))
    }

    func resetMeasurement() {
        fixedPoints = []
        livePoint = nil
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
}
#endif
