import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(PresetStore.self) private var presets
    @Environment(\.openSettings) private var openSettings
    @AppStorage("keepCameraInfo") private var keepCameraInfo = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        StepHeader(number: 2, title: "เลือกเป้าหมาย")
                        PlatformPicker()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        StepHeader(number: 3, title: "เลือกโฟลเดอร์บันทึก")
                        outputFolderRow
                    }
                }
                .padding(16)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if model.isProcessing {
                    ProgressView(value: Double(model.completedTasks), total: Double(max(model.totalTasks, 1))) {
                        Text("กำลังย่อภาพ \(model.completedTasks)/\(model.totalTasks)")
                            .font(.caption)
                    }
                } else if let summary = model.lastRunSummary {
                    HStack {
                        Text(summary).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("เปิดใน Finder") { model.revealOutputFolder() }
                            .controlSize(.small)
                    }
                }

                Button {
                    model.process(catalog: presets.catalog, options: ProcessOptions(keepCameraInfo: keepCameraInfo))
                } label: {
                    Text(buttonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canProcess(with: presets.catalog))

                Button {
                    openSettings()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: presets.lastError == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle")
                        Text("ข้อมูลขนาดภาพ: \(presets.catalog.updatedAt) · \(presets.origin.label)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(presets.lastError ?? "ระบบตรวจหาขนาดภาพล่าสุดของ Facebook และ LINE ให้อัตโนมัติ")
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var buttonTitle: String {
        let targets = presets.catalog.orderedKeys(in: model.selectedTargets).count
        guard !model.jobs.isEmpty, targets > 0 else { return "ย่อภาพ" }
        return targets == 1 ? "ย่อภาพ \(model.jobs.count) ภาพ" : "ย่อภาพ \(model.jobs.count) ภาพ × \(targets) แบบ"
    }

    private var outputFolderRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill").foregroundStyle(.secondary)
            if let folder = model.outputFolder {
                Text(folder.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(folder.path)
            } else {
                Text("ยังไม่ได้เลือก").foregroundStyle(.secondary)
            }
            Spacer()
            Button(model.outputFolder == nil ? "เลือก…" : "เปลี่ยน…") { model.chooseOutputFolder() }
                .disabled(model.isProcessing)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct PlatformPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(PresetStore.self) private var presets

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(presets.catalog.platforms) { platform in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(String(platform.name.prefix(1)))
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6).fill(brandColor(platform.id)))
                        Text(platform.name).font(.subheadline.weight(.semibold))
                    }

                    ForEach(platform.targets) { target in
                        let key = TargetKey(platformID: platform.id, targetID: target.id)
                        Toggle(isOn: Binding(
                            get: { model.selectedTargets.contains(key) },
                            set: { _ in model.toggle(key) }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(target.name)
                                Text(target.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .help(target.detail ?? target.summary)
                        .disabled(model.isProcessing)
                    }

                    if let note = platform.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            }
        }
    }

    private func brandColor(_ id: String) -> Color {
        switch id {
        case "facebook": return Color(red: 0.094, green: 0.467, blue: 0.949)
        case "line": return Color(red: 0.024, green: 0.780, blue: 0.333)
        default: return .accentColor
        }
    }
}
