import SwiftUI

enum GrabbTheme {
    static let base = Color(red: 0.03, green: 0.03, blue: 0.05)
    static let indigo = Color(red: 0.17, green: 0.13, blue: 0.48)
    static let indigoDeep = Color(red: 0.10, green: 0.08, blue: 0.30)
    static let pill = Color.white.opacity(0.12)
}

extension View {
    /// Liquid Glass with strong transparency and a specular highlight.
    /// macOS 26 or later uses the clear glass style. Earlier versions use a thin material.
    @ViewBuilder
    func glassPill<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(macOS 26.0, *) {
            let base: Glass = tint.map { Glass.clear.tint($0.opacity(0.55)) } ?? Glass.clear
            self
                .glassEffect(interactive ? base.interactive() : base, in: shape)
                .overlay { GlassShine(shape: shape) }
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .background(shape.fill(tint?.opacity(0.35) ?? Color.white.opacity(0.06)))
                .overlay { GlassShine(shape: shape) }
        }
    }
}

/// Light that falls on the top edge of a glass control: a soft gradient inside and a bright rim.
private struct GlassShine<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.34), .white.opacity(0.06), .clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.7)
                    )
                )
                .blendMode(.plusLighter)
            shape
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.9), location: 0),
                            .init(color: .white.opacity(0.08), location: 0.35),
                            .init(color: .white.opacity(0.0), location: 0.6),
                            .init(color: .white.opacity(0.45), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

/// One segmented switch for Downloads and History. It sits in the blue bar, under the URL row.
/// Equal segment widths, noun labels, one glass track with a sliding thumb (HIG: segmented controls).
private struct SectionSwitch: View {
    @Environment(LibraryModel.self) private var model
    @Namespace private var thumbSpace

    private let segmentWidth: CGFloat = 120
    private let height: CGFloat = 32

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let selected = model.selectedTab == tab
                Button {
                    withAnimation(.snappy(duration: 0.22)) { model.selectedTab = tab }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(selected ? 1 : 0.65))
                        .frame(width: segmentWidth, height: height - 6)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(.white.opacity(0.24))
                                    .overlay { Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1) }
                                    .matchedGeometryEffect(id: "thumb", in: thumbSpace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .glassPill(Capsule(), interactive: false)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Section")
    }
}

/// Barra de topo arredondada: gradiente índigo até o preto, nome do app em branco e controles em pílulas.
struct HeaderBarView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    private var canClear: Bool {
        model.jobs.contains { $0.status.isFinished }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Grabb")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                if model.activeCount > 0 {
                    Text(model.activeCount == 1 ? "1 active" : "\(model.activeCount) active")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 34, height: 34)
                        .glassPill(Circle())
                        .foregroundStyle(.white)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Preferences: choose the browser, destination folder, and more.")
                .accessibilityLabel("Preferences")

                Button {
                    model.clearFinished()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 34, height: 34)
                        .glassPill(Circle(), interactive: canClear)
                        .foregroundStyle(.white.opacity(canClear ? 1 : 0.35))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canClear)
                .help("Remove finished, canceled, and failed items from the list.")
                .accessibilityLabel("Clear Finished")
            }
            .padding(.leading, 68)
            .frame(height: 32)

            ComposerView()

            SectionSwitch()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 28, bottomTrailingRadius: 28, topTrailingRadius: 0, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: GrabbTheme.indigo, location: 0),
                            .init(color: GrabbTheme.indigoDeep, location: 0.5),
                            .init(color: Color.black, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 28, bottomTrailingRadius: 28, topTrailingRadius: 0, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

#Preview {
    let settings = AppSettings()
    HeaderBarView()
        .environment(settings)
        .environment(LibraryModel(settings: settings))
        .padding(8)
        .frame(width: 760, height: 200)
        .background(GrabbTheme.base)
}
