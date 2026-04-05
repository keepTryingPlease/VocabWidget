// MilestoneViews.swift
// Two celebration styles:
//   MilestoneToastView       — small pill that slides up from the bottom
//                              and auto-dismisses after 2.5 seconds (milestones 1–25)
//   MilestoneCelebrationView — full sheet with icon, big count, and message
//                              dismissed by the user (milestones 50+)

import SwiftUI

private extension Color {
    static let appBackground = Color(red: 0.14, green: 0.14, blue: 0.15)
    static let appPrimary    = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let appSecondary  = Color(red: 0.55, green: 0.54, blue: 0.52)
    static let milestoneGold = Color(red: 0.95, green: 0.78, blue: 0.35)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Toast  (small milestones — auto-dismisses)
// ─────────────────────────────────────────────────────────────────────────────
struct MilestoneToastView: View {
    let milestone: Milestone

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: milestone.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.milestoneGold)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.title)
                    .font(.custom("PlayfairDisplay-Bold", size: 15))
                    .foregroundStyle(Color.appPrimary)
                Text(milestone.message)
                    .font(.custom("Inter_18pt-Regular", size: 13))
                    .foregroundStyle(Color.appSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(red: 0.20, green: 0.20, blue: 0.21))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Celebration sheet  (big milestones — user-dismissed)
// ─────────────────────────────────────────────────────────────────────────────
struct MilestoneCelebrationView: View {
    let milestone: Milestone
    @Environment(\.dismiss) private var dismiss

    @State private var iconScale:   CGFloat = 0.5
    @State private var iconOpacity: CGFloat = 0.0
    @State private var countScale:  CGFloat = 0.8

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── Icon ──────────────────────────────────────────────────────
            Image(systemName: milestone.icon)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.milestoneGold)
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
                .padding(.bottom, 24)

            // ── Count ─────────────────────────────────────────────────────
            Text("\(milestone.count)")
                .font(.custom("PlayfairDisplay-Bold", size: 88))
                .foregroundStyle(Color.appPrimary)
                .scaleEffect(countScale)
                .padding(.bottom, 8)

            // ── Title ─────────────────────────────────────────────────────
            Text(milestone.title)
                .font(.custom("PlayfairDisplay-Bold", size: 26))
                .foregroundStyle(Color.appPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            // ── Message ───────────────────────────────────────────────────
            Text(milestone.message)
                .font(.custom("Inter_18pt-Regular", size: 17))
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)

            Spacer()

            // ── Dismiss ───────────────────────────────────────────────────
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
            .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                iconScale   = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.1)) {
                countScale = 1.0
            }
        }
    }
}

#Preview("Toast") {
    MilestoneToastView(milestone: Milestone.all[2])
        .padding()
        .background(Color(red: 0.14, green: 0.14, blue: 0.15))
}

#Preview("Celebration") {
    MilestoneCelebrationView(milestone: Milestone.all[4])
}
