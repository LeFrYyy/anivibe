import SwiftUI

struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: 16) {
                AnivibeMark()
                    .frame(width: 88, height: 88)
                    .scaleEffect(appeared ? 1 : 0.92)
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

/// Векторный знак Anivibe (повторяет иконку приложения): буква «A» и треугольник «play».
struct AnivibeMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: s * 0.18, y: s * 0.86))
                    p.addLine(to: CGPoint(x: s * 0.5, y: s * 0.12))
                    p.addLine(to: CGPoint(x: s * 0.82, y: s * 0.86))
                }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: s * 0.13, lineCap: .round, lineJoin: .round))
                Path { p in
                    p.move(to: CGPoint(x: s * 0.43, y: s * 0.52))
                    p.addLine(to: CGPoint(x: s * 0.43, y: s * 0.74))
                    p.addLine(to: CGPoint(x: s * 0.62, y: s * 0.63))
                    p.closeSubpath()
                }
                .fill(Theme.secondaryAccent)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
