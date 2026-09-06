import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .clipShape(.rect(cornerRadius: 36))
                    .shadow(color: .cyan.opacity(0.35), radius: 24)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Treadmill Remote")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("FitShow / Egofit controller")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Treadmill Remote, FitShow and Egofit controller")
    }
}

