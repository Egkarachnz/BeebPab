import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(PresetStore.self) private var presets
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                StepHeader(number: 1, title: "เพิ่มภาพ", trailing: model.jobs.isEmpty ? nil : "\(model.jobs.count) ภาพ")
                    .padding([.horizontal, .top], 16)
                    .padding(.bottom, 8)
                Group {
                    if model.jobs.isEmpty {
                        DropZoneView(isTargeted: isDropTargeted)
                    } else {
                        ImageGridView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 480)
            .dropDestination(for: URL.self) { urls, _ in
                guard !model.isProcessing else { return false }
                model.add(urls)
                return true
            } isTargeted: { isDropTargeted = $0 }

            Divider()

            SidebarView()
                .frame(width: 340)
        }
        .frame(minWidth: 880, minHeight: 580)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.chooseFiles()
                } label: {
                    Label("เพิ่มภาพ", systemImage: "plus")
                }
                .help("เพิ่มรูปภาพหรือโฟลเดอร์")
                .disabled(model.isProcessing)

                Button {
                    model.clear()
                } label: {
                    Label("ล้างรายการ", systemImage: "trash")
                }
                .help("ล้างรายการภาพ")
                .disabled(model.jobs.isEmpty || model.isProcessing)
            }
        }
    }
}

struct StepHeader: View {
    var number: Int
    var title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(title).font(.headline)
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct DropZoneView: View {
    @Environment(AppModel.self) private var model
    var isTargeted: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text("ลากรูปภาพหรือโฟลเดอร์มาวางที่นี่")
                .font(.title3.weight(.medium))
            Text("รองรับ JPEG, PNG, HEIC, TIFF, WebP และไฟล์ RAW")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("เลือกไฟล์หรือโฟลเดอร์…") { model.chooseFiles() }
                .controlSize(.large)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .background(RoundedRectangle(cornerRadius: 14)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear))
        )
        .padding(16)
    }
}
