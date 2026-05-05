#if os(iOS)
import SwiftUI

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
