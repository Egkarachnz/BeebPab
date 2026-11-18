import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                AppHeader()
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                HStack {
                    StepHeader(number: 1, title: "เพิ่มภาพ", symbol: "photo.stack", isComplete: !model.jobs.isEmpty)
                    if !model.jobs.isEmpty {
                        Chip(text: "\(model.jobs.count) ภาพ", color: Theme.blue)
                    }
                    Spacer()
                    if !model.jobs.isEmpty {
                        Button { model.chooseFiles() } label: {
                            Label("เพิ่มอีก", systemImage: "plus.circle.fill")
                        }
                        .disabled(model.isProcessing)
                        Button(role: .destructive) { model.clear() } label: {
                            Label("ล้าง", systemImage: "trash")
                        }
                        .disabled(model.isProcessing)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                ZStack {
                    if model.jobs.isEmpty {
                        DropZoneView(isTargeted: isDropTargeted)
                    } else {
                        ImageGridView()
                        if isDropTargeted { DropOverlay() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeOut(duration: 0.15), value: isDropTargeted)
            }
            .frame(minWidth: 500)
            .background(Color(nsColor: .windowBackgroundColor))
            .dropDestination(for: URL.self) { urls, _ in
                guard !model.isProcessing else { return false }
                model.add(urls)
                return true
            } isTargeted: { isDropTargeted = $0 }

            SidebarView()
                .frame(width: 350)
                .background(Color(nsColor: .underPageBackgroundColor).opacity(0.6))
                .overlay(alignment: .leading) { Divider() }
        }
        .frame(minWidth: 900, minHeight: 640)
    }
}

private struct AppHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("BeebPab")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.brandGradient)
                Text("ย่อภาพให้คมชัด พร้อมโพสต์ Facebook และส่ง LINE")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct DropZoneView: View {
    @Environment(AppModel.self) private var model
    var isTargeted: Bool

    private let formats: [(String, Color)] = [
        ("JPEG", .orange), ("PNG", .purple), ("HEIC", .pink), ("TIFF", .teal), ("WebP", .indigo), ("RAW", .brown),
    ]

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.brandGradient)
                    .frame(width: 96, height: 96)
                    .shadow(color: Theme.blue.opacity(0.35), radius: 14, y: 6)
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "photo.on.rectangle.angled")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .scaleEffect(isTargeted ? 1.08 : 1)

            VStack(spacing: 6) {
                Text(isTargeted ? "ปล่อยเพื่อเพิ่มภาพ" : "ลากรูปภาพหรือโฟลเดอร์มาวางที่นี่")
                    .font(.title2.weight(.semibold))
                Text("ระบบจะค้นหาภาพในโฟลเดอร์ย่อยให้อัตโนมัติ")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(formats, id: \.0) { Chip(text: $0.0, color: $0.1) }
            }

            Button { model.chooseFiles() } label: {
                Label("เลือกไฟล์หรือโฟลเดอร์…", systemImage: "folder.badge.plus")
                    .padding(.horizontal, 18)
            }
            .buttonStyle(PrimaryButtonStyle())
            .fixedSize()
            .padding(.top, 4)

            Text("หรือกด ⌘O")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Theme.blue.opacity(isTargeted ? 0.14 : 0.06), Theme.cyan.opacity(isTargeted ? 0.10 : 0.03)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isTargeted ? Theme.blue : Theme.blue.opacity(0.3),
                              style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 1.5, dash: [9, 7]))
        )
        .padding([.horizontal, .bottom], 20)
    }
}

private struct DropOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.blue.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.blue, style: StrokeStyle(lineWidth: 2.5, dash: [9, 7]))
            )
            .overlay(
                Label("ปล่อยเพื่อเพิ่มภาพ", systemImage: "plus.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.brandGradient))
            )
            .padding([.horizontal, .bottom], 12)
            .allowsHitTesting(false)
    }
}
