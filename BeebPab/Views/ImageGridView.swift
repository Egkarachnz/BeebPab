import AppKit
import SwiftUI

struct ImageGridView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.jobs) { job in
                    ImageCell(job: job)
                        .contextMenu {
                            Button("แสดงต้นฉบับใน Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([job.url])
                            }
                            if !job.outputs.isEmpty {
                                Button("แสดงไฟล์ที่ย่อแล้วใน Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting(job.outputs.map(\.result.outputURL))
                                }
                            }
                            Divider()
                            Button("ลบออกจากรายการ", role: .destructive) { model.remove(job) }
                                .disabled(model.isProcessing)
                        }
                }
            }
            .padding(16)
        }
    }
}

private struct ImageCell: View {
    let job: ImageJob

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12))
                if let thumb = job.thumbnail {
                    Image(decorative: thumb, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(4)
                } else {
                    ProgressView().controlSize(.small)
                }
                statusBadge
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
            }
            .frame(height: 120)

            Text(job.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)

            if let size = job.pixelSize {
                Text("\(size.width)×\(size.height)" + (job.fileSize.map { " · " + bytes($0) } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(job.outputs.enumerated()), id: \.offset) { _, output in
                let r = output.result
                Label {
                    Text("\(r.pixelWidth)×\(r.pixelHeight) · \(bytes(Int64(r.byteCount)))")
                } icon: {
                    Image(systemName: r.exceedsSizeLimit ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(r.exceedsSizeLimit ? .orange : .green)
                }
                .font(.caption)
                .help(output.label + (r.quality.map { " · คุณภาพ JPEG \(Int($0 * 100))%" } ?? ""))
            }

            ForEach(job.errors, id: \.self) { message in
                Label(message, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder private var statusBadge: some View {
        switch job.status {
        case .processing:
            ProgressView().controlSize(.small)
                .padding(4)
                .background(.regularMaterial, in: Circle())
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.white, .green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.white, .red)
        case .idle, .waiting:
            EmptyView()
        }
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
