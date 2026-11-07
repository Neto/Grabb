import SwiftUI

/// One action in the right column of a card.
struct CardAction {
    let title: String
    var destructive = false
    let run: () -> Void
}

/// A long card for one request. The content sits on the left. The actions sit on the right,
/// one per cell, and thin lines divide the cells.
struct RequestCard<Content: View>: View {
    let actions: [CardAction]
    @ViewBuilder let content: Content

    private let radius: CGFloat = 16
    private var line: Color { .white.opacity(0.14) }

    var body: some View {
        HStack(spacing: 0) {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !actions.isEmpty {
                Rectangle().fill(line).frame(width: 1)

                VStack(spacing: 0) {
                    ForEach(actions.indices, id: \.self) { index in
                        if index > 0 {
                            Rectangle().fill(line).frame(height: 1)
                        }
                        Button(action: actions[index].run) {
                            Text(actions[index].title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(actions[index].destructive ? Color(red: 1, green: 0.45, blue: 0.45) : Color.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(CardActionStyle())
                        .frame(minHeight: 34)
                    }
                }
                .frame(width: 124)
            }
        }
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.white.opacity(0.055)))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.32), .white.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

private struct CardActionStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : (hovering ? 0.08 : 0)))
            .onHover { hovering = $0 }
    }
}
