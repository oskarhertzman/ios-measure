#if os(iOS)
import ARKit
import Combine
import SwiftUI

@MainActor
final class MeasurementViewModel: ObservableObject {
    @Published private(set) var startPoint: SIMD3<Float>?
    @Published private(set) var endPoint: SIMD3<Float>?
    @Published private(set) var livePoint: SIMD3<Float>?
    @Published private(set) var distanceText = "--"
    @Published private(set) var instructionText = "Move the device slowly to scan surfaces, then align the reticle."
    @Published private(set) var confidenceLevel: SurfaceConfidence = .unknown
    @Published var isLidarAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)

    var canPlacePoint: Bool {
        isLidarAvailable && livePoint != nil && confidenceLevel != .low
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

        guard endPoint == nil else { return false }

        livePoint = point
        confidenceLevel = confidence

        if startPoint == nil {
            instructionText = point == nil
                ? "Point at a surface until the reticle locks on."
                : "Tap to place the first point."
        } else {
            instructionText = point == nil
                ? "Move slowly until the second point locks."
                : "Tap to place the second point."
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

        if endPoint != nil {
            resetMeasurement()
        }

        if startPoint == nil {
            startPoint = livePoint
            instructionText = "First point placed. Move to the second point."
        } else {
            endPoint = livePoint
            instructionText = "Measurement complete. Tap reset to start over."
        }

        refreshDistance()
    }

    func resetMeasurement() {
        startPoint = nil
        endPoint = nil
        livePoint = nil
        distanceText = "--"
        confidenceLevel = .unknown
        instructionText = "Move the device slowly to scan surfaces, then align the reticle."
    }

    func setAvailability(isLidarAvailable: Bool, message: String) {
        self.isLidarAvailable = isLidarAvailable
        instructionText = message
    }

    private func refreshDistance() {
        guard let startPoint else {
            distanceText = "--"
            return
        }

        guard let targetPoint = endPoint ?? livePoint else {
            distanceText = "--"
            return
        }

        let delta = targetPoint - startPoint
        let meters = simd_length(delta)
        distanceText = Self.formatDistance(meters)
    }

    private static func formatDistance(_ meters: Float) -> String {
        if meters >= 1 {
            return String(format: "%.2f m", meters)
        }
        return String(format: "%.1f cm", meters * 100)
    }
}
#endif
