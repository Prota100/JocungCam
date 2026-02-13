import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recorder: ScreenRecorder
    @State private var isPlaying = true
    @State private var playTimer: Timer?
    @State private var speed: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.3)
            preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(0.3)
            timeline
            Divider().opacity(0.3)
            editToolbar
            Divider().opacity(0.3)
            bottomBar
        }
        .frame(minWidth: 600, minHeight: 520)
        .onAppear { startPlayback() }
        .onDisappear { stopPlayback() }
        .sheet(isPresented: $showCropSheet) { cropSheet }
        .sheet(isPresented: $showFrameTimeSheet) { frameTimeSheet }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet(isPresented: $showExportSheet, frames: appState.frames) { url in
                performSave(to: url)
            }.environmentObject(appState)
        }
    }

    // MARK: - Top Bar
    var topBar: some View {
        HStack(spacing: 8) {
            Button(action: { stopPlayback(); appState.reset() }) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 9))
                    Text("새로").font(HCTheme.caption)
                }
            }.buttonStyle(.plain).foregroundColor(HCTheme.textSecondary)

            Divider().frame(height: 14)

            // Stats
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    Image(systemName: "aspectratio").font(.system(size: 9))
                    Text(appState.frameSize).font(HCTheme.captionMono)
                }
                HStack(spacing: 3) {
                    Image(systemName: "film").font(.system(size: 9))
                    Text("\(appState.frames.count)f").font(HCTheme.captionMono)
                }
                HStack(spacing: 3) {
                    Image(systemName: "clock").font(.system(size: 9))
                    Text(String(format: "%.1fs", appState.totalDuration)).font(HCTheme.captionMono)
                }
            }.foregroundColor(HCTheme.textSecondary)

            Spacer()

            HCTag(appState.estimatedSize, color: HCTheme.accent)
        }
        .padding(.horizontal, HCTheme.padLg).padding(.vertical, 6)
    }

    // MARK: - Preview
    var preview: some View {
        ZStack {
            Color.black.opacity(0.3)
            if let f = appState.frames[safe: appState.selectedFrameIndex] {
                Image(nsImage: f.nsImage).resizable().aspectRatio(contentMode: .fit).padding(4)
            }
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 4) {
                HCIconButton(isPlaying ? "pause.fill" : "play.fill", help: "재생/정지") { togglePlayback() }
                HCIconButton("backward.frame.fill", help: "이전 프레임") { prevFrame() }
                HCIconButton("forward.frame.fill", help: "다음 프레임") { nextFrame() }

                Divider().frame(height: 14).opacity(0.3)

                Menu {
                    ForEach([0.25, 0.5, 1.0, 1.5, 2.0, 3.0], id: \.self) { s in
                        Button("\(s == Double(Int(s)) ? "\(Int(s))" : String(format: "%.2g", s))x") {
                            speed = s; if isPlaying { restartPlayback() }
                        }
                    }
                } label: {
                    Text(speed == 1.0 ? "1x" : String(format: "%.2gx", speed))
                        .font(HCTheme.microMono).foregroundColor(HCTheme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(HCTheme.accentDim).clipShape(Capsule())
                }

                Text("\(appState.selectedFrameIndex + 1)/\(appState.frames.count)")
                    .font(HCTheme.microMono).foregroundColor(HCTheme.textTertiary)
            }
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: HCTheme.radiusSm))
            .padding(6)
        }
        .contentShape(Rectangle())
        .onTapGesture { togglePlayback() }
    }

    // MARK: - Timeline
    @State private var trimMode = false
    @State private var trimStart: Int = 0
    @State private var trimEnd: Int = 0

    var timeline: some View {
        VStack(spacing: 0) {
            if trimMode {
                VStack(spacing: 8) {
                    // 트림 헤더
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "scissors").font(.system(size: 9))
                            Text("트림").font(.system(size: 10, weight: .bold))
                        }.foregroundColor(HCTheme.accent)

                        Text("\(trimStart + 1) ~ \(trimEnd + 1)").font(HCTheme.microMono).foregroundColor(HCTheme.textSecondary)
                        HCTag("\(trimEnd - trimStart + 1)프레임")

                        Spacer()

                        Button("적용") {
                            pushUndo()
                            appState.frames = Array(appState.frames[trimStart...trimEnd])
                            appState.selectedFrameIndex = 0; trimMode = false
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.borderedProminent).tint(HCTheme.accent).controlSize(.mini)

                        Button("취소") { trimMode = false }
                            .font(.system(size: 10)).controlSize(.mini)
                    }
                    
                    // QuickTime 스타일 트림 슬라이더
                    GeometryReader { geo in
                        let totalWidth = geo.size.width - 32
                        let frameCount = appState.frames.count
                        let startPos = totalWidth * CGFloat(trimStart) / CGFloat(max(1, frameCount - 1))
                        let endPos = totalWidth * CGFloat(trimEnd) / CGFloat(max(1, frameCount - 1))
                        
                        ZStack(alignment: .leading) {
                            // 배경 트랙
                            RoundedRectangle(cornerRadius: 2)
                                .fill(HCTheme.surface)
                                .frame(height: 6)
                                .offset(x: 16)
                            
                            // 선택된 범위
                            RoundedRectangle(cornerRadius: 2)
                                .fill(HCTheme.accent)
                                .frame(width: endPos - startPos + 16, height: 6)
                                .offset(x: 16 + startPos)
                            
                            // 시작 핸들
                            Circle()
                                .fill(HCTheme.accent)
                                .frame(width: 16, height: 16)
                                .offset(x: 8 + startPos)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            let mouseX = max(0, min(totalWidth, value.location.x - 16))
                                            let newFrame = Int(mouseX / totalWidth * CGFloat(frameCount - 1))
                                            trimStart = max(0, min(trimEnd - 1, newFrame))
                                        }
                                )
                            
                            // 끝 핸들
                            Circle()
                                .fill(HCTheme.accent)
                                .frame(width: 16, height: 16)
                                .offset(x: 8 + endPos)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            let mouseX = max(0, min(totalWidth, value.location.x - 16))
                                            let newFrame = Int(mouseX / totalWidth * CGFloat(frameCount - 1))
                                            trimEnd = max(trimStart + 1, min(frameCount - 1, newFrame))
                                        }
                                )
                        }
                    }
                    .frame(height: 16)
                }
                .padding(.horizontal, HCTheme.pad).padding(.vertical, 6)
                .background(HCTheme.accentDim)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 1) {
                        ForEach(Array(appState.frames.enumerated()), id: \.element.id) { i, f in
                            ZStack {
                                Image(nsImage: f.nsImage).resizable().aspectRatio(contentMode: .fill)
                                    .frame(width: 48, height: 64).clipped()

                                // Trim dim
                                if trimMode && (i < trimStart || i > trimEnd) {
                                    Color.black.opacity(0.65)
                                }

                                // Trim handles
                                if trimMode && i == trimStart {
                                    HStack { Rectangle().fill(HCTheme.accent).frame(width: 3); Spacer() }
                                }
                                if trimMode && i == trimEnd {
                                    HStack { Spacer(); Rectangle().fill(HCTheme.accent).frame(width: 3) }
                                }

                                // Selection
                                if i == appState.selectedFrameIndex {
                                    RoundedRectangle(cornerRadius: 2).stroke(HCTheme.accent, lineWidth: 2)
                                }
                            }
                            .onTapGesture {
                                if trimMode {
                                    if abs(i - trimStart) < abs(i - trimEnd) { trimStart = min(i, trimEnd) }
                                    else { trimEnd = max(i, trimStart) }
                                }
                                appState.selectedFrameIndex = i; stopPlayback()
                            }
                            .id(i)
                        }
                    }.padding(.horizontal, 4)
                }
                .onChange(of: appState.selectedFrameIndex) { _, v in
                    withAnimation(.easeOut(duration: 0.08)) { proxy.scrollTo(v, anchor: .center) }
                }
            }
            .frame(height: 68)
        }
    }

    // MARK: - Edit Toolbar
    var editToolbar: some View {
        HStack(spacing: 2) {
            // Undo/Redo
            HCIconButton("arrow.uturn.backward", help: "실행 취소") { undo() }
            HCIconButton("arrow.uturn.forward", help: "다시 실행") { redo() }

            Divider().frame(height: 16).opacity(0.3).padding(.horizontal, 2)

            // Frame ops
            HCIconButton("trash", help: "프레임 삭제", danger: true) { deleteFrame() }

            Menu {
                Button("짝수 프레임 제거") { pushUndo(); FrameOps.removeEvenFrames(&appState.frames) }
                Button("홀수 프레임 제거") { pushUndo(); FrameOps.removeOddFrames(&appState.frames) }
                Divider()
                Button("3번째마다 제거") { pushUndo(); FrameOps.removeEveryNth(3, frames: &appState.frames) }
                Button("5번째마다 제거") { pushUndo(); FrameOps.removeEveryNth(5, frames: &appState.frames) }
                Divider()
                Button("유사 프레임 제거") { pushUndo(); FrameOps.removeSimilar(frames: &appState.frames) }
            } label: {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 11))
                    .frame(width: 26, height: 26)
            }.menuStyle(.borderlessButton).frame(width: 26)

            Divider().frame(height: 16).opacity(0.3).padding(.horizontal, 2)

            // Speed
            HCIconButton("tortoise", help: "−10% 느리게") { pushUndo(); FrameOps.adjustSpeed(0.9, frames: &appState.frames) }
            HCIconButton("hare", help: "+10% 빠르게") { pushUndo(); FrameOps.adjustSpeed(1.1, frames: &appState.frames) }
            HCIconButton("arrow.left.arrow.right", help: "뒤집기") { pushUndo(); FrameOps.reverse(&appState.frames) }
            HCIconButton("infinity", help: "요요") { pushUndo(); FrameOps.yoyo(&appState.frames) }

            Divider().frame(height: 16).opacity(0.3).padding(.horizontal, 2)

            // Crop & Trim
            HCIconButton("crop", help: "자르기 (크롭)") { startCrop() }
            HCIconButton("scissors", help: "트림 (구간 자르기)") { startTrim() }
            HCIconButton("clock", help: "프레임 시간") { showFrameTimeSheet = true }

            Spacer()
        }
        .padding(.horizontal, HCTheme.pad).padding(.vertical, 4)
    }

    // MARK: - Bottom Bar
    @State private var showExportSheet = false

    var bottomBar: some View {
        HStack(spacing: 8) {
            // Quick format
            HStack(spacing: 4) {
                ForEach(OutputFormat.allCases) { fmt in
                    HCPillButton(fmt.rawValue, isActive: appState.outputFormat == fmt) {
                        appState.outputFormat = fmt
                    }
                }
            }

            Spacer()

            if let err = appState.errorText {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8))
                    Text(err).font(HCTheme.micro).lineLimit(1)
                }.foregroundColor(HCTheme.danger)
            }
            if appState.statusText != "" {
                HCTag(appState.statusText, color: HCTheme.success)
            }

            Button(action: copyToClipboard) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 11))
            }.buttonStyle(.bordered).controlSize(.small).help("클립보드 복사")

            Button(action: { showExportSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 10))
                    Text("내보내기").font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(HCTheme.accent)
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: HCTheme.radiusSm))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s")
        }
        .padding(.horizontal, HCTheme.padLg).padding(.vertical, 8)
    }

    // MARK: - Sheets

    @State private var showCropSheet = false
    @State private var cropX = "0"
    @State private var cropY = "0"
    @State private var cropW = ""
    @State private var cropH = ""

    var cropSheet: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "crop").foregroundColor(HCTheme.accent)
                Text("크롭").font(.system(size: 14, weight: .bold))
                Spacer()
            }
            Divider().opacity(0.3)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("위치").font(HCTheme.micro).foregroundColor(HCTheme.textTertiary)
                    HStack {
                        Text("X").font(HCTheme.microMono).frame(width: 12)
                        TextField("0", text: $cropX).frame(width: 55).textFieldStyle(.roundedBorder).font(HCTheme.captionMono)
                    }
                    HStack {
                        Text("Y").font(HCTheme.microMono).frame(width: 12)
                        TextField("0", text: $cropY).frame(width: 55).textFieldStyle(.roundedBorder).font(HCTheme.captionMono)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("크기").font(HCTheme.micro).foregroundColor(HCTheme.textTertiary)
                    HStack {
                        Text("W").font(HCTheme.microMono).frame(width: 14)
                        TextField("너비", text: $cropW).frame(width: 55).textFieldStyle(.roundedBorder).font(HCTheme.captionMono)
                    }
                    HStack {
                        Text("H").font(HCTheme.microMono).frame(width: 14)
                        TextField("높이", text: $cropH).frame(width: 55).textFieldStyle(.roundedBorder).font(HCTheme.captionMono)
                    }
                }
            }
            HStack(spacing: 4) {
                ForEach(["16:9", "4:3", "1:1", "9:16"], id: \.self) { ratio in
                    HCPillButton(ratio) { applyRatio(ratio) }
                }
            }
            Divider().opacity(0.3)
            HStack {
                Button("취소") { showCropSheet = false }.keyboardShortcut(.escape)
                Spacer()
                Button("적용") { applyCrop() }
                    .buttonStyle(.borderedProminent).tint(HCTheme.accent).keyboardShortcut(.return)
            }
        }.padding(HCTheme.padLg).frame(width: 280)
    }

    @State private var showFrameTimeSheet = false
    @State private var frameTimeMs: String = "66"

    var frameTimeSheet: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "clock").foregroundColor(HCTheme.accent)
                Text("프레임 시간").font(.system(size: 14, weight: .bold))
                Spacer()
            }
            Divider().opacity(0.3)
            HStack {
                TextField("ms", text: $frameTimeMs).frame(width: 60).textFieldStyle(.roundedBorder).font(HCTheme.captionMono)
                Text("ms").font(HCTheme.caption).foregroundColor(HCTheme.textSecondary)
            }
            HStack(spacing: 4) {
                ForEach([33, 50, 66, 100, 200], id: \.self) { ms in
                    HCPillButton("\(ms)ms") { frameTimeMs = "\(ms)" }
                }
            }
            Text("현재: \(String(format: "%.0fms", (appState.frames.first?.duration ?? 0.066) * 1000))")
                .font(HCTheme.micro).foregroundColor(HCTheme.textTertiary)
            Divider().opacity(0.3)
            HStack {
                Button("취소") { showFrameTimeSheet = false }.keyboardShortcut(.escape)
                Spacer()
                Button("현재만") {
                    if let ms = Double(frameTimeMs), ms > 0 {
                        pushUndo(); appState.frames[appState.selectedFrameIndex].duration = ms / 1000.0
                        showFrameTimeSheet = false
                    }
                }.buttonStyle(.bordered)
                Button("전체 적용") {
                    if let ms = Double(frameTimeMs), ms > 0 {
                        pushUndo(); FrameOps.setAllDuration(ms / 1000.0, frames: &appState.frames)
                        showFrameTimeSheet = false
                    }
                }.buttonStyle(.borderedProminent).tint(HCTheme.accent).keyboardShortcut(.return)
            }
        }.padding(HCTheme.padLg).frame(width: 280)
    }

    // MARK: - Undo
    @State private var undoStack: [[GIFFrame]] = []
    @State private var redoStack: [[GIFFrame]] = []

    func pushUndo() {
        undoStack.append(appState.frames)
        if undoStack.count > 30 { undoStack.removeFirst() }
        redoStack = []
    }
    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(appState.frames); appState.frames = prev
        appState.selectedFrameIndex = min(appState.selectedFrameIndex, appState.frames.count - 1)
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(appState.frames); appState.frames = next
        appState.selectedFrameIndex = min(appState.selectedFrameIndex, appState.frames.count - 1)
    }

    // MARK: - Actions
    func deleteFrame() {
        pushUndo()
        FrameOps.deleteFrame(at: appState.selectedFrameIndex, from: &appState.frames)
        appState.selectedFrameIndex = min(appState.selectedFrameIndex, appState.frames.count - 1)
    }

    func startCrop() {
        guard let f = appState.frames.first else { return }
        cropW = "\(f.image.width)"; cropH = "\(f.image.height)"; cropX = "0"; cropY = "0"
        showCropSheet = true
    }

    func startTrim() { trimStart = 0; trimEnd = appState.frames.count - 1; trimMode = true }

    func applyRatio(_ ratio: String) {
        guard let f = appState.frames.first else { return }
        let parts = ratio.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        let w = f.image.width; let h = w * parts[1] / parts[0]
        cropW = "\(w)"; cropH = "\(min(h, f.image.height))"
        cropX = "0"; cropY = "\((f.image.height - min(h, f.image.height)) / 2)"
    }

    func applyCrop() {
        guard let x = Int(cropX), let y = Int(cropY), let w = Int(cropW), let h = Int(cropH),
              w > 0, h > 0, let first = appState.frames.first else { return }
        let cx = max(0, min(x, first.image.width - 1))
        let cy = max(0, min(y, first.image.height - 1))
        let cw = min(w, first.image.width - cx), ch = min(h, first.image.height - cy)
        guard cw > 0, ch > 0 else { appState.errorText = "유효하지 않은 크롭 영역"; return }
        pushUndo()
        FrameOps.crop(CGRect(x: cx, y: cy, width: cw, height: ch), frames: &appState.frames)
        showCropSheet = false
        appState.statusText = "크롭 → \(cw)×\(ch)"
    }

    func copyToClipboard() {
        let frames = appState.frames
        let opts = GIFEncoder.Options(maxColors: appState.gifQuality.maxColors, dither: appState.useDither,
            ditherLevel: appState.ditherLevel, speed: appState.liqSpeed, quality: appState.liqQuality, maxWidth: appState.maxWidth)
        appState.statusText = "복사 중..."
        Task.detached {
            if let data = try? GIFEncoder.encodeToData(frames: frames, options: opts) {
                Task { @MainActor in
                    let pb = NSPasteboard.general; pb.clearContents()
                    pb.setData(data, forType: .tiff)
                    pb.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
                    appState.statusText = "복사됨 ✓"
                }
            }
        }
    }

    func performSave(to url: URL) {
        stopPlayback()
        appState.mode = .saving
        let frames = appState.frames
        let format = appState.outputFormat
        let opts = GIFEncoder.Options(
            maxColors: appState.gifQuality.maxColors, dither: appState.useDither,
            ditherLevel: appState.ditherLevel, speed: appState.liqSpeed, quality: appState.liqQuality,
            loopCount: appState.loopCount, maxWidth: appState.maxWidth, maxFileSizeKB: appState.maxFileSizeKB,
            removeSimilarPixels: appState.removeSimilarPixels, centerFocusedDither: appState.centerFocusedDither,
            skipQuantizeWhenQ100: appState.skipQuantizeWhenQ100
        )
        let mp4q = appState.mp4Quality
        let useGifski = appState.useGifski
        let webpQuality = appState.webpQuality
        let webpLossless = appState.webpLossless
        let loopCount = appState.loopCount
        Task.detached {
            do {
                switch format {
                case .gif:
                    if useGifski && GifskiEncoder.isAvailable {
                        let gopts = GifskiEncoder.Options(fps: Int(1.0 / (frames.first?.duration ?? 0.066)),
                            quality: opts.quality, maxWidth: opts.maxWidth, loopCount: opts.loopCount)
                        try await GifskiEncoder.encode(frames: frames, to: url, options: gopts) { p in
                            Task { @MainActor in appState.saveProgress = p }
                        }
                    } else {
                        try GIFEncoder.encode(frames: frames, to: url, options: opts) { p in
                            Task { @MainActor in appState.saveProgress = p }
                        }
                    }
                case .mp4:
                    try await MP4Encoder.encode(frames: frames, to: url, quality: mp4q) { p in
                        Task { @MainActor in appState.saveProgress = p }
                    }
                case .webp:
                    if WebPEncoder.isAvailable {
                        let wopts = WebPEncoder.Options(quality: webpQuality, lossless: webpLossless,
                            fps: Int(1.0 / (frames.first?.duration ?? 0.066)), loopCount: loopCount, maxWidth: opts.maxWidth)
                        try await WebPEncoder.encode(frames: frames, to: url, options: wopts) { p in
                            Task { @MainActor in appState.saveProgress = p }
                        }
                    } else {
                        try GIFEncoder.encode(frames: frames, to: url, options: opts) { p in
                            Task { @MainActor in appState.saveProgress = p }
                        }
                    }
                case .apng:
                    // APNG는 GIFEncoder와 동일한 ImageIO 기반이므로 async 아님
                    try GIFEncoder.encode(frames: frames, to: url, options: opts) { p in
                        Task { @MainActor in appState.saveProgress = p }
                    }
                }
                Task { @MainActor in
                    appState.mode = .editing; appState.statusText = "저장 완료 ✓"
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                Task { @MainActor in appState.errorText = error.localizedDescription; appState.mode = .editing }
            }
        }
    }

    // MARK: - Playback
    func togglePlayback() { if isPlaying { stopPlayback() } else { startPlayback() } }
    func startPlayback() { isPlaying = true; scheduleNext() }
    func stopPlayback() { isPlaying = false; playTimer?.invalidate(); playTimer = nil }
    func restartPlayback() { stopPlayback(); startPlayback() }
    func scheduleNext() {
        guard isPlaying, !appState.frames.isEmpty else { isPlaying = false; return }
        let dur = appState.frames[appState.selectedFrameIndex].duration / speed
        playTimer = Timer.scheduledTimer(withTimeInterval: max(0.005, dur), repeats: false) { _ in
            Task { @MainActor in nextFrame(); if isPlaying { scheduleNext() } }
        }
    }
    func nextFrame() { appState.selectedFrameIndex = (appState.selectedFrameIndex + 1) % max(1, appState.frames.count) }
    func prevFrame() { appState.selectedFrameIndex = appState.selectedFrameIndex > 0 ? appState.selectedFrameIndex - 1 : appState.frames.count - 1 }
}

struct SavingView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().stroke(HCTheme.border, lineWidth: 4).frame(width: 80, height: 80)
                Circle().trim(from: 0, to: appState.saveProgress)
                    .stroke(HCTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 80, height: 80).rotationEffect(.degrees(-90))
                Text("\(Int(appState.saveProgress * 100))%")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
            }
            Text("\(appState.outputFormat.rawValue) 생성 중...")
                .font(HCTheme.caption).foregroundColor(HCTheme.textSecondary)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
