import SwiftUI

struct SplashView: View {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: 16) {
                AnivibeMark()
                    .frame(width: 140, height: 140)
                    .opacity(appeared || reduceMotion ? 1 : 0.4)
                Text("Anivibe")
                    .font(.system(.largeTitle, weight: .bold))
                    .foregroundStyle(.white)
            }
            .opacity(appeared ? 1 : 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Anivibe")
        .onAppear { withAnimation(AppMotion.panel(reduceMotion: reduceMotion)) { appeared = true } }
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
                .overlay {
                    RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
