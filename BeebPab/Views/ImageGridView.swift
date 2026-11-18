import AppKit
import SwiftUI

struct ImageGridView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(model.jobs) { job in
                    ImageCell(job: job, canRemove: !model.isProcessing) { model.remove(job) }
                        .contextMenu {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([job.url])
                            } label: { Label("แสดงต้นฉบับใน Finder", systemImage: "folder") }
                            if !job.outputs.isEmpty {
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting(job.outputs.map(\.result.outputURL))
                                } label: { Label("แสดงไฟล์ที่ย่อแล้วใน Finder", systemImage: "checkmark.circle") }
                            }
                            Divider()
                            Button(role: .destructive) { model.remove(job) } label: {
                                Label("ลบออกจากรายการ", systemImage: "trash")
                            }
                            .disabled(model.isProcessing)
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 4)
        }
    }
}

private struct ImageCell: View {
    let job: ImageJob
    var canRemove: Bool
    var onRemove: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                if let thumb = job.thumbnail {
                    Image(decorative: thumb, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    ProgressView().controlSize(.small)
                }

                if job.status == .processing {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.35))
                    ProgressView().controlSize(.regular).tint(.white)
                }
            }
            .frame(height: 124)
            .overlay(alignment: .topTrailing) { statusBadge.padding(6) }
            .overlay(alignment: .topLeading) {
                if isHovering && canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .help("ลบออกจากรายการ")
                    .padding(6)
                }
            }

            Text(job.name)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            if let size = job.pixelSize {
                HStack(spacing: 4) {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                    Text("\(size.width)×\(size.height)")
                    if let bytes = job.fileSize { Text("· \(Theme.bytes(bytes))") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ForEach(Array(job.outputs.enumerated()), id: \.offset) { _, output in
                OutputRow(output: output, originalBytes: job.fileSize)
            }

            ForEach(job.errors, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: job.status == .idle || job.status == .waiting ? 0 : 1.5)
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: job.status)
    }

    private var borderColor: Color {
        switch job.status {
        case .done: return Theme.green.opacity(0.7)
        case .failed: return .red.opacity(0.7)
        case .processing: return Theme.blue.opacity(0.7)
        default: return .clear
        }
    }

    @ViewBuilder private var statusBadge: some View {
        switch job.status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Theme.green)
                .shadow(radius: 2)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
                .shadow(radius: 2)
        default:
            EmptyView()
        }
    }
}

private struct OutputRow: View {
    let output: ImageJob.Output
    let originalBytes: Int64?

    var body: some View {
        let r = output.result
        HStack(spacing: 5) {
            Image(systemName: r.exceedsSizeLimit ? "exclamationmark.triangle.fill" : "arrow.down.right.circle.fill")
                .foregroundStyle(r.exceedsSizeLimit ? Theme.orange : Theme.green)
            Text("\(r.pixelWidth)×\(r.pixelHeight) · \(Theme.bytes(Int64(r.byteCount)))")
                .foregroundStyle(.primary)
            Spacer(minLength: 2)
            if let original = originalBytes, original > 0, Int64(r.byteCount) < original {
                let saved = Int((1 - Double(r.byteCount) / Double(original)) * 100)
                Chip(text: "-\(saved)%", color: Theme.green)
            }
        }
        .font(.caption)
        .help(output.label + (r.quality.map { " · คุณภาพ JPEG \(Int($0 * 100))%" } ?? ""))
    }
}
