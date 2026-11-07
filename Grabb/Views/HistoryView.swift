import SwiftUI

struct HistoryView: View {
    @Environment(LibraryModel.self) private var model
    @State private var search = ""
    @State private var confirmClear = false

    private var filtered: [HistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.history }
        return model.history.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.sourceURL.localizedCaseInsensitiveContains(query)
                || ($0.uploader?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        if model.history.isEmpty {
            ContentUnavailableView {
                Label("No history yet", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Links that you download appear here.\nYou can download the same link again.")
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField("Search history", text: $search)
                        .textFieldStyle(.roundedBorder)
                    Text(model.history.count == 1 ? "1 link" : "\(model.history.count) links")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Clear History", role: .destructive) {
                        confirmClear = true
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                List {
                    ForEach(filtered) { entry in
                        HistoryRowView(entry: entry)
                            .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .alternatingRowBackgrounds(.disabled)
                .overlay {
                    if filtered.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .confirmationDialog(
                "Delete all history?",
                isPresented: $confirmClear,
                titleVisibility: .visible
            ) {
                Button("Delete History", role: .destructive) {
                    model.clearHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Downloaded files are not deleted.")
            }
        }
    }
}

struct HistoryRowView: View {
    @Environment(LibraryModel.self) private var model
    let entry: HistoryEntry

    var body: some View {
        RequestCard(actions: cardActions) {
          HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.title)
                        .font(.headline)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Label(entry.platform.title, systemImage: entry.platform.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let uploader = entry.uploader, !uploader.isEmpty {
                        Text(uploader).lineLimit(1)
                    }
                    Text(entry.quality.title)
                    Text(entry.lastDownloadedAt.formatted(date: .abbreviated, time: .shortened))
                    if entry.downloadCount > 1 {
                        Text("\(entry.downloadCount) downloads")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(entry.sourceURL)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
          }
        }
        .contextMenu {
            Button("Download Again", systemImage: "arrow.down.circle") { model.redownload(entry.id) }
            if entry.fileExists {
                Button("Show in Finder", systemImage: "folder") { model.revealHistory(entry.id) }
            }
            Button("Copy URL", systemImage: "doc.on.clipboard") { model.copyHistoryURL(entry.id) }
            Divider()
            Button("Remove from History", role: .destructive) { model.removeHistory(entry.id) }
        }
    }

    private var cardActions: [CardAction] {
        var items = [CardAction(title: "Download Again") { model.redownload(entry.id) }]
        if entry.fileExists {
            items.append(CardAction(title: "Show") { model.revealHistory(entry.id) })
        }
        items.append(CardAction(title: "Remove", destructive: true) { model.removeHistory(entry.id) })
        return items
    }

    private var thumbnail: some View {
        Group {
            if let url = entry.thumbnailURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 120, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: entry.platform.systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }
}
