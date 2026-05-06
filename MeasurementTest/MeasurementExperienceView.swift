#if os(iOS)
import SwiftUI
import UIKit

struct MeasurementExperienceView: View {
    @StateObject private var viewModel = MeasurementViewModel()
    @State private var isSavedMeasurementsPresented = false
    @State private var isSavePromptPresented = false
    @State private var pendingMeasurementName = ""
    @State private var impactGenerator = UIImpactFeedbackGenerator(style: .light)

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

			VStack {
				HStack {
					Spacer()
					menuButton
				}
				Spacer()
			}
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color.black)
        .sheet(isPresented: $isSavedMeasurementsPresented) {
            SavedMeasurementsSheet(
                measurements: viewModel.savedMeasurements,
                onDeleteMeasurement: viewModel.deleteSavedMeasurement,
                onClearAll: viewModel.clearSavedMeasurements
            )
        }
        .sheet(isPresented: $isSavePromptPresented) {
            SaveMeasurementSheet(
                name: $pendingMeasurementName,
                onCancel: { isSavePromptPresented = false },
                onSave: {
                    viewModel.saveCurrentMeasurement(named: pendingMeasurementName)
                    isSavePromptPresented = false
                }
            )
        }
        .onAppear {
            impactGenerator.prepare()
        }
        .onChange(of: isSavedMeasurementsPresented) { _, _ in
            updateSceneSuspensionState()
        }
        .onChange(of: isSavePromptPresented) { _, _ in
            updateSceneSuspensionState()
        }
    }

    private var menuButton: some View {
        Button {
            isSavedMeasurementsPresented = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(.black.opacity(0), in: Circle())
        }
        .foregroundStyle(.white)
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

                Text(viewModel.shouldShowLiveSegment && viewModel.startPoint != nil ? "live" : "fixed")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(viewModel.shouldShowLiveSegment && viewModel.startPoint != nil ? Color.green : Color.white.opacity(0.85))
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

            if let identifiedShapeKind = viewModel.identifiedShapeKind {
                Text(identifiedShapeKind.title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.9), in: Capsule())
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
                if !viewModel.hasCompletedMeasurement {
                    Button(action: handlePrimaryAction) {
                        Text(viewModel.fixedPoints.isEmpty ? "Set Start Point" : "Set Point")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .disabled(!viewModel.canPlacePoint)
                }

                if viewModel.hasCompletedMeasurement {
                    Button(action: handleSaveMeasurement) {
                        Text("Save")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .disabled(!viewModel.canSaveMeasurement)

                    Button(action: handleAddPoint) {
                        Text("Add Point")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .foregroundStyle(.white)
                    .disabled(!viewModel.canAddAdditionalPoint)
                }

                Button(action: handleUndoLastPoint) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .foregroundStyle(.white)
                .disabled(!viewModel.canUndoLastPoint)
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

    private func handlePrimaryAction() {
        playLightHaptic()
        viewModel.placeCurrentPoint()
    }

    private func handleSaveMeasurement() {
        playLightHaptic()
        pendingMeasurementName = viewModel.defaultMeasurementName
        isSavePromptPresented = true
    }

    private func handleAddPoint() {
        playLightHaptic()
        viewModel.beginAdditionalPoint()
    }

    private func handleUndoLastPoint() {
        playLightHaptic()
        viewModel.undoLastPoint()
    }

    private func playLightHaptic() {
        impactGenerator.impactOccurred()
        impactGenerator.prepare()
    }

    private func updateSceneSuspensionState() {
        viewModel.isSceneUpdatesSuspended = isSavedMeasurementsPresented || isSavePromptPresented
    }
}

private struct SavedMeasurementsSheet: View {
    let measurements: [SavedMeasurement]
    let onDeleteMeasurement: (UUID) -> Void
    let onClearAll: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if measurements.isEmpty {
                    ContentUnavailableView(
                        "No Saved Measurements",
                        systemImage: "ruler",
                        description: Text("Save a measurement to see it here.")
                    )
                } else {
                    List(measurements) { measurement in
                        Group {
                            if measurement.identifiedShapeKind == .rectangle {
                                RectangleMeasurementCard(
                                    measurement: measurement,
                                    onDelete: { onDeleteMeasurement(measurement.id) }
                                )
                            } else {
                                HStack(alignment: .center, spacing: 12) {
                                    Image(systemName: "ruler")
                                        .font(.headline)
                                        .foregroundStyle(.black.opacity(0.8))
                                        .frame(width: 28, height: 28)
                                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(measurement.name)
                                            .font(.headline)
                                        Text(measurement.lengthText)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Button(role: .destructive) {
                                        onDeleteMeasurement(measurement.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.red)
                                            .frame(width: 30, height: 30)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .listRowBackground(Color.white)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                }
            }
            .background(Color.white)
            .navigationTitle("Saved Measurements")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !measurements.isEmpty {
                        Button("Clear All", role: .destructive, action: onClearAll)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .background(Color.white)
    }
}

private struct RectangleMeasurementCard: View {
    let measurement: SavedMeasurement
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(measurement.name)
                    .font(.headline)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 16) {
                RectangleDiagram()
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 18) {
                        metricBlock(title: "Length", value: measurement.formattedLength(measurement.rectangleHeightMeters ?? 0))
                        metricBlock(title: "Width", value: measurement.formattedLength(measurement.rectangleWidthMeters ?? 0))
                    }
                    HStack(alignment: .top, spacing: 18) {
                        metricBlock(title: "Area", value: measurement.formattedArea(measurement.areaSquareMeters))
                        metricBlock(title: "Diagonal", value: measurement.formattedLength(measurement.rectangleDiagonalMeters ?? 0))
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func metricBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RectangleDiagram: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black.opacity(0.14), lineWidth: 1)
                .frame(width: 96, height: 96)

            Path { path in
                path.move(to: CGPoint(x: 18, y: 18))
                path.addLine(to: CGPoint(x: 78, y: 18))
                path.addLine(to: CGPoint(x: 78, y: 78))
                path.addLine(to: CGPoint(x: 18, y: 78))
                path.closeSubpath()
                path.move(to: CGPoint(x: 48, y: 18))
                path.addLine(to: CGPoint(x: 48, y: 78))
                path.move(to: CGPoint(x: 18, y: 48))
                path.addLine(to: CGPoint(x: 78, y: 48))
            }
            .stroke(.black.opacity(0.65), lineWidth: 1.5)

            ForEach(Array([
                CGPoint(x: 18, y: 18),
                CGPoint(x: 78, y: 18),
                CGPoint(x: 78, y: 78),
                CGPoint(x: 18, y: 78)
            ].enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(.black.opacity(0.78))
                    .frame(width: 6, height: 6)
                    .position(point)
            }
        }
        .frame(width: 96, height: 96)
    }
}

private struct SaveMeasurementSheet: View {
    @Binding var name: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Enter a name for this measurement.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Measurement name", text: $name)
                    .textFieldStyle(.roundedBorder)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
            .navigationTitle("Save Measurement")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: onSave)
                }
            }
        }
        .presentationDetents([.fraction(0.28)])
        .presentationDragIndicator(.visible)
        .background(Color.white)
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
