import SwiftUI
import BECore

/// BE's design language: Apple-native and minimal. System fonts (SF Pro,
/// rounded for numbers), SF Symbols, grouped backgrounds, continuous corners,
/// one accent colour per health area, and full Dynamic Type and Dark Mode support.
enum Theme {
    static let cardRadius: CGFloat = 22
    static let cardPadding: CGFloat = 14
    static let gridSpacing: CGFloat = 12

    static func tint(for metric: MetricKind) -> Color {
        switch metric {
        case .steps, .activeEnergy, .exerciseMinutes, .standHours, .vo2Max: .green
        case .restingHeartRate, .heartRate, .hrv: .pink
        case .oxygenSaturation, .respiratoryRate, .wristTemperature: .teal
        case .sleepHours: .indigo
        case .bodyMass, .bodyFat: .purple
        case .dietaryEnergy, .protein, .carbohydrates, .fat: .orange
        case .water: .cyan
        }
    }

    static func color(for tone: CoachNote.Tone) -> Color {
        switch tone {
        case .positive: .green
        case .neutral: .secondary
        case .attention: .orange
        }
    }

    static let move = Color(red: 0.98, green: 0.07, blue: 0.31)
    static let exercise = Color(red: 0.65, green: 1.0, blue: 0.0)
    static let stand = Color(red: 0.0, green: 0.93, blue: 0.95)
}

extension View {
    /// The look of every Home widget: like an iOS Home Screen widget.
    func widgetCard() -> some View {
        padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

extension Font {
    /// Big numbers: SF Pro Rounded, tabular digits.
    static func metric(_ style: Font.TextStyle = .title) -> Font {
        .system(style, design: .rounded).weight(.semibold).monospacedDigit()
    }
}

/// Concentric activity rings, drawn from HealthKit's ring data.
struct RingsView: View {
    var move: Double
    var exercise: Double
    var stand: Double
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            ring(move, Theme.move, inset: 0)
            ring(exercise, Theme.exercise, inset: lineWidth + 2)
            ring(stand, Theme.stand, inset: (lineWidth + 2) * 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Move \(Int(move * 100))%, exercise \(Int(exercise * 100))%, stand \(Int(stand * 100))%")
    }

    private func ring(_ fraction: Double, _ color: Color, inset: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset + lineWidth / 2)
        .animation(.spring(duration: 0.8), value: fraction)
    }
}

/// Thin capsule progress bar.
struct ProgressBar: View {
    var value: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.18))
                Capsule().fill(tint).frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 6)
        .animation(.spring(duration: 0.6), value: value)
    }
}
