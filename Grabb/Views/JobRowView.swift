import SwiftUI

struct JobRowView: View {
    @Environment(LibraryModel.self) private var model
    let job: DownloadJob

    var body: some View {
        RequestCard(actions: cardActions) {
          HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(job.title)
                        .font(.headline)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Label(job.platform.title, systemImage: job.platform.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }

                metadataLine

                statusBlock
            }
          }
        }
        .contextMenu { menuItems }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var thumbnail: some View {
        Group {
            if let url = job.info?.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        placeholder
                            .overlay { ProgressView().controlSize(.small) }
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
                Image(systemName: job.platform.systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private var metadataLine: some View {
        HStack(spacing: 8) {
            if let uploader = job.info?.uploader, !uploader.isEmpty {
                Text(uploader)
                    .lineLimit(1)
            }
            if let duration = job.info?.durationLabel {
                Text(duration)
                    .monospacedDigit()
            }
            Text(job.quality.title)
            if let output = job.outputURL {
                Text(output.lastPathComponent)
                    .lineLimit(1)
                    .help(output.path)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var statusBlock: some View {
        switch job.status {
        case .fetchingInfo:
            ProgressView(job.statusDetail ?? "Fetching info…")
                .controlSize(.small)
        case .downloading(let fraction, let speed, let eta):
            VStack(alignment: .leading, spacing: 4) {
                if let fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
                HStack {
                    if let fraction {
                        Text("Download: \(fraction.formatted(.percent.precision(.fractionLength(0))))")
                    } else {
                        Text("Download…")
                    }
                    if let speed { Text(speed) }
                    if let eta { Text("\(eta) left") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        case .processing(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                if let fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
                Text(fraction.map { "Converting: \($0.formatted(.percent.precision(.fractionLength(0))))" } ?? "Converting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .completed:
            Label("Finished", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        case .cancelled:
            Label("Canceled", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private var cardActions: [CardAction] {
        if job.status.isActive {
            return [CardAction(title: "Cancel") { model.cancel(job.id) }]
        }
        if case .completed = job.status {
            return [
                CardAction(title: "Show") { model.reveal(job.id) },
                CardAction(title: "Open") { model.open(job.id) },
            ]
        }
        return [
            CardAction(title: "Try Again") { model.retry(job.id) },
            CardAction(title: "Remove", destructive: true) { model.remove(job.id) },
        ]
    }

    @ViewBuilder
    private var menuItems: some View {
        if case .completed = job.status {
            Button("Show in Finder", systemImage: "folder") { model.reveal(job.id) }
            Button("Open", systemImage: "play.circle") { model.open(job.id) }
        }
        if job.status.isActive {
            Button("Cancel") { model.cancel(job.id) }
        } else {
            Button("Try Again", systemImage: "arrow.clockwise") { model.retry(job.id) }
        }
        Button("Copy URL", systemImage: "doc.on.clipboard") { model.copyURL(job.id) }
        Divider()
        Button("Remove from List", role: .destructive) { model.remove(job.id) }
    }

    private var accessibilitySummary: String {
        var parts = [job.platform.title, job.title]
        switch job.status {
        case .fetchingInfo: parts.append("fetching info")
        case .downloading(let fraction, _, _):
            if let fraction {
                parts.append("downloading \(Int(fraction * 100)) percent")
            } else {
                parts.append("downloading")
            }
        case .processing(let fraction):
            if let fraction {
                parts.append("converting \(Int(fraction * 100)) percent")
            } else {
                parts.append("converting")
            }
        case .completed: parts.append("finished")
        case .failed(let message): parts.append("failed: \(message)")
        case .cancelled: parts.append("canceled")
        }
        return parts.joined(separator: ", ")
    }
}
