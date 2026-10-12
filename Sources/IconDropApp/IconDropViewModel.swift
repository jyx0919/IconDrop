import AppKit
import IconDropCore
import SwiftUI

struct QueuedIconAssignment: Identifiable {
    let id = UUID()
    let imageURL: URL
    var folderURLs: [URL]
    var preview: NSImage
    let removeBackground: Bool
}

@MainActor
final class IconDropViewModel: ObservableObject {
    @Published private(set) var imageURL: URL?
    @Published private(set) var folderURLs: [URL] = []
    @Published private(set) var imagePreview: NSImage?
    @Published private(set) var queue: [QueuedIconAssignment] = []
    @Published private(set) var feedback: String?
    @Published private(set) var feedbackIsError = false
    @Published private(set) var isPreparing = false
    @Published private(set) var preparationFailed = false
    @Published var contentScale = IconImageProcessor.defaultContentScale {
        didSet { schedulePreviewRefresh() }
    }
    @Published var removeBackground = false {
        didSet { refreshPreviews() }
    }

    var canAddTask: Bool { imageURL != nil && imagePreview != nil && !folderURLs.isEmpty && !isPreparing }
    var canApply: Bool { !queue.isEmpty && !isPreparing && !preparationFailed }
    var folderCount: Int { queue.reduce(0) { $0 + $1.folderURLs.count } }

    private let service: FolderIconService
    private var previewGeneration = 0
    private var pendingPreviewRefresh: DispatchWorkItem?

    init(service: FolderIconService = FolderIconService()) {
        self.service = service
    }

    func receiveImages(_ urls: [URL]) {
        guard urls.count == 1, let url = urls.first,
              (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              NSImage(contentsOf: url) != nil else {
            show("请一次拖入一张图片文件。", error: true)
            return
        }
        imageURL = url
        refreshPreviews()
    }

    func receiveFolders(_ urls: [URL]) {
        guard !urls.isEmpty, urls.allSatisfy({
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }) else {
            show("这里只能拖入文件夹。", error: true)
            return
        }
        var seen = Set(folderURLs.map { $0.standardizedFileURL.resolvingSymlinksInPath() })
        for url in urls {
            let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
            if seen.insert(normalized).inserted { folderURLs.append(url) }
        }
        show("已选择 \(folderURLs.count) 个文件夹。")
    }

    func clearImage() {
        imageURL = nil
        imagePreview = nil
        refreshPreviews()
        show("已清除当前图片。")
    }

    func clearFolders() {
        folderURLs = []
        show("已清除当前文件夹。")
    }

    func addTask() {
        guard let imageURL, let imagePreview, !folderURLs.isEmpty else {
            show("先拖入一张图片和至少一个文件夹。", error: true)
            return
        }
        let queued = Set(queue.flatMap(\.folderURLs).map { $0.standardizedFileURL.resolvingSymlinksInPath() })
        let duplicates = folderURLs.filter { queued.contains($0.standardizedFileURL.resolvingSymlinksInPath()) }
        guard duplicates.isEmpty else {
            show("“\(duplicates[0].lastPathComponent)”已在任务清单中。每个文件夹只能配对一次。", error: true)
            return
        }
        queue.append(QueuedIconAssignment(
            imageURL: imageURL,
            folderURLs: folderURLs,
            preview: imagePreview,
            removeBackground: removeBackground
        ))
        let count = folderURLs.count
        self.imageURL = nil
        self.imagePreview = nil
        folderURLs = []
        show("已加入 \(count) 个文件夹，可继续拖入下一张图片。")
    }

    func removeTask(_ id: UUID) {
        queue.removeAll { $0.id == id }
        preparationFailed = false
        show("任务已移除。")
    }

    func clearTasks() {
        queue = []
        preparationFailed = false
        show("任务清单已清空。")
    }

    func applyTasks() {
        guard canApply else {
            show("先把图片和文件夹加入任务清单。", error: true)
            return
        }
        let assignments = queue.map {
            IconAssignment(imageURL: $0.imageURL, folderURLs: $0.folderURLs, removeBackground: $0.removeBackground)
        }
        let results = service.apply(assignments, contentScale: contentScale)
        var resultIndex = 0
        var failedQueue: [QueuedIconAssignment] = []
        for var task in queue {
            let taskResults = Array(results[resultIndex..<(resultIndex + task.folderURLs.count)])
            task.folderURLs = zip(task.folderURLs, taskResults).compactMap { url, result in
                result.succeeded ? nil : url
            }
            if !task.folderURLs.isEmpty { failedQueue.append(task) }
            resultIndex += taskResults.count
        }
        queue = failedQueue
        let successCount = results.filter(\.succeeded).count
        let failureCount = results.count - successCount
        if let firstError = results.first(where: { !$0.succeeded })?.error {
            show("已应用 \(successCount) 个，失败 \(failureCount) 个：\(firstError.localizedDescription)", error: true)
        } else {
            show("已成功修改 \(successCount) 个文件夹图标。")
        }
    }

    func restoreSelectedFolders() {
        guard !folderURLs.isEmpty else {
            show("先在右侧拖入需要恢复的文件夹。", error: true)
            return
        }
        let results = service.restoreOriginalIcon(for: folderURLs)
        let successCount = results.filter(\.succeeded).count
        if let firstError = results.first(where: { !$0.succeeded })?.error {
            show("已恢复 \(successCount) 个；\(firstError.localizedDescription)", error: true)
        } else {
            show("已恢复 \(successCount) 个文件夹原来的图标。")
        }
    }

    private func schedulePreviewRefresh() {
        previewGeneration += 1
        pendingPreviewRefresh?.cancel()
        guard imageURL != nil || !queue.isEmpty else { return }
        isPreparing = true
        let work = DispatchWorkItem { [weak self] in self?.refreshPreviews() }
        pendingPreviewRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180), execute: work)
    }

    private func refreshPreviews() {
        pendingPreviewRefresh?.cancel()
        pendingPreviewRefresh = nil
        previewGeneration += 1
        let generation = previewGeneration
        let currentURL = imageURL
        let currentRemoveBackground = removeBackground
        let scale = contentScale
        let queued = queue.map { ($0.id, $0.imageURL, $0.removeBackground) }
        imagePreview = nil
        preparationFailed = false
        isPreparing = currentURL != nil || !queued.isEmpty
        guard isPreparing else { return }
        show("正在准备图片预览…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let processor = IconImageProcessor()
            let current = currentURL.map { url in
                Result { try processor.makeIcon(from: url, contentScale: scale, removingBackground: currentRemoveBackground) }
            }
            let prepared = queued.map { id, url, removeBackground in
                (id, Result { try processor.makeIcon(from: url, contentScale: scale, removingBackground: removeBackground) })
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.previewGeneration == generation else { return }
                self.isPreparing = false
                if let current {
                    switch current {
                    case .success(let preview): self.imagePreview = preview
                    case .failure(let error):
                        self.preparationFailed = true
                        self.show(error.localizedDescription, error: true)
                    }
                }
                for (id, result) in prepared {
                    switch result {
                    case .success(let preview):
                        if let index = self.queue.firstIndex(where: { $0.id == id }) {
                            self.queue[index].preview = preview
                        }
                    case .failure(let error):
                        self.preparationFailed = true
                        self.show(error.localizedDescription, error: true)
                    }
                }
                if !self.preparationFailed { self.show("图片预览已更新。") }
            }
        }
    }

    private func show(_ text: String, error: Bool = false) {
        feedback = text
        feedbackIsError = error
    }
}
