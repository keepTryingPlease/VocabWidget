// MilestoneViews.swift
// Full-screen celebration sheet shown for every mastery milestone.
// Fireworks burst across the screen on appear.

import SwiftUI

private extension Color {
    static let appBackground = Color(red: 0.14, green: 0.14, blue: 0.15)
    static let appPrimary    = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let appSecondary  = Color(red: 0.55, green: 0.54, blue: 0.52)
    static let milestoneGold = Color(red: 0.95, green: 0.78, blue: 0.35)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Celebration sheet
// ─────────────────────────────────────────────────────────────────────────────
struct MilestoneCelebrationView: View {
    let milestone: Milestone
    @Environment(\.dismiss) private var dismiss

    @State private var iconScale:   CGFloat = 0.4
    @State private var iconOpacity: CGFloat = 0.0
    @State private var countScale:  CGFloat = 0.7
    @State private var textOpacity: CGFloat = 0.0

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            // ── Fireworks layer (behind content, non-interactive) ─────────
            FireworksView()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // ── Content ───────────────────────────────────────────────────
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: milestone.icon)
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(Color.milestoneGold)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
                    .padding(.bottom, 20)

                Text("\(milestone.count)")
                    .font(.custom("PlayfairDisplay-Bold", size: 96))
                    .foregroundStyle(Color.appPrimary)
                    .scaleEffect(countScale)
                    .padding(.bottom, 4)

                Text(milestone.title)
                    .font(.custom("PlayfairDisplay-Bold", size: 26))
                    .foregroundStyle(Color.appPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)
                    .opacity(textOpacity)

                Text(milestone.message)
                    .font(.custom("Inter_18pt-Regular", size: 17))
                    .foregroundStyle(Color.appSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                    .opacity(textOpacity)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Keep going  →")
                        .font(.custom("Inter_18pt-Regular", size: 17))
                        .foregroundStyle(Color.appBackground)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 16)
                        .background(Color.appPrimary)
                        .clipShape(Capsule())
                }
                .opacity(textOpacity)
                .padding(.bottom, 56)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                iconScale   = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65).delay(0.12)) {
                countScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.25)) {
                textOpacity = 1.0
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Fireworks
// ─────────────────────────────────────────────────────────────────────────────

private struct ParticleData: Identifiable {
    let id    = UUID()
    let origin: CGPoint
    let angle:  Double
    let distance: CGFloat
    let color:  Color
    let size:   CGFloat
    let delay:  Double
}

private struct BurstData: Identifiable {
    let id        = UUID()
    let particles: [ParticleData]
}

struct FireworksView: View {

    @State private var bursts: [BurstData] = []

    private let palette: [Color] = [
        Color(red: 0.95, green: 0.78, blue: 0.35), // gold
        Color(red: 0.98, green: 0.55, blue: 0.25), // orange
        Color(red: 0.40, green: 0.88, blue: 0.55), // green
        Color(red: 0.45, green: 0.68, blue: 0.98), // blue
        Color(red: 0.88, green: 0.48, blue: 0.98), // purple
        Color(red: 0.98, green: 0.48, blue: 0.72), // pink
        .white,
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(bursts) { burst in
                    ForEach(burst.particles) { p in
                        FireworkParticleView(particle: p)
                    }
                }
            }
            .onAppear {
                let size = geo.size
                for wave in 0..<5 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(wave) * 0.42) {
                        bursts.append(makeBurst(in: size))
                    }
                }
            }
        }
    }

    private func makeBurst(in size: CGSize) -> BurstData {
        let origin = CGPoint(
            x: CGFloat.random(in: size.width  * 0.15 ... size.width  * 0.85),
            y: CGFloat.random(in: size.height * 0.10 ... size.height * 0.55)
        )
        let count = Int.random(in: 18...26)
        let particles = (0..<count).map { i -> ParticleData in
            let base  = Double(i) / Double(count) * .pi * 2
            let jitter = Double.random(in: -0.25...0.25)
            return ParticleData(
                origin:   origin,
                angle:    base + jitter,
                distance: CGFloat.random(in: 55...140),
                color:    palette.randomElement()!,
                size:     CGFloat.random(in: 4...9),
                delay:    Double.random(in: 0...0.08)
            )
        }
        return BurstData(particles: particles)
    }
}

private struct FireworkParticleView: View {
    let particle: ParticleData
    @State private var fired = false

    private var targetX: CGFloat { particle.origin.x + cos(particle.angle) * particle.distance }
    private var targetY: CGFloat { particle.origin.y + sin(particle.angle) * particle.distance + 28 }

    var body: some View {
        Circle()
            .fill(particle.color)
            .frame(width: particle.size, height: particle.size)
            .position(fired ? CGPoint(x: targetX, y: targetY) : particle.origin)
            .opacity(fired ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.1).delay(particle.delay)) {
                    fired = true
                }
            }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Milestone progress sheet
// ─────────────────────────────────────────────────────────────────────────────
struct MilestoneProgressView: View {

    @ObservedObject var milestoneManager: MilestoneManager
    @ObservedObject var library:          UserLibrary
    @Environment(\.dismiss) private var dismiss

    private var achieved: Int { milestoneManager.shownCounts.count }
    private let total = Milestone.all.count

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ────────────────────────────────────────────────
                HStack(alignment: .firstTextBaseline) {
                    Text("Achievements")
                        .font(.custom("PlayfairDisplay-Bold", size: 22))
                        .foregroundStyle(Color.appPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Color.appSecondary.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 20)

                // ── Progress summary ──────────────────────────────────────
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(achieved)")
                        .font(.custom("PlayfairDisplay-Bold", size: 56))
                        .foregroundStyle(Color.milestoneGold)
                    Text("/ \(total)")
                        .font(.custom("Inter_18pt-Regular", size: 22))
                        .foregroundStyle(Color.appSecondary)
                        .padding(.bottom, 8)
                }

                Text(library.masteredIDs.isEmpty
                     ? "Start mastering words to unlock achievements"
                     : "\(library.masteredIDs.count) word\(library.masteredIDs.count == 1 ? "" : "s") mastered")
                    .font(.custom("Inter_18pt-Regular", size: 14))
                    .foregroundStyle(Color.appSecondary)
                    .padding(.bottom, 20)

                // ── Progress bar ──────────────────────────────────────────
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.appPrimary.opacity(0.07))
                        Capsule()
                            .fill(Color.milestoneGold)
                            .frame(width: total > 0
                                   ? geo.size.width * CGFloat(achieved) / CGFloat(total)
                                   : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: achieved)
                    }
                    .frame(height: 5)
                }
                .frame(height: 5)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                Divider().overlay(Color.appSecondary.opacity(0.18))

                // ── Milestone list ────────────────────────────────────────
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Milestone.all) { milestone in
                            milestoneRow(milestone)
                            if milestone.id != Milestone.all.last?.id {
                                Divider()
                                    .overlay(Color.appSecondary.opacity(0.1))
                                    .padding(.leading, 72)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func milestoneRow(_ milestone: Milestone) -> some View {
        let done = milestoneManager.shownCounts.contains(milestone.count)

        HStack(spacing: 16) {
            // Icon badge
            ZStack {
                Circle()
                    .fill(done
                          ? Color.milestoneGold.opacity(0.14)
                          : Color.appPrimary.opacity(0.05))
                    .frame(width: 44, height: 44)
                Image(systemName: milestone.icon)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(done ? Color.milestoneGold : Color.appSecondary.opacity(0.5))
            }

            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(milestone.title)
                    .font(.custom("Inter_18pt-Regular", size: 15))
                    .foregroundStyle(done ? Color.appPrimary : Color.appSecondary)
                Text("\(milestone.count) words")
                    .font(.custom("Inter_18pt-Regular", size: 12))
                    .foregroundStyle(Color.appSecondary.opacity(0.55))
            }

            Spacer()

            // Status indicator
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(red: 0.35, green: 0.85, blue: 0.55))
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appSecondary.opacity(0.3))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .opacity(done ? 1.0 : 0.55)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────────────────────────────────────────
#Preview {
    MilestoneCelebrationView(milestone: Milestone.all[4])
}
