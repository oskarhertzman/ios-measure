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
			updateBillboards()
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
				if let anchor { arView.scene.removeAnchor(anchor) }
				anchor = nil
				return
			}
			
			let anchorEntity = anchor ?? AnchorEntity(world: .zero)
			
			if anchorEntity.children.isEmpty {
				// SIZING: 3.5mm (Only ~1.3mm larger than the line dots for a sleek look)
				anchorEntity.addChild(Self.makeDotEntity(radius: 0.0035))
			}
			
			anchorEntity.position = point
			
			if anchor == nil {
				arView.scene.addAnchor(anchorEntity)
				anchor = anchorEntity
			}
		}
		
		
		private func updateLine(in arView: ARView) {
			guard let start = viewModel.startPoint, let end = viewModel.endPoint ?? viewModel.livePoint else {
				lineAnchor?.removeFromParent()
				lineAnchor = nil
				return
			}
			
			let delta = end - start
			let distance = simd_length(delta)
			
			// Safety check for very small distances
			guard distance > 0.002 else { return }
			
			let direction = simd_normalize(delta)
			
			let anchorEntity = lineAnchor ?? AnchorEntity(world: .zero)
			anchorEntity.children.removeAll()
			
			if viewModel.endPoint == nil {
				// --- DASHED LIVE LINE (While measuring) ---
				let dotSpacing: Float = 0.010 // 1cm spacing
				let dotCount = Int(distance / dotSpacing)
				
				for i in 0...dotCount {
					let offset = Float(i) * dotSpacing
					let position = start + (direction * offset)
					
					// Use the small 2D-style circle dot
					let dot = Self.makeDotEntity(radius: 0.0022)
					dot.position = position
					anchorEntity.addChild(dot)
				}
			} else {
				// --- SOLID FINALIZED LINE WITH RULER TICKS (After setting) ---
				
				// 1. The Solid Main Line
				let lineMesh = MeshResource.generateCylinder(height: distance, radius: 0.0008)
				let lineModel = ModelEntity(mesh: lineMesh, materials: [UnlitMaterial(color: .white)])
				lineModel.position = start + (delta / 2)
				lineModel.look(at: end, from: lineModel.position, relativeTo: nil)
				lineModel.orientation *= simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
				anchorEntity.addChild(lineModel)
				
				// 2. The Hierarchical Ruler Logic
				let cmSpacing: Float = 0.01 // 1cm
				let totalCm = Int(distance / cmSpacing)
				
				for i in 1...totalCm {
					let offset = Float(i) * cmSpacing
					let position = start + (direction * offset)
					
					var tickHeight: Float = 0.005 // Default 1cm (Shortest)
					
					if i % 10 == 0 {
						tickHeight = 0.014 // 10cm (Longest)
						let label = Self.makeTextEntity("\(i)")
						label.position = position
						anchorEntity.addChild(label)
					} else if i % 5 == 0 {
						tickHeight = 0.009 // 5cm (Medium)
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
		
		private static func worldPoint(from result: ARRaycastResult) -> SIMD3<Float> {
			SIMD3<Float>(
				result.worldTransform.columns.3.x,
				result.worldTransform.columns.3.y,
				result.worldTransform.columns.3.z
			)
		}
		
		private static func pointMaterial(color: UIColor) -> UnlitMaterial {
			UnlitMaterial(color: color)
		}
		
		private static func makeDotEntity(radius: Float) -> Entity {
			// 1. Create a cylinder with tiny height. It's effectively a 2D disc.
			// Increased sides (default is 64) for a perfectly smooth circle.
			let mesh = MeshResource.generateCylinder(height: 0.00001, radius: radius)
			let material = UnlitMaterial(color: .white)
			let model = ModelEntity(mesh: mesh, materials: [material])
			
			// 2. RealityKit cylinders have their circular face on the Y-axis.
			// The look(at:) logic points the Z-axis at the camera.
			// We rotate the model 90 degrees so the circular face points forward.
			model.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
			
			// 3. Wrap it in a container for the Billboard logic
			let container = Entity()
			container.addChild(model)
			container.components.set(BillboardComponent())
			
			return container
		}
		
		private func updateBillboards() {
			guard let arView = arView,
					let frame = arView.session.currentFrame else { return }
			
			// Get the camera's position from the current AR frame transform
			let cameraTransform = frame.camera.transform
			let cameraPosition = SIMD3<Float>(cameraTransform.columns.3.x,
											  cameraTransform.columns.3.y,
											  cameraTransform.columns.3.z)
			
			let query = EntityQuery(where: .has(BillboardComponent.self))
			arView.scene.performQuery(query).forEach { entity in
				// Always face the camera position
				entity.look(at: cameraPosition,
							from: entity.position(relativeTo: nil),
							relativeTo: nil)
			}
		}
		
		private static func makeTickEntity(height: Float) -> Entity {
			let width: Float = 0.0012 // Consistent thickness
			let mesh = MeshResource.generatePlane(width: width, depth: height)
			let material = UnlitMaterial(color: .white.withAlphaComponent(0.9))
			let model = ModelEntity(mesh: mesh, materials: [material])
			
			// 1. Rotate to face the camera (Billboard setup)
			model.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
			
			// 2. OFFSET: Move the tick down so the top edge touches the line
			// Since the plane is centered, moving it down by height/2 makes the top stay at 0
			model.position.y = -(height / 2)
			
			let container = Entity()
			container.addChild(model)
			container.components.set(BillboardComponent())
			
			return container
		}
		
		private static func makeTextEntity(_ text: String) -> Entity {
			// Small, bold font to match the system look
			let font = UIFont.systemFont(ofSize: 0.008, weight: .bold)
			let mesh = MeshResource.generateText(text, extrusionDepth: 0.0001, font: font)
			let material = UnlitMaterial(color: .white.withAlphaComponent(0.8))
			let model = ModelEntity(mesh: mesh, materials: [material])
			
			// Center the text horizontally
			let bounds = model.visualBounds(relativeTo: nil)
			let width = bounds.max.x - bounds.min.x
			model.position.x = -(width / 2)
			
			// Position it below the longest tick (approx 1.8cm down)
			model.position.y = -0.018
			
			let container = Entity()
			container.addChild(model)
			container.components.set(BillboardComponent())
			return container
		}
	}
}

// MARK: - Billboard Logic

struct BillboardComponent: Component {}



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
