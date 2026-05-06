#if os(iOS)
import ARKit
import RealityKit
import SwiftUI
import UIKit

struct ARMeasurementView: UIViewRepresentable {
    @ObservedObject var viewModel: MeasurementViewModel

    func makeCoordinator() -> ARMeasurementCoordinator {
        ARMeasurementCoordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        context.coordinator.attach(to: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.syncSceneContent()
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: ARMeasurementCoordinator) {
        coordinator.stop()
    }
}

@MainActor
final class ARMeasurementCoordinator: NSObject {
    let viewModel: MeasurementViewModel
    weak var arView: ARView?
    var displayLink: CADisplayLink?

    var meshEntities: [UUID: ModelEntity] = [:]
    var savedMeasurementAnchors: [UUID: AnchorEntity] = [:]

    var startAnchor: AnchorEntity?
    var endAnchor: AnchorEntity?
    var lineAnchor: AnchorEntity?

    var recentHits: [SIMD3<Float>] = []
    let maxRecentHits = 5

    var frameCounter = 0
    static var textCache: [String: MeshResource] = [:]
    var lastRenderedSignature = ""
    var snapFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    var currentSnapTarget: SIMD3<Float>?

    init(viewModel: MeasurementViewModel) {
        self.viewModel = viewModel
    }

    func attach(to arView: ARView) {
        self.arView = arView
        arView.session.delegate = self

        configureSession(for: arView)
        configureCoaching(for: arView)

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        arView.addGestureRecognizer(tapRecognizer)

        let displayLink = CADisplayLink(target: self, selector: #selector(updateLiveMeasurement))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
        snapFeedbackGenerator.prepare()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func syncSceneContent() {
        guard let arView else { return }

        updatePointAnchor(&startAnchor, point: viewModel.startPoint, in: arView)
        updatePointAnchor(&endAnchor, point: viewModel.currentTargetPoint, in: arView)
        updateLine(in: arView)
        syncSavedMeasurements(in: arView)
    }
}
#endif
