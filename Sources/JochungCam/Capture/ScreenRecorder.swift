import ScreenCaptureKit
import CoreGraphics
import AppKit

@MainActor
final class ScreenRecorder: ObservableObject {
    private var stream: SCStream?
    private var output: FrameOutput?
    private var timer: Timer?
    private var startTime: Date?
    let cursorTracker = CursorTracker()

    func getRegionForMode(_ mode: AppState.CaptureMode) -> CGRect? {
        // 마우스 커서가 있는 스크린 사용 (더블 모니터 지원)
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else { return nil }
        let f = screen.frame
        // 좌표를 스크린 기준으로 정규화 (0,0 시작)
        switch mode {
        case .region: return nil // user selects
        case .fullscreen: return CGRect(x: 0, y: 0, width: f.width, height: f.height)
        case .halfscreen: return CGRect(x: 0, y: 0, width: f.width, height: f.height / 2)
        case .quarterscreen: return CGRect(x: 0, y: 0, width: f.width / 2, height: f.height / 2)
        }
    }

    func startRecording(region: CGRect, appState: AppState) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        // 마우스 위치 기반으로 적절한 디스플레이 찾기
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        
        // CGDirectDisplayID로 매칭되는 SCDisplay 찾기
        guard let screen = targetScreen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first 
        else { throw RecordError.noDisplay }

        let myWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingWindows: myWindows)

        let config = SCStreamConfiguration()
        config.sourceRect = region
        config.width = Int(region.width * 2)
        config.height = Int(region.height * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(appState.fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = appState.cursorCapture
        config.capturesAudio = false

        let output = FrameOutput(fps: appState.fps, skipSame: appState.skipSameFrames)
        self.output = output

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()
        self.stream = stream
        self.startTime = Date()

        appState.selectedRegion = region
        if appState.rememberRegion { appState.lastRegion = region }
        appState.mode = .recording
        appState.errorText = nil

        // Start cursor tracking if effects enabled
        if appState.cursorEffect || appState.cursorHighlight {
            cursorTracker.start(region: region)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                appState.recordingDuration = Date().timeIntervalSince(start)
                appState.frameCount = self.output?.count ?? 0
                if appState.frameCount >= AppState.maxFrames ||
                   appState.recordingDuration >= Double(appState.maxRecordSeconds) {
                    await self.stopRecording(appState: appState)
                }
            }
        }
    }

    func pauseRecording(appState: AppState) { output?.isPaused = true; appState.mode = .paused }
    func resumeRecording(appState: AppState) { output?.isPaused = false; appState.mode = .recording }

    func stopRecording(appState: AppState) async {
        timer?.invalidate(); timer = nil
        cursorTracker.stop()
        if let stream { try? await stream.stopCapture(); self.stream = nil }
        var captured = output?.harvest() ?? []
        output = nil

        // Apply cursor effects if enabled
        if (appState.cursorEffect || appState.cursorHighlight) && !captured.isEmpty {
            let scale = CGFloat(captured[0].image.width) / appState.selectedRegion.width
            let opts = CursorTracker.RenderOptions(
                highlightColor: appState.cursorHighlightColor,
                leftClickColor: appState.cursorLeftClickColor,
                rightClickColor: appState.cursorRightClickColor
            )
            captured = cursorTracker.renderOntoFrames(captured, region: appState.selectedRegion, scale: scale, options: opts)
        }
        if captured.isEmpty {
            appState.errorText = "프레임이 캡처되지 않았습니다. 화면 녹화 권한을 확인하세요."
            appState.mode = .home
        } else if appState.directSave {
            // 다이렉트 세이브: 편집 스킵 → 바로 GIF
            appState.mode = .saving
            let frames = captured.map { f -> GIFFrame in
                var out = f
                if f.image.width > 2560 { out.image = downsample(f.image, factor: 2) ?? f.image }
                return out
            }
            let opts = GIFEncoder.Options(
                maxColors: appState.gifQuality.maxColors, dither: appState.useDither,
                ditherLevel: appState.ditherLevel, speed: appState.liqSpeed, quality: appState.liqQuality,
                maxWidth: appState.maxWidth, removeSimilarPixels: appState.removeSimilarPixels
            )
            let useGifski = appState.useGifski
            let ts = { let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"; return f.string(from: Date()) }()
            let dir = appState.directSavePath.isEmpty ?
                FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first! :
                URL(fileURLWithPath: appState.directSavePath)
            let url = dir.appendingPathComponent("jochung_\(ts).gif")
            Task.detached {
                do {
                    if useGifski && GifskiEncoder.isAvailable {
                        let gopts = GifskiEncoder.Options(
                            fps: Int(1.0 / (frames.first?.duration ?? 0.066)),
                            quality: opts.quality, maxWidth: opts.maxWidth
                        )
                        try GifskiEncoder.encode(frames: frames, to: url, options: gopts) { p in
                            Task { @MainActor in appState.saveProgress = p }
                        }
                    } else {
                        try GIFEncoder.encode(frames: frames, to: url, options: opts) { p in
                            Task { @MainActor in appState.saveProgress = p }
                        }
                    }
                    Task { @MainActor in
                        appState.statusText = "저장 완료 ✓"
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        appState.mode = .home
                    }
                } catch {
                    Task { @MainActor in appState.errorText = error.localizedDescription; appState.mode = .home }
                }
            }
        } else {
            appState.enterEditor(with: captured)
        }
    }

    var isActive: Bool { stream != nil }

    private func downsample(_ img: CGImage, factor: Int) -> CGImage? {
        let nw = img.width / factor, nh = img.height / factor
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }
}

final class FrameOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private var _frames: [GIFFrame] = []
    private let lock = NSLock()
    private let targetFps: Int
    private let skipSame: Bool
    private var lastTime: Date?
    private var lastPixelHash: UInt64 = 0
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    var isPaused = false
    var count: Int { lock.withLock { _frames.count } }

    init(fps: Int, skipSame: Bool) {
        self.targetFps = fps; self.skipSame = skipSame; super.init()
    }

    func harvest() -> [GIFFrame] { lock.withLock { let o = _frames; _frames = []; return o } }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !isPaused else { return }
        guard let buf = sb.imageBuffer else { return }

        let ci = CIImage(cvImageBuffer: buf)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }

        // Skip same frame (simple hash)
        if skipSame {
            let hash = quickHash(cg)
            if hash == lastPixelHash { return }
            lastPixelHash = hash
        }

        let now = Date()
        let dur: TimeInterval
        if let last = lastTime { dur = min(now.timeIntervalSince(last), 1.0) }
        else { dur = 1.0 / Double(targetFps) }
        lastTime = now

        lock.withLock { _frames.append(GIFFrame(image: cg, duration: dur)) }
    }

    private func quickHash(_ img: CGImage) -> UInt64 {
        // Sample a few pixels for fast comparison
        let w = img.width, h = img.height
        guard let data = img.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return 0 }
        let bpr = img.bytesPerRow
        var hash: UInt64 = 0
        let samples = [(w/4, h/4), (w/2, h/2), (3*w/4, 3*h/4), (w/3, h/3)]
        for (x, y) in samples {
            let offset = y * bpr + x * 4
            if offset + 3 < CFDataGetLength(data) {
                hash = hash &* 31 &+ UInt64(ptr[offset]) &* 17 &+ UInt64(ptr[offset+1]) &* 13 &+ UInt64(ptr[offset+2])
            }
        }
        return hash
    }
}

enum RecordError: Error, LocalizedError {
    case noDisplay
    var errorDescription: String? { "디스플레이를 찾을 수 없습니다" }
}
