import SwiftUI
import UniformTypeIdentifiers

struct ExportSheet: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    let frames: [GIFFrame]
    let onExport: (URL) -> Void

    @State private var estimatedSize: String = ""
    @State private var previewImage: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("내보내기").font(.system(size: 14, weight: .bold))
                Spacer()
                Text(frameInfo).font(.caption.monospaced()).foregroundColor(.secondary)
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // Preview
                    if let img = previewImage {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 120).cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
                    }

                    // Format selector
                    formatSection

                    Divider().padding(.horizontal)

                    // Format-specific options
                    switch appState.outputFormat {
                    case .gif: gifOptions
                    case .webp: webpOptions
                    case .mp4: mp4Options
                    case .apng: apngOptions
                    }

                    Divider().padding(.horizontal)

                    // Common options
                    commonOptions

                    Divider().padding(.horizontal)

                    // Presets
                    if appState.outputFormat == .gif {
                        presetSection
                    }
                }
                .padding(12)
            }

            Divider()

            // Bottom bar
            HStack {
                // Estimated size
                HStack(spacing: 4) {
                    Image(systemName: "doc").font(.caption2)
                    Text(estimatedSize).font(.caption.monospaced().bold())
                }.foregroundColor(.secondary)

                Spacer()

                Button("취소") { isPresented = false }
                    .keyboardShortcut(.escape)

                Button(action: doExport) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("저장")
                    }.font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent).tint(.yellow)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(minWidth: 420, maxWidth: 420, minHeight: 500, maxHeight: 700)
        .onAppear {
            updatePreview()
            updateEstimate()
        }
        .onChange(of: appState.outputFormat) { _, _ in updateEstimate() }
        .onChange(of: appState.gifQuality) { _, _ in updateEstimate() }
        .onChange(of: appState.maxWidth) { _, _ in updateEstimate() }
    }

    // MARK: - Frame info
    var frameInfo: String {
        guard let f = frames.first else { return "" }
        let dur = frames.reduce(0.0) { $0 + $1.duration }
        return "\(f.image.width)×\(f.image.height) · \(frames.count)f · \(String(format: "%.1fs", dur))"
    }

    // MARK: - Format
    var formatSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("포맷")
            HStack(spacing: 6) {
                ForEach(OutputFormat.allCases) { fmt in
                    Button {
                        appState.outputFormat = fmt
                    } label: {
                        VStack(spacing: 2) {
                            Text(fmt.rawValue).font(.system(size: 12, weight: .semibold))
                            Text(formatDesc(fmt)).font(.system(size: 8)).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(appState.outputFormat == fmt ? .yellow : .secondary.opacity(0.2))
                }
            }
        }
    }

    func formatDesc(_ f: OutputFormat) -> String {
        switch f {
        case .gif: return "움짤"
        case .webp: return "고압축"
        case .mp4: return "영상"
        case .apng: return "투명지원"
        }
    }

    // MARK: - GIF Options
    var gifOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("GIF 설정")

            // Encoder
            HStack {
                Text("인코더").font(.caption2).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                Picker("", selection: $appState.useGifski) {
                    Text("gifski (최고 화질)").tag(true)
                    Text("libimagequant (빠름)").tag(false)
                }.labelsHidden().controlSize(.small)
                if appState.useGifski {
                    Circle().fill(GifskiEncoder.isAvailable ? Color.green : Color.red).frame(width: 6, height: 6)
                    Text(GifskiEncoder.isAvailable ? "사용 가능" : "미설치").font(.system(size: 9)).foregroundColor(.secondary)
                }
            }

            // Colors
            HStack {
                Text("색상 수").font(.caption2).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                ForEach(GIFQuality.allCases) { q in
                    Button(q.rawValue) { appState.gifQuality = q }
                        .buttonStyle(.bordered)
                        .tint(appState.gifQuality == q ? .yellow : .secondary.opacity(0.2))
                        .controlSize(.mini)
                }
            }

            // Dithering
            HStack {
                Text("디더링").font(.caption2).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                Toggle("", isOn: $appState.useDither).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                if appState.useDither {
                    Slider(value: $appState.ditherLevel, in: 0...1).frame(width: 80)
                    Text(String(format: "%.1f", appState.ditherLevel)).font(.caption2.monospaced()).frame(width: 22)
                }
            }

            if !appState.useGifski {
                // LIQ settings (only for libimagequant)
                HStack {
                    Text("LIQ 속도").font(.caption2).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                    Slider(value: Binding(get: { Double(appState.liqSpeed) }, set: { appState.liqSpeed = Int($0) }), in: 1...10, step: 1).frame(width: 100)
                    Text("\(appState.liqSpeed)").font(.caption2.monospaced()).frame(width: 16)
                    Text("1=최고화질").font(.system(size: 8)).foregroundColor(.secondary.opacity(0.5))
                }
                HStack {
                    Text("LIQ 품질").font(.caption2).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                    Slider(value: Binding(get: { Double(appState.liqQuality) }, set: { appState.liqQuality = Int($0) }), in: 1...100, step: 1).frame(width: 100)
                    Text("\(appState.liqQuality)").font(.caption2.monospaced()).frame(width: 24)
                }
            }

            // Advanced GIF
            HStack {
                Toggle("유사 픽셀 제거", isOn: $appState.removeSimilarPixels).font(.caption2)
                Toggle("Q100 스킵", isOn: $appState.skipQuantizeWhenQ100).font(.caption2)
            }
        }
    }

    // MARK: - WebP Options
    var webpOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("WebP 설정")
            if !WebPEncoder.isAvailable {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                    Text("brew install webp 필요").font(.caption)
                }
            }
            HStack {
                Text("품질").font(.caption2).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                Slider(value: Binding(get: { Double(appState.webpQuality) }, set: { appState.webpQuality = Int($0) }), in: 1...100).frame(width: 140)
                Text("\(appState.webpQuality)").font(.caption2.monospaced()).frame(width: 24)
            }
            HStack {
                Text("모드").font(.caption2).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                Toggle("무손실", isOn: $appState.webpLossless).toggleStyle(.checkbox).font(.caption2)
            }
        }
    }

    // MARK: - MP4 Options
    var mp4Options: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("MP4 설정")
            HStack {
                Text("품질").font(.caption2).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                Slider(value: Binding(get: { Double(appState.mp4Quality) }, set: { appState.mp4Quality = Int($0) }), in: 10...100).frame(width: 140)
                Text("\(appState.mp4Quality)").font(.caption2.monospaced()).frame(width: 24)
            }
            Text("H.264 인코딩 · AVFoundation").font(.system(size: 9)).foregroundColor(.secondary.opacity(0.5)).padding(.leading, 66)
        }
    }

    // MARK: - APNG Options
    var apngOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("APNG 설정")
            Text("ImageIO 네이티브 인코딩 · 투명 배경 지원").font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - Common
    var commonOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("출력 설정")

            HStack {
                Text("최대 너비").font(.caption2).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                TextField("0 = 원본", value: $appState.maxWidth, format: .number)
                    .frame(width: 60).textFieldStyle(.roundedBorder).font(.caption2)
                Text("px").font(.caption2).foregroundColor(.secondary)
                if appState.maxWidth > 0, let f = frames.first {
                    let scale = Double(appState.maxWidth) / Double(f.image.width)
                    let nh = Int(Double(f.image.height) * scale)
                    Text("→ \(appState.maxWidth)×\(nh)").font(.caption2.monospaced()).foregroundColor(.yellow)
                }
            }

            HStack {
                Text("파일 제한").font(.caption2).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                TextField("0 = 무제한", value: $appState.maxFileSizeKB, format: .number)
                    .frame(width: 60).textFieldStyle(.roundedBorder).font(.caption2)
                Text("KB").font(.caption2).foregroundColor(.secondary)
                if appState.maxFileSizeKB > 0 {
                    Text("(\(appState.maxFileSizeKB / 1024)MB)").font(.caption2).foregroundColor(.secondary)
                }
            }

            HStack {
                Text("루프").font(.caption2).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                TextField("0", value: $appState.loopCount, format: .number)
                    .frame(width: 40).textFieldStyle(.roundedBorder).font(.caption2)
                Text("0 = 무한반복").font(.system(size: 9)).foregroundColor(.secondary.opacity(0.5))
            }
        }
    }

    // MARK: - Presets
    var presetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("빠른 프리셋")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 6) {
                ForEach(GIFSizePreset.allCases) { preset in
                    Button {
                        appState.maxWidth = preset.maxWidth
                        appState.gifQuality = preset.quality
                        appState.maxFileSizeKB = preset.maxFileSizeKB
                        appState.liqSpeed = preset.liqSpeed
                    } label: {
                        VStack(spacing: 2) {
                            Text(preset.label).font(.caption.bold())
                            Text(presetDetail(preset)).font(.system(size: 8)).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(isActivePreset(preset) ? .yellow : .secondary.opacity(0.15))
                }
            }
        }
    }

    func presetDetail(_ p: GIFSizePreset) -> String {
        switch p {
        case .light: return "400px · 1MB"
        case .normal: return "640px · 3MB" 
        case .discord: return "480px · 10MB"
        case .high: return "원본 · 무제한"
        }
    }

    func isActivePreset(_ p: GIFSizePreset) -> Bool {
        appState.maxWidth == p.maxWidth && appState.gifQuality == p.quality && appState.maxFileSizeKB == p.maxFileSizeKB
    }

    // MARK: - Helpers

    func sectionHeader(_ title: String) -> some View {
        Text(title).font(.caption.bold()).foregroundColor(.primary)
    }

    func updatePreview() {
        if let f = frames.first {
            previewImage = f.nsImage
        }
    }

    func updateEstimate() {
        guard let f = frames.first else { estimatedSize = ""; return }
        let w = appState.maxWidth > 0 ? min(appState.maxWidth, f.image.width) : f.image.width
        let h = appState.maxWidth > 0 ? Int(Double(f.image.height) * Double(w) / Double(f.image.width)) : f.image.height
        let px = w * h
        let bpf: Double
        switch appState.outputFormat {
        case .gif: bpf = Double(px) * Double(appState.gifQuality.maxColors) / 256.0 * 0.4
        case .webp: bpf = Double(px) * (appState.webpLossless ? 0.5 : 0.15)
        case .mp4: bpf = Double(px) * 0.08
        case .apng: bpf = Double(px) * 0.6
        }
        let total = bpf * Double(frames.count)
        if appState.maxFileSizeKB > 0 {
            let limited = min(total, Double(appState.maxFileSizeKB) * 1024)
            estimatedSize = formatBytes(limited) + " (제한: \(formatBytes(Double(appState.maxFileSizeKB) * 1024)))"
        } else {
            estimatedSize = "~" + formatBytes(total)
        }
    }

    func formatBytes(_ b: Double) -> String {
        b >= 1_048_576 ? String(format: "%.1fMB", b / 1_048_576) : String(format: "%.0fKB", b / 1024)
    }

    func doExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: appState.outputFormat.ext) ?? .gif]
        let ts = { let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"; return f.string(from: Date()) }()
        panel.nameFieldStringValue = "jochung_\(ts).\(appState.outputFormat.ext)"
        panel.begin { r in
            guard r == .OK, let url = panel.url else { return }
            isPresented = false
            onExport(url)
        }
    }
}
