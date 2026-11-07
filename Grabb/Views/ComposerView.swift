import SwiftUI

struct ComposerView: View {
    @Environment(LibraryModel.self) private var model
    @FocusState private var urlFocused: Bool

    private let pillHeight: CGFloat = 36

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    model.pasteFromClipboard()
                    urlFocused = true
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: pillHeight)
                        .glassPill(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Paste a URL from the clipboard.")

                TextField(
                    "",
                    text: $model.draftURL,
                    prompt: Text("Paste a video URL").foregroundStyle(.white.opacity(0.45))
                )
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: pillHeight)
                .glassPill(Capsule(), interactive: false)
                .focused($urlFocused)
                .accessibilityLabel("Video URL")

                Menu {
                    Picker("Quality", selection: $model.quality) {
                        Section("Available") {
                            ForEach(model.availableQualities) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        if !model.availableUpscales.isEmpty {
                            Section("Upscale (\(upscaleMethodLabel))") {
                                ForEach(model.availableUpscales) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 6) {
                        Text(qualityLabel)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(qualityMenuDisabled ? Color.white.opacity(0.4) : Color.white)
                    .padding(.horizontal, 14)
                    .frame(height: pillHeight)
                    .glassPill(Capsule(), interactive: !qualityMenuDisabled)
                    .contentShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .disabled(qualityMenuDisabled)
                .fixedSize()
                .accessibilityLabel("Quality")
                .help("Quality of the downloaded file.")

                Button(action: submit) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .frame(height: pillHeight)
                        .foregroundStyle(model.canSubmit ? Color.white : Color.white.opacity(0.4))
                        .glassPill(Capsule(), tint: model.canSubmit ? GrabbTheme.indigo : nil, interactive: model.canSubmit)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!model.canSubmit)
                .keyboardShortcut(.defaultAction)
                .help("Fetch the video and start the download.")
            }

        }
        .onAppear {
            urlFocused = true
        }
    }

    private var upscaleMethodLabel: String {
        Upscaler.method(forShortSide: model.probedMaxHeight ?? 0).label
    }

    private var qualityMenuDisabled: Bool {
        model.availableQualities.isEmpty || model.isImageOnly
    }

    private var qualityLabel: String {
        if model.isProbingQuality { return "Fetching…" }
        if model.isImageOnly { return model.imageCount > 1 ? "\(model.imageCount) images" : "Image" }
        if model.availableQualities.isEmpty { return "Quality" }
        return model.quality.title
    }

    private func submit() {
        model.enqueueDraft()
    }
}
