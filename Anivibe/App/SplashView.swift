import SwiftUI

struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: 16) {
                AnivibeMark()
                    .frame(width: 140, height: 140)
                    .scaleEffect(appeared ? 1 : 0.85)
                Text("Anivibe")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            }
            .opacity(appeared ? 1 : 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Anivibe")
        .onAppear { withAnimation(.easeOut(duration: 0.4)) { appeared = true } }
    }
}

/// Логотип Anivibe — та же картинка, что и иконка приложения.
struct AnivibeMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: s, height: s)
                .clipShape(RoundedRectangle(cornerRadius: s * 0.225, style: .continuous))
                .shadow(color: Color(red: 0.3, green: 0.55, blue: 1).opacity(0.35), radius: s * 0.15)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
