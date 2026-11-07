import SwiftUI

struct RootView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            VStack(spacing: 0) {
                HeaderBarView()
                    .padding(.bottom, 4)

                if let banner = model.banner {
                    bannerBar(banner)
                }

                engineBar

                switch model.selectedTab {
                case .downloads:
                    if model.jobs.isEmpty {
                        EmptyQueueView()
                    } else {
                        ScrollViewReader { proxy in
                            List {
                                ForEach(model.jobs) { job in
                                    JobRowView(job: job)
                                        .id(job.id)
                                        .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                }
                            }
                            .listStyle(.inset)
                            .scrollContentBackground(.hidden)
                            .alternatingRowBackgrounds(.disabled)
                            .onChange(of: model.jobs.first?.id) { _, newID in
                                guard let newID else { return }
                                withAnimation {
                                    proxy.scrollTo(newID, anchor: .top)
                                }
                            }
                        }
                    }
                case .history:
                    HistoryView()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()
                    LogoMark(size: 20)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea(.container, edges: .top)
            .navigationTitle("Grabb")
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .onDrop(of: [.url, .plainText], isTargeted: nil, perform: handleDrop)
            .sheet(isPresented: $model.showTutorial, onDismiss: { model.markTutorialSeen() }) {
                TutorialView()
            }
            .onAppear { model.quality = settings.defaultQuality }
            .frame(minWidth: 640, minHeight: 460)
            .containerBackground(for: .window) { GrabbTheme.base }
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var engineBar: some View {
        switch model.engineStatus {
        case .missing(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.yellow.opacity(0.12))
        case .ready, .unknown:
            EmptyView()
        }
    }

    private func bannerBar(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
            Spacer()
            Button("OK") { model.banner = nil }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var found = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
                    Task { @MainActor in
                        model.enqueue(url: url.absoluteString)
                    }
                }
                found = true
            } else if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                    guard let string = string as? String else { return }
                    Task { @MainActor in
                        model.enqueue(url: string)
                    }
                }
                found = true
            }
        }
        return found
    }
}

struct EmptyQueueView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("No downloads yet", systemImage: "arrow.down.circle")
        } actions: {
            Button("Show Tutorial") { model.showTutorial = true }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    let settings = AppSettings()
    RootView()
        .environment(settings)
        .environment(LibraryModel(settings: settings))
        .frame(width: 760, height: 560)
}
