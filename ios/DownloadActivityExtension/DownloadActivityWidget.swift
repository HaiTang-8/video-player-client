import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 16.2, *)
struct ProgressRingView: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)
            Image(systemName: "arrow.down")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(.blue)
        }
        .frame(width: size, height: size)
    }
}

@available(iOS 16.2, *)
struct DownloadActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ProgressRingView(progress: context.state.totalProgress, size: 28, lineWidth: 3)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.totalProgress * 100))%")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .contentTransition(.numericText())
                        .fixedSize()
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.totalTaskCount > 1 {
                        Text("\(context.state.activeTaskCount)/\(context.state.totalTaskCount) 个任务")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text(context.state.currentTaskName)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressView(value: context.state.totalProgress)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                            .animation(.linear(duration: 0.3), value: context.state.totalProgress)
                        HStack {
                            Text(formatBytes(context.state.totalDownloadedBytes))
                                .contentTransition(.numericText())
                            Text("/")
                            Text(formatBytes(context.state.totalBytes))
                            Spacer()
                            Text(formatSpeed(context.state.totalSpeed))
                                .contentTransition(.numericText())
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                ProgressRingView(progress: context.state.totalProgress, size: 16, lineWidth: 2)
                    .padding(.leading, 4)
            } compactTrailing: {
                if context.state.totalTaskCount > 1 {
                    Text("\(context.state.totalTaskCount)个")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .contentTransition(.numericText())
                } else {
                    Text("\(Int(context.state.totalProgress * 100))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .contentTransition(.numericText())
                }
            } minimal: {
                ProgressRingView(progress: context.state.totalProgress, size: 22, lineWidth: 2)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }
}

@available(iOS 16.2, *)
struct LockScreenView: View {
    let context: ActivityViewContext<DownloadActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                ProgressRingView(progress: context.state.totalProgress, size: 24, lineWidth: 2.5)
                if context.state.totalTaskCount > 1 {
                    Text("\(context.state.activeTaskCount)/\(context.state.totalTaskCount) 个任务下载中")
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text(context.state.currentTaskName)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }

            ProgressView(value: context.state.totalProgress)
                .progressViewStyle(.linear)
                .tint(statusColor)
                .animation(.linear(duration: 0.3), value: context.state.totalProgress)

            HStack {
                Text(formatBytes(context.state.totalDownloadedBytes))
                    .contentTransition(.numericText())
                Text("/")
                Text(formatBytes(context.state.totalBytes))
                Spacer()
                if context.state.status == "downloading" {
                    Text(formatSpeed(context.state.totalSpeed))
                        .contentTransition(.numericText())
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .activityBackgroundTint(Color(.systemBackground).opacity(0.8))
    }

    private var statusColor: Color {
        switch context.state.status {
        case "downloading": return .blue
        case "paused": return .orange
        case "completed": return .green
        default: return .blue
        }
    }

    private var statusText: String {
        switch context.state.status {
        case "downloading": return "下载中"
        case "paused": return "已暂停"
        case "completed": return "已完成"
        default: return ""
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }
}
