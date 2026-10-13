import AppKit
import SwiftUI

struct IconDropPanel: View {
    @ObservedObject var model: IconDropViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(spacing: 12) {
                DropCard(title: "图片", subtitle: "一次一张", onDrop: model.receiveImages) {
                    if let url = model.imageURL {
                        if let preview = model.imagePreview {
                            Image(nsImage: preview)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 76, height: 76)
                        } else if model.isPreparing {
                            ProgressView().frame(width: 76, height: 76)
                        } else {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 34))
                                .frame(width: 76, height: 76)
                        }
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 38))
                            .foregroundStyle(.tertiary)
                        Text("拖入或粘贴图片")
                            .font(.headline)
                        Text("一次一张 · 支持 ⌘V")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DropCard(title: "文件夹", subtitle: "可拖入多个", onDrop: model.receiveFolders) {
                    if model.folderURLs.isEmpty {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 38))
                            .foregroundStyle(.tertiary)
                        Text("拖入文件夹")
                            .font(.headline)
                        Text("一次可选一个或多个")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        Text("已选 \(model.folderURLs.count) 个")
                            .font(.headline)
                        Text(model.folderURLs.prefix(2).map(\.lastPathComponent).joined(separator: "、"))
                            .lineLimit(1)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 178)
            .disabled(model.isApplying)

            HStack {
                Button("粘贴图片") { model.pasteImageFromClipboard() }
                    .keyboardShortcut("v", modifiers: .command)
                    .buttonStyle(.bordered)
                Button("清除图片") { model.clearImage() }
                    .disabled(model.imageURL == nil)
                    .buttonStyle(.plain)
                Spacer()
                Button("清除文件夹") { model.clearFolders() }
                    .disabled(model.folderURLs.isEmpty || model.isApplying)
                    .buttonStyle(.plain)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .disabled(model.isApplying)

            HStack(spacing: 16) {
                Label("图案大小", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline)
                    .frame(width: 100, alignment: .leading)
                Slider(value: $model.contentScale, in: 0.4...0.95)
                    .disabled(model.isApplying)
                    .accessibilityLabel("图案大小")
                Text("\(Int(model.contentScale * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }

            Toggle("移除背景", isOn: $model.removeBackground)
                .disabled(model.isApplying)
                .font(.subheadline)
                .help("使用 macOS 识别图片主体；此设置随当前图片一起加入任务。")

            HStack {
                Spacer()
                Button("恢复所选原图标") { model.restoreSelectedFolders() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .disabled(model.folderURLs.isEmpty || model.isApplying)
                Button("加入任务") { model.addTask() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canAddTask)
            }

            Divider()

            HStack {
                Text("待应用")
                    .font(.headline)
                Text("\(model.folderCount) 个文件夹")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.queue.isEmpty {
                    Button("清空") { model.clearTasks() }
                        .disabled(model.isApplying)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    if model.queue.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 24))
                            Text("任务会显示在这里")
                                .font(.subheadline)
                            Text("不同文件夹可分别配对不同图片")
                                .font(.caption)
                        }
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 118)
                    } else {
                        ForEach(model.queue) { task in
                            HStack(spacing: 10) {
                                Image(nsImage: task.preview)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 42, height: 42)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.imageURL.lastPathComponent)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    if task.removeBackground {
                                        Text("已移除背景")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(task.folderURLs.map(\.lastPathComponent).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\(task.folderURLs.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Button { model.removeTask(task.id) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("移除任务")
                                .disabled(model.isApplying)
                            }
                            .padding(9)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .frame(minHeight: 126, maxHeight: 164)

            if model.isApplying {
                ProgressView(value: Double(model.completedFolderCount), total: Double(model.totalFolderCount))
                    .accessibilityLabel("应用进度")
                Text("正在应用 \(model.completedFolderCount)/\(model.totalFolderCount) 个文件夹")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if let feedback = model.feedback {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(model.feedbackIsError ? .red : .secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Button("应用全部") { model.applyTasks() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canApply)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("IconDrop")
                    .font(.title3.weight(.semibold))
                Text("拖入、配对、预览、应用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("BETA")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
            Menu {
                Button("退出 IconDrop") { NSApplication.shared.terminate(nil) }
                    .disabled(model.isApplying)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("更多选项")
        }
    }
}

private struct DropCard<Content: View>: View {
    let title: String
    let subtitle: String
    let onDrop: ([URL]) -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
        .overlay(FileDropSurface(onDrop: onDrop))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)拖入区域，\(subtitle)")
    }
}
