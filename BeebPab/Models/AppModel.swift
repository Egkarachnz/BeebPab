import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ImageJob: Identifiable {
    struct Output: Equatable {
        var key: TargetKey
        var label: String
        var result: ProcessResult
    }

    enum Status: Equatable { case idle, waiting, processing, done, failed }

    let id = UUID()
    let url: URL
    var thumbnail: CGImage?
    var pixelSize: (width: Int, height: Int)?
    var fileSize: Int64?
    var outputs: [Output] = []
    var errors: [String] = []
    var pendingCount = 0
    var status: Status = .idle
    /// When true, the next run resizes this image again (overwriting its earlier files).
    var redoRequested = false

    init(url: URL) { self.url = url }

    var name: String { url.lastPathComponent }

    func output(for key: TargetKey) -> Output? { outputs.first { $0.key == key } }

    func loadInfo() {
        let url = self.url
        Task.detached(priority: .utility) {
            let thumb = ImageProcessor.thumbnail(for: url)
            let size = ImageProcessor.pixelSize(of: url)
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            await MainActor.run {
                self.thumbnail = thumb
                self.pixelSize = size
                self.fileSize = bytes
            }
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private static let selectionKey = "selectedTargets"

    var jobs: [ImageJob] = []
    var selectedTargets: Set<TargetKey> {
        didSet { saveSelection() }
    }
    private(set) var outputFolder: URL?
    private(set) var isProcessing = false
    private(set) var completedTasks = 0
    private(set) var totalTasks = 0
    private(set) var lastRunFolder: URL?
    private(set) var lastRunSummary: String?
    private var folderIsScoped = false

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.selectionKey),
           let saved = try? JSONDecoder().decode(Set<TargetKey>.self, from: data) {
            selectedTargets = saved
        } else {
            selectedTargets = [TargetKey(platformID: "facebook", targetID: "feed")]
        }
        if let url = FolderBookmark.restore(), url.startAccessingSecurityScopedResource() {
            outputFolder = url
            folderIsScoped = true
        }
    }

    // MARK: Inputs

    func add(_ urls: [URL]) {
        guard !isProcessing else { return }
        Task {
            let found = await Task.detached(priority: .userInitiated) { FileCollector.imageURLs(from: urls) }.value
            let existing = Set(jobs.map(\.url))
            for url in found where !existing.contains(url) {
                let job = ImageJob(url: url)
                jobs.append(job)
                job.loadInfo()
            }
        }
    }

    func remove(_ job: ImageJob) {
        guard !isProcessing else { return }
        jobs.removeAll { $0.id == job.id }
    }

    func clear() {
        guard !isProcessing else { return }
        jobs.removeAll()
        lastRunSummary = nil
    }

    func requestRedo(_ job: ImageJob) {
        guard !isProcessing else { return }
        job.redoRequested = true
        job.status = .idle
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .folder]
        panel.prompt = "เพิ่ม"
        panel.message = "เลือกรูปภาพหรือโฟลเดอร์ที่มีรูปภาพ"
        if panel.runModal() == .OK { add(panel.urls) }
    }

    // MARK: Output folder

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "เลือกโฟลเดอร์นี้"
        panel.message = "เลือกโฟลเดอร์สำหรับบันทึกภาพที่ย่อแล้ว"
        if let current = outputFolder { panel.directoryURL = current }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setOutputFolder(url)
        FolderBookmark.save(url)
    }

    func setOutputFolder(_ url: URL) {
        if folderIsScoped { outputFolder?.stopAccessingSecurityScopedResource() }
        folderIsScoped = false
        outputFolder = url
    }

    // MARK: Pending work

    func toggle(_ key: TargetKey) {
        if selectedTargets.contains(key) { selectedTargets.remove(key) } else { selectedTargets.insert(key) }
    }

    /// An output counts as done only if its file still exists in the current output folder.
    static func isDone(_ output: ImageJob.Output, in folder: URL) -> Bool {
        let path = output.result.outputURL.standardizedFileURL.path
        let base = folder.standardizedFileURL.path
        return path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
            && FileManager.default.fileExists(atPath: path)
    }

    /// Selected targets this image still needs (all of them if a redo was requested).
    func pendingKeys(for job: ImageJob, catalog: PresetCatalog) -> [TargetKey] {
        let keys = catalog.orderedKeys(in: selectedTargets)
        guard let folder = outputFolder, !job.redoRequested else { return keys }
        return keys.filter { key in
            guard let output = job.output(for: key) else { return true }
            return !Self.isDone(output, in: folder)
        }
    }

    func pendingImageCount(with catalog: PresetCatalog) -> Int {
        jobs.filter { !pendingKeys(for: $0, catalog: catalog).isEmpty }.count
    }

    var allImagesDone: Bool { !jobs.isEmpty && jobs.allSatisfy { $0.status == .done } }

    func canProcess(with catalog: PresetCatalog) -> Bool {
        !isProcessing && outputFolder != nil && !catalog.orderedKeys(in: selectedTargets).isEmpty
            && pendingImageCount(with: catalog) > 0
    }

    // MARK: Processing

    func process(catalog: PresetCatalog, options: ProcessOptions) {
        guard canProcess(with: catalog), let folder = outputFolder else { return }
        // Subfolders depend on the whole selection, so file locations stay stable between runs.
        let useSubfolders = catalog.orderedKeys(in: selectedTargets).count > 1

        struct WorkItem: Sendable {
            var jobIndex: Int
            var key: TargetKey
            var label: String
            var input: URL
            var target: OutputTarget
            var output: URL
        }

        var reserved = Set<URL>()
        // Files from earlier runs that we'll overwrite count as taken by their own job only.
        for job in jobs { for output in job.outputs { reserved.insert(output.result.outputURL) } }

        var work: [WorkItem] = []
        var setupErrors = 0
        for (index, job) in jobs.enumerated() {
            let keys = pendingKeys(for: job, catalog: catalog)
            guard !keys.isEmpty else { continue }
            job.errors = []
            job.pendingCount = 0
            job.redoRequested = false
            for key in keys {
                guard let (platform, target) = catalog.resolve(key) else { continue }
                do {
                    let out: URL
                    if let previous = job.output(for: key),
                       previous.result.outputURL.deletingLastPathComponent().standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path) {
                        out = previous.result.outputURL   // re-run: overwrite the same file, no "(2)" copy
                    } else {
                        out = try OutputWriter.outputURL(for: job.url, platform: platform, target: target,
                                                         in: folder, useSubfolder: useSubfolders, reserved: &reserved)
                    }
                    work.append(WorkItem(jobIndex: index, key: key, label: "\(platform.name) · \(target.name)",
                                         input: job.url, target: target, output: out))
                    job.pendingCount += 1
                } catch {
                    job.errors.append(error.localizedDescription)
                    setupErrors += 1
                }
            }
            job.status = job.pendingCount > 0 ? .waiting : .failed
        }

        let jobsSnapshot = jobs
        isProcessing = true
        completedTasks = 0
        totalTasks = work.count
        lastRunSummary = nil

        Task {
            let started = Date()
            var failures = setupErrors
            var saved = 0
            var oversize = 0
            await withTaskGroup(of: (WorkItem, Result<ProcessResult, Error>).self) { group in
                var queue = work.makeIterator()
                let limit = max(2, ProcessInfo.processInfo.activeProcessorCount)

                func enqueueNext() -> Int? {
                    guard let item = queue.next() else { return nil }
                    group.addTask {
                        let result = Result { try ImageProcessor.process(inputURL: item.input, target: item.target,
                                                                         outputURL: item.output, options: options) }
                        return (item, result)
                    }
                    return item.jobIndex
                }

                for _ in 0..<limit {
                    if let index = enqueueNext() { jobsSnapshot[index].status = .processing }
                }
                for await (item, result) in group {
                    let job = jobsSnapshot[item.jobIndex]
                    switch result {
                    case .success(let r):
                        job.outputs.removeAll { $0.key == item.key }
                        job.outputs.append(.init(key: item.key, label: item.label, result: r))
                        saved += 1
                        if r.exceedsSizeLimit { oversize += 1 }
                    case .failure(let error):
                        job.errors.append("\(item.label): \(error.localizedDescription)")
                        failures += 1
                    }
                    job.pendingCount -= 1
                    if job.pendingCount == 0 { job.status = job.errors.isEmpty ? .done : .failed }
                    completedTasks += 1
                    if let index = enqueueNext() { jobsSnapshot[index].status = .processing }
                }
            }

            let seconds = Date().timeIntervalSince(started)
            var summary = "บันทึก \(saved) ไฟล์ ใน \(String(format: "%.1f", seconds)) วินาที"
            if failures > 0 { summary += " · ผิดพลาด \(failures)" }
            if oversize > 0 { summary += " · \(oversize) ไฟล์ยังใหญ่กว่าเกณฑ์" }
            lastRunSummary = summary
            lastRunFolder = folder
            isProcessing = false
        }
    }

    func revealOutputFolder() {
        guard let folder = lastRunFolder ?? outputFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private func saveSelection() {
        if let data = try? JSONEncoder().encode(selectedTargets) {
            UserDefaults.standard.set(data, forKey: Self.selectionKey)
        }
    }
}
