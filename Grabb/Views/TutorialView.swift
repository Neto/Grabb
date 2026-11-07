import SwiftUI

// MARK: - Frame tracking

/// Collects the frames of the mock controls so the animated cursor can move to the real positions.
private struct TutorialFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func tutorialAnchor(_ id: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TutorialFrames.self,
                    value: [id: proxy.frame(in: .named("mock"))]
                )
            }
        )
    }
}

// MARK: - Tutorial

/// Animated first-run tutorial. A mock window shows a cursor that clicks the real controls
/// and shows an example for each step.
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var frames: [String: CGRect] = [:]

    @State private var cursor = CGPoint(x: 340, y: 300)
    @State private var cursorVisible = false
    @State private var pressing = false
    @State private var target = ""

    @State private var url = ""
    @State private var quality = "Best quality"
    @State private var menuOpen = false
    @State private var menuLow = false
    @State private var progress: Double?
    @State private var phase = "Download"
    @State private var finished = false
    @State private var historyTab = false
    @State private var settingsOpen = false

    private let exampleURL = "https://www.youtube.com/watch?v=example"

    private let steps: [(title: String, text: String)] = [
        ("Paste a link",
         "Click Paste, or type a link in the field. Grabb works with YouTube, Instagram, TikTok, and Vimeo."),
        ("Choose the quality",
         "Pick a resolution. Choose Audio only to save an MP3. The options depend on the video."),
        ("Upscale low resolution videos",
         "For a low resolution video, the Quality menu adds an Upscale section. Choose Upscale to 1080p for a bigger picture. Grabb uses Apple ML on macOS 26 and later."),
        ("Click Download",
         "Grabb downloads the video and converts it for QuickTime. The progress shows in the list."),
        ("Find it again in History",
         "Grabb saves each finished download in History. Click Download Again to repeat it."),
        ("Set your preferences",
         "Open Preferences to choose the destination folder and a browser for sign in. Some videos and Stories need browser cookies."),
        ("You are ready",
         "Paste a link and click Download. To see this tutorial again, choose Help > Show Tutorial."),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Grabb")
                .font(.title2.bold())

            VStack(spacing: 6) {
                Text("Step \(step + 1) of \(steps.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(steps[step].title)
                    .font(.title3.weight(.semibold))
                Text(steps[step].text)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560, minHeight: 44, alignment: .top)
            }

            stage

            HStack {
                HStack(spacing: 6) {
                    ForEach(steps.indices, id: \.self) { index in
                        Circle()
                            .fill(index == step ? Color.white : Color.white.opacity(0.25))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(TutorialSecondaryButton())
                }
                if step == steps.count - 1 {
                    Button("Start Using Grabb") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(TutorialPrimaryButton())
                } else {
                    Button("Next") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(TutorialPrimaryButton())
                }
            }
        }
        .padding(24)
        .frame(width: 780)
        .background {
            LinearGradient(
                stops: [
                    .init(color: GrabbTheme.indigo, location: 0),
                    .init(color: GrabbTheme.indigoDeep, location: 0.35),
                    .init(color: Color(red: 0.03, green: 0.03, blue: 0.06), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .preferredColorScheme(.dark)
        .task(id: step) {
            try? await run(step)
        }
    }

    // MARK: Stage (light grey surround and logo)

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: 0.90), Color(white: 0.80)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            VStack(spacing: 0) {
                mock
                    .padding(.top, 18)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 376)
    }

    // MARK: Mock window

    private var mock: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                mockHeader
                mockContent
                Spacer(minLength: 0)
            }
            LogoMark(size: 16)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            if menuOpen { qualityMenu }
            if settingsOpen { settingsCard }
            if cursorVisible { cursorView }
        }
        .frame(width: 680, height: 340)
        .coordinateSpace(name: "mock")
        .background(GrabbTheme.base)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.28), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        .onPreferenceChange(TutorialFrames.self) { frames = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animated example of the Grabb window")
    }

    private func scale(_ id: String) -> CGFloat {
        pressing && target == id ? 0.92 : 1
    }

    private var mockHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(.white.opacity(0.4)).frame(width: 10, height: 10)
                }
                Text("Grabb")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.leading, 14)
                    .padding(.top, 8)
                Spacer()
                Image(systemName: "gearshape")
                    .frame(width: 28, height: 28)
                    .mockGlass(Circle())
                    .scaleEffect(scale("gear"))
                    .tutorialAnchor("gear")
            }

            HStack(spacing: 8) {
                Label("Paste", systemImage: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .mockGlass(Capsule())
                    .scaleEffect(scale("paste"))
                    .tutorialAnchor("paste")

                HStack {
                    Text(url.isEmpty ? "Paste a video URL" : url)
                        .lineLimit(1)
                        .foregroundStyle(url.isEmpty ? Color.white.opacity(0.45) : Color.white)
                    Spacer(minLength: 0)
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .mockGlass(Capsule())
                .tutorialAnchor("field")

                HStack(spacing: 5) {
                    Text(url.isEmpty ? "Quality" : quality)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.callout)
                .foregroundStyle(url.isEmpty ? Color.white.opacity(0.4) : Color.white)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .mockGlass(Capsule())
                .scaleEffect(scale("quality"))
                .tutorialAnchor("quality")

                Label("Download", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(url.isEmpty ? Color.white.opacity(0.4) : Color.white)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .mockGlass(Capsule(), tint: url.isEmpty ? nil : GrabbTheme.indigo)
                    .scaleEffect(scale("download"))
                    .tutorialAnchor("download")
            }

            HStack(spacing: 0) {
                switchSegment("Downloads", selected: !historyTab)
                switchSegment("History", selected: historyTab)
                    .scaleEffect(scale("tabHistory"))
                    .tutorialAnchor("tabHistory")
            }
            .padding(2)
            .mockGlass(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: [GrabbTheme.indigo, GrabbTheme.indigoDeep, .black],
                    startPoint: .top,
                    endPoint: .bottom
                ))
        )
    }

    @ViewBuilder
    private var mockContent: some View {
        if historyTab {
            mockRow(
                subtitle: "YouTube · 1080p · 1 download",
                trailing: AnyView(
                    Text("Download Again")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(GrabbTheme.indigo))
                        .scaleEffect(scale("redownload"))
                        .tutorialAnchor("redownload")
                )
            )
        } else if let progress {
            mockRow(
                subtitle: finished ? "Finished" : "\(phase): \(Int(progress * 100))%",
                trailing: AnyView(
                    Group {
                        if finished {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            ProgressView(value: progress).frame(width: 140)
                        }
                    }
                )
            )
        } else {
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 30))
                Text("No downloads yet")
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        }
    }

    private func switchSegment(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(selected ? 1 : 0.65))
            .frame(width: 100, height: 22)
            .background {
                if selected {
                    Capsule()
                        .fill(.white.opacity(0.24))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                }
            }
    }

    private func mockRow(subtitle: String, trailing: AnyView) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.1)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Example video").font(.callout.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            trailing
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var qualityMenu: some View {
        let available = menuLow
            ? ["Best quality", "360p", "240p", "Audio only (MP3)"]
            : ["Best quality", "1080p", "720p", "Audio only (MP3)"]
        let upscale = ["Upscale to 720p", "Upscale to 1080p"]
        let origin = frames["quality"].map { CGPoint(x: $0.minX, y: $0.maxY + 4) } ?? CGPoint(x: 430, y: 90)
        return VStack(alignment: .leading, spacing: 0) {
            menuHeader("Available")
            ForEach(available, id: \.self) { option in
                menuRow(option, anchor: !menuLow && option == "1080p" ? "opt1080" : nil)
            }
            if menuLow {
                Divider().padding(.vertical, 3)
                menuHeader("Upscale (Apple ML)")
                ForEach(upscale, id: \.self) { option in
                    menuRow(option, anchor: option == "Upscale to 1080p" ? "optUp1080" : nil)
                }
            }
        }
        .frame(width: 190)
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15)))
        .shadow(radius: 8)
        .offset(x: origin.x, y: origin.y)
    }

    private func menuHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 10)
            .frame(height: 20, alignment: .leading)
    }

    @ViewBuilder
    private func menuRow(_ option: String, anchor: String?) -> some View {
        let row = HStack {
            Text(option)
            Spacer(minLength: 10)
            if option == quality { Image(systemName: "checkmark") }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(anchor != nil && target == anchor ? Color.accentColor.opacity(0.5) : .clear)
        if let anchor {
            row.tutorialAnchor(anchor)
        } else {
            row
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preferences").font(.callout.weight(.semibold))
            settingsLine("Destination folder", "Downloads")
            settingsLine("Cookies for videos", "Automatic")
            settingsLine("Cookies for Instagram Stories", "Brave")
            settingsLine("When finished", "Show in Finder")
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.15)))
        .shadow(radius: 8)
        .offset(x: 340, y: 46)
    }

    private func settingsLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.white.opacity(0.65))
        }
        .font(.caption)
    }

    private var cursorView: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.7), lineWidth: 2)
                .frame(width: 30, height: 30)
                .scaleEffect(pressing ? 1 : 0.3)
                .opacity(pressing ? 1 : 0)
            Image(systemName: "cursorarrow")
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 2)
                .offset(x: 8, y: 10)
        }
        .position(cursor)
        .allowsHitTesting(false)
    }

    // MARK: Script

    private func pause(_ milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }

    private func move(to id: String, dx: CGFloat = 0, dy: CGFloat = 0) async throws {
        target = id
        if let frame = frames[id] {
            withAnimation(.easeInOut(duration: 0.8)) {
                cursor = CGPoint(x: frame.midX + dx, y: frame.midY + dy)
            }
        }
        try await pause(900)
    }

    private func click() async throws {
        withAnimation(.easeIn(duration: 0.1)) { pressing = true }
        try await pause(160)
        withAnimation(.easeOut(duration: 0.25)) { pressing = false }
        try await pause(300)
    }

    private func typeURL() async throws {
        url = ""
        for character in exampleURL {
            url.append(character)
            try await pause(28)
        }
    }

    private func setBaseline(
        url: String = "",
        quality: String = "Best quality",
        job: Bool = false,
        history: Bool = false,
        settings: Bool = false,
        menu: Bool = false,
        low: Bool = false
    ) {
        menuLow = low
        self.url = url
        self.quality = quality
        progress = job ? 1 : nil
        finished = job
        phase = "Download"
        historyTab = history
        settingsOpen = settings
        menuOpen = menu
        pressing = false
        target = ""
    }

    private func advance() {
        if step < steps.count - 1 { step += 1 }
    }

    private func run(_ current: Int) async throws {
        try await pause(250)
        switch current {
        case 0:
            setBaseline()
            cursor = CGPoint(x: 340, y: 300)
            withAnimation { cursorVisible = true }
            try await pause(500)
            try await move(to: "paste")
            try await click()
            try await typeURL()
            try await pause(1400)
            advance()

        case 1:
            setBaseline(url: exampleURL)
            cursorVisible = true
            try await move(to: "quality")
            try await click()
            withAnimation(.easeOut(duration: 0.15)) { menuOpen = true }
            try await pause(500)
            try await move(to: "opt1080")
            try await click()
            quality = "1080p"
            withAnimation { menuOpen = false }
            try await pause(1300)
            advance()

        case 2:
            setBaseline(url: exampleURL, low: true)
            cursorVisible = true
            try await move(to: "quality")
            try await click()
            withAnimation(.easeOut(duration: 0.15)) { menuOpen = true }
            try await pause(900)
            try await move(to: "optUp1080")
            try await click()
            quality = "Upscale to 1080p"
            withAnimation { menuOpen = false }
            try await pause(1500)
            advance()

        case 3:
            setBaseline(url: exampleURL, quality: "1080p")
            cursorVisible = true
            try await move(to: "download")
            try await click()
            url = ""
            progress = 0
            phase = "Download"
            for index in 1...40 {
                withAnimation(.linear(duration: 0.06)) { progress = Double(index) / 40 }
                try await pause(55)
            }
            phase = "Converting"
            progress = 0
            for index in 1...15 {
                withAnimation(.linear(duration: 0.06)) { progress = Double(index) / 15 }
                try await pause(50)
            }
            finished = true
            try await pause(1500)
            advance()

        case 4:
            setBaseline(job: true)
            cursorVisible = true
            try await move(to: "tabHistory")
            try await click()
            withAnimation { historyTab = true }
            try await pause(600)
            try await move(to: "redownload")
            try await click()
            try await pause(1200)
            advance()

        case 5:
            setBaseline()
            cursorVisible = true
            try await move(to: "gear")
            try await click()
            withAnimation(.easeOut(duration: 0.2)) { settingsOpen = true }
            try await pause(3200)
            advance()

        default:
            setBaseline()
            withAnimation { cursorVisible = false }
        }
    }
}

/// Mock of the clear glass look used by the real controls.
private extension View {
    func mockGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil) -> some View {
        self
            .background(shape.fill(tint?.opacity(0.4) ?? Color.white.opacity(0.07)))
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.65)
                    )
                )
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.8), location: 0),
                            .init(color: .white.opacity(0.06), location: 0.4),
                            .init(color: .white.opacity(0.35), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
    }
}

#Preview {
    TutorialView()
}


/// Main action of the tutorial: indigo glass capsule with a bright rim.
private struct TutorialPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 36)
            .background(Capsule().fill(GrabbTheme.indigo.opacity(0.85)))
            .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 1))
            .shadow(color: GrabbTheme.indigo.opacity(0.6), radius: 10, y: 2)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

private struct TutorialSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 36)
            .background(Capsule().fill(.white.opacity(0.1)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}
