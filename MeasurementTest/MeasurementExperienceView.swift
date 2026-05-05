#if os(iOS)
import ARKit
import Combine
import RealityKit
import SwiftUI
import UIKit

struct MeasurementExperienceView: View {
	@StateObject private var viewModel = MeasurementViewModel()
	
	var body: some View {
		ZStack {
			ARMeasurementView(viewModel: viewModel)
				.ignoresSafeArea()
			
			VStack(spacing: 0) {
				topPanel
				Spacer()
				bottomPanel
			}
			.padding(.horizontal, 20)
			.padding(.vertical, 24)
			
			reticle
		}
		.background(Color.black)
	}
	
	private var topPanel: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Measure")
				.font(.system(size: 34, weight: .bold, design: .rounded))
				.foregroundStyle(.white)
			
			Text(viewModel.instructionText)
				.font(.callout)
				.foregroundStyle(.white.opacity(0.9))
			
			HStack(alignment: .firstTextBaseline, spacing: 10) {
				Text(viewModel.distanceText)
					.font(.system(size: 30, weight: .semibold, design: .rounded))
					.monospacedDigit()
					.foregroundStyle(.white)
				
				Text(viewModel.endPoint == nil && viewModel.startPoint != nil ? "live" : "fixed")
					.font(.caption.weight(.semibold))
					.textCase(.uppercase)
					.foregroundStyle(.black)
					.padding(.horizontal, 10)
					.padding(.vertical, 5)
					.background(viewModel.endPoint == nil && viewModel.startPoint != nil ? Color.green : Color.white.opacity(0.85))
					.clipShape(Capsule())
			}
			
			if viewModel.confidenceLevel != .unknown {
				HStack(spacing: 6) {
					Circle()
						.fill(viewModel.confidenceColor)
						.frame(width: 8, height: 8)
					Text(viewModel.confidenceText)
						.font(.caption)
						.foregroundStyle(.white.opacity(0.7))
				}
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(18)
		.background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
		.overlay(alignment: .topTrailing) {
			if !viewModel.isLidarAvailable {
				Text("LiDAR required")
					.font(.caption.weight(.semibold))
					.padding(.horizontal, 10)
					.padding(.vertical, 6)
					.background(.orange, in: Capsule())
					.foregroundStyle(.black)
					.padding(16)
			}
		}
	}
	
	private var bottomPanel: some View {
		VStack(spacing: 14) {
			Text("Hold steady for best accuracy. Green reticle indicates a stable surface lock.")
				.font(.footnote)
				.multilineTextAlignment(.center)
				.foregroundStyle(.white.opacity(0.86))
			
			HStack(spacing: 12) {
				Button(action: viewModel.placeCurrentPoint) {
					Text(viewModel.startPoint == nil ? "Set Start Point" : (viewModel.endPoint == nil ? "Set End Point" : "Start New Measure"))
						.font(.headline)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 16)
				}
				.buttonStyle(.borderedProminent)
				.tint(.white)
				.foregroundStyle(.black)
				.disabled(!viewModel.canPlacePoint)
				
				Button(action: viewModel.resetMeasurement) {
					Image(systemName: "arrow.counterclockwise")
						.font(.headline)
						.frame(width: 56, height: 56)
				}
				.buttonStyle(.bordered)
				.tint(.white)
				.foregroundStyle(.white)
			}
		}
		.padding(18)
		.background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
	}
	
	private var reticle: some View {
		ZStack {
			Circle()
				.strokeBorder(.white.opacity(0.95), lineWidth: 2)
				.frame(width: 42, height: 42)
			
			Circle()
				.fill(viewModel.canPlacePoint ? Color.green : Color.red)
				.frame(width: 8, height: 8)
			
			Rectangle()
				.fill(.white.opacity(0.9))
				.frame(width: 2, height: 56)
			
			Rectangle()
				.fill(.white.opacity(0.9))
				.frame(width: 56, height: 2)
		}
		.shadow(color: .black.opacity(0.35), radius: 8)
		.allowsHitTesting(false)
	}
}

// MARK: - Confidence Level

enum SurfaceConfidence {
	case unknown, low, medium, high
}

// MARK: - View Model

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
	
	func updateLivePoint(_ point: SIMD3<Float>?, confidence: SurfaceConfidence) {
		guard endPoint == nil else { return }
		
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

// MARK: - AR View Representable

struct ARMeasurementView: UIViewRepresentable {
	@ObservedObject var viewModel: MeasurementViewModel
	
	func makeCoordinator() -> Coordinator {
		Coordinator(viewModel: viewModel)
	}
	
	func makeUIView(context: Context) -> ARView {
		let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
		context.coordinator.attach(to: arView)
		return arView
	}
	
	func updateUIView(_ uiView: ARView, context: Context) {
		context.coordinator.syncSceneContent()
	}
	
	static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
		coordinator.stop()
	}
	
	@MainActor
	final class Coordinator: NSObject, ARSessionDelegate {
		private let viewModel: MeasurementViewModel
		private weak var arView: ARView?
		private var displayLink: CADisplayLink?
		
		// Mesh tracking for collision-based raycasting
		private var meshEntities: [UUID: ModelEntity] = [:]
		
		private var startAnchor: AnchorEntity?
		private var endAnchor: AnchorEntity?
		private var lineAnchor: AnchorEntity?
		
		// Stabilization: average recent hits to reduce jitter
		private var recentHits: [SIMD3<Float>] = []
		private let maxRecentHits = 5
		
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
		}
		
		func stop() {
			displayLink?.invalidate()
			displayLink = nil
		}
		
		private func configureSession(for arView: ARView) {
			guard ARWorldTrackingConfiguration.isSupported else {
				viewModel.setAvailability(
					isLidarAvailable: false,
					message: "ARKit world tracking is unavailable on this device."
				)
				return
			}
			
			let lidarSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
			viewModel.isLidarAvailable = lidarSupported
			
			guard lidarSupported else {
				viewModel.setAvailability(
					isLidarAvailable: false,
					message: "This app requires LiDAR for precise surface measurement."
				)
				return
			}
			
			let configuration = ARWorldTrackingConfiguration()
			configuration.planeDetection = [.horizontal, .vertical]
			configuration.environmentTexturing = .automatic
			
			// Use mesh with classification for better surface understanding
			if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
				configuration.sceneReconstruction = .meshWithClassification
			} else {
				configuration.sceneReconstruction = .mesh
			}
			
			// Enable scene depth for more accurate raycasting
			if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
				configuration.frameSemantics.insert(.sceneDepth)
			}
			if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
				configuration.frameSemantics.insert(.smoothedSceneDepth)
			}
			
			arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
			
			// Enable scene understanding for mesh-based collision
			arView.environment.sceneUnderstanding.options = [.occlusion, .physics, .collision]
			arView.renderOptions.insert(.disableMotionBlur)
		}
		
		private func configureCoaching(for arView: ARView) {
			let coachingView = ARCoachingOverlayView()
			coachingView.session = arView.session
			coachingView.goal = .anyPlane
			coachingView.activatesAutomatically = true
			coachingView.translatesAutoresizingMaskIntoConstraints = false
			
			arView.addSubview(coachingView)
			NSLayoutConstraint.activate([
				coachingView.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
				coachingView.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
				coachingView.topAnchor.constraint(equalTo: arView.topAnchor),
				coachingView.bottomAnchor.constraint(equalTo: arView.bottomAnchor)
			])
		}
		
		// MARK: - ARSessionDelegate
		
		nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
			Task { @MainActor in
				for anchor in anchors {
					if let meshAnchor = anchor as? ARMeshAnchor {
						addMeshEntity(for: meshAnchor)
					}
				}
			}
		}
		
		nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
			Task { @MainActor in
				for anchor in anchors {
					if let meshAnchor = anchor as? ARMeshAnchor {
						updateMeshEntity(for: meshAnchor)
					}
				}
			}
		}
		
		nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
			Task { @MainActor in
				for anchor in anchors {
					if let meshAnchor = anchor as? ARMeshAnchor {
						removeMeshEntity(for: meshAnchor)
					}
				}
			}
		}
		
			private func addMeshEntity(for meshAnchor: ARMeshAnchor) {
				guard let arView else { return }
				
				let entity = ModelEntity()
				entity.transform = Transform(matrix: meshAnchor.transform)
				
				Task(priority: .low) { [weak self, weak entity] in
					guard let self, let entity else { return }
					guard let shape = try? await ShapeResource.generateStaticMesh(from: meshAnchor) else { return }
					
					await MainActor.run {
						guard self.meshEntities[meshAnchor.identifier] === entity else { return }
						entity.collision = CollisionComponent(shapes: [shape], isStatic: true)
						entity.physicsBody = PhysicsBodyComponent(shapes: [shape], mass: 0, mode: .static)
					}
				}
				
					meshEntities[meshAnchor.identifier] = entity
					let anchorEntity = AnchorEntity(world: meshAnchor.transform)
					anchorEntity.addChild(entity)
					arView.scene.addAnchor(anchorEntity)
			}
		
			private func updateMeshEntity(for meshAnchor: ARMeshAnchor) {
				guard let entity = meshEntities[meshAnchor.identifier] else {
					addMeshEntity(for: meshAnchor)
					return
				}
				
				entity.transform = Transform(matrix: meshAnchor.transform)
				
				Task(priority: .low) { [weak self, weak entity] in
					guard let self, let entity else { return }
					guard let shape = try? await ShapeResource.generateStaticMesh(from: meshAnchor) else { return }
					
					await MainActor.run {
						guard self.meshEntities[meshAnchor.identifier] === entity else { return }
						entity.collision = CollisionComponent(shapes: [shape], isStatic: true)
					}
				}
			}
		
		private func removeMeshEntity(for meshAnchor: ARMeshAnchor) {
			meshEntities[meshAnchor.identifier]?.removeFromParent()
			meshEntities.removeValue(forKey: meshAnchor.identifier)
		}
		
		@objc
		private func handleTap() {
			viewModel.placeCurrentPoint()
			syncSceneContent()
		}
		
		@objc
		private func updateLiveMeasurement() {
			guard let arView, viewModel.isLidarAvailable else { return }
			
			if viewModel.endPoint != nil || arView.bounds.size == .zero {
				return
			}
			
			let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
			
			// Try multiple raycast strategies for best accuracy
			var hitPoint: SIMD3<Float>?
			var confidence: SurfaceConfidence = .unknown
			
			// Strategy 1: Raycast against scene mesh (most accurate with LiDAR)
			if let result = performSceneRaycast(from: center, in: arView) {
				hitPoint = result.point
				confidence = result.confidence
			}
			// Strategy 2: Fall back to existing plane geometry
			else if let result = arView.raycast(from: center, allowing: .existingPlaneGeometry, alignment: .any).first {
				hitPoint = Self.worldPoint(from: result)
				confidence = .medium
			}
			// Strategy 3: Estimated plane as last resort
			else if let result = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first {
				hitPoint = Self.worldPoint(from: result)
				confidence = .low
			}
			
			// Stabilize the point by averaging recent hits
			if let point = hitPoint {
				let stabilizedPoint = stabilizePoint(point)
				viewModel.updateLivePoint(stabilizedPoint, confidence: confidence)
			} else {
				recentHits.removeAll()
				viewModel.updateLivePoint(nil, confidence: .unknown)
			}
			
			syncSceneContent()
		}
		
		private struct RaycastHit {
			let point: SIMD3<Float>
			let confidence: SurfaceConfidence
		}
		
		private func performSceneRaycast(from screenPoint: CGPoint, in arView: ARView) -> RaycastHit? {
			guard let ray = arView.ray(through: screenPoint) else { return nil }
			
			let origin = ray.origin
			let direction = ray.direction
			let maxDistance: Float = 5.0
			
			// Raycast against the collision geometry (scene mesh)
			let results = arView.scene.raycast(
				origin: origin,
				direction: direction,
				length: maxDistance,
				query: .nearest,
				mask: .all,
				relativeTo: nil
			)
			
			guard let hit = results.first else { return nil }
			
			// Determine confidence based on distance and hit entity type
			let distance = hit.distance
			let confidence: SurfaceConfidence
			
			if distance < 0.5 {
				confidence = .high
			} else if distance < 2.0 {
				confidence = .high
			} else if distance < 4.0 {
				confidence = .medium
			} else {
				confidence = .low
			}
			
			return RaycastHit(point: hit.position, confidence: confidence)
		}
		
		private func stabilizePoint(_ newPoint: SIMD3<Float>) -> SIMD3<Float> {
			recentHits.append(newPoint)
			
			if recentHits.count > maxRecentHits {
				recentHits.removeFirst()
			}
			
			guard recentHits.count >= 3 else {
				return newPoint
			}
			
			// Remove outliers and average
			let sorted = recentHits.sorted { simd_length($0) < simd_length($1) }
			let trimmed = Array(sorted.dropFirst().dropLast()) // Remove min and max
			
			guard !trimmed.isEmpty else { return newPoint }
			
			let sum = trimmed.reduce(SIMD3<Float>.zero, +)
			return sum / Float(trimmed.count)
		}
		
		func syncSceneContent() {
			guard let arView else { return }
			
			updatePointAnchor(&startAnchor, point: viewModel.startPoint, color: .systemGreen, in: arView)
			updatePointAnchor(&endAnchor, point: viewModel.endPoint ?? (viewModel.startPoint == nil ? nil : viewModel.livePoint), color: .systemOrange, in: arView)
			updateLine(in: arView)
		}
		
			private func updatePointAnchor(_ anchor: inout AnchorEntity?, point: SIMD3<Float>?, color: UIColor, in arView: ARView) {
				guard let point else {
					if let anchor {
						arView.scene.removeAnchor(anchor)
				}
					anchor = nil
					return
				}
				
				let anchorEntity = anchor ?? AnchorEntity(world: .zero)
				if anchorEntity.children.isEmpty {
					let ring = ModelEntity(
						mesh: .generateSphere(radius: 0.018),
						materials: [SimpleMaterial(color: .white.withAlphaComponent(0.95), roughness: 0.05, isMetallic: false)]
					)
					let core = ModelEntity(
						mesh: .generateSphere(radius: 0.010),
						materials: [Self.pointMaterial(color: color)]
					)
					anchorEntity.addChild(ring)
					anchorEntity.addChild(core)
				}
				
				let core = anchorEntity.children.compactMap { $0 as? ModelEntity }.last
				core?.model?.materials = [Self.pointMaterial(color: color)]
				anchorEntity.position = point
				
				if anchor == nil {
					arView.scene.addAnchor(anchorEntity)
					anchor = anchorEntity
			}
		}
		
		private func updateLine(in arView: ARView) {
			guard let start = viewModel.startPoint, let end = viewModel.endPoint ?? viewModel.livePoint else {
				if let lineAnchor {
					arView.scene.removeAnchor(lineAnchor)
				}
				lineAnchor = nil
				return
			}
			
			let delta = end - start
			let distance = simd_length(delta)
			
			guard distance > 0.001 else {
				if let lineAnchor {
					arView.scene.removeAnchor(lineAnchor)
				}
				lineAnchor = nil
				return
			}
			
				let midpoint = (start + end) / 2
				let direction = simd_normalize(delta)
				let isLocked = viewModel.endPoint != nil
				
				let anchorEntity = lineAnchor ?? AnchorEntity(world: .zero)
				anchorEntity.children.removeAll()
				
				if isLocked {
					let lineEntity = ModelEntity(
						mesh: .generateCylinder(height: distance, radius: 0.0035),
						materials: [Self.lineMaterial(color: .white)]
					)
					anchorEntity.addChild(lineEntity)
				} else {
					let dashLength: Float = 0.028
					let gapLength: Float = 0.016
					let lineRadius: Float = 0.0026
					let step = dashLength + gapLength
					var offset = (-distance / 2) + (dashLength / 2)
					
					while offset < (distance / 2) {
						let remaining = (distance / 2) - offset
						let segmentLength = min(dashLength, remaining * 2)
						guard segmentLength > 0.003 else { break }
						
						let dashEntity = ModelEntity(
							mesh: .generateCylinder(height: segmentLength, radius: lineRadius),
							materials: [Self.lineMaterial(color: .systemYellow)]
						)
						dashEntity.position.y = offset
						anchorEntity.addChild(dashEntity)
						offset += step
					}
				}
				
				anchorEntity.position = midpoint
				anchorEntity.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction)
				
				if lineAnchor == nil {
				arView.scene.addAnchor(anchorEntity)
				lineAnchor = anchorEntity
			}
		}
		
		private static func worldPoint(from result: ARRaycastResult) -> SIMD3<Float> {
			SIMD3<Float>(
				result.worldTransform.columns.3.x,
				result.worldTransform.columns.3.y,
				result.worldTransform.columns.3.z
			)
		}
		
		private static func pointMaterial(color: UIColor) -> SimpleMaterial {
			SimpleMaterial(color: color, roughness: 0.15, isMetallic: false)
		}
		
		private static func lineMaterial(color: UIColor) -> SimpleMaterial {
			SimpleMaterial(color: color, roughness: 0.2, isMetallic: false)
		}
	}
}

#else
import SwiftUI

struct MeasurementExperienceView: View {
	var body: some View {
		VStack(spacing: 16) {
			Image(systemName: "arkit")
				.font(.system(size: 42))
			Text("This measurement app requires iPhone or iPad with LiDAR.")
				.multilineTextAlignment(.center)
		}
		.padding(24)
	}
}
#endif
