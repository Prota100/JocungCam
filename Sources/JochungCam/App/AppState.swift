import SwiftUI
import Combine

enum AppMode: Equatable {
    case home
    case selecting
    case recording
    case paused
    case editing
    case cropping
    case saving
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case gif = "GIF"
    case webp = "WebP"
    case apng = "APNG"
    case mp4 = "MP4"
    var id: String { rawValue }
    var ext: String { rawValue.lowercased() }
}

enum QuantMethod: String, CaseIterable, Identifiable {
    case liq = "LIQ"
    case neuquant = "NeuQuant"
    case octree = "Octree"
    var id: String { rawValue }
}

enum GIFQuality: String, CaseIterable, Identifiable {
    case high = "256색"
    case medium = "128색"
    case low = "64색"
    case tiny = "32색"
    var id: String { rawValue }
    var maxColors: Int {
        switch self { case .high: 256; case .medium: 128; case .low: 64; case .tiny: 32 }
    }
}

enum GIFSizePreset: String, CaseIterable, Identifiable {
    case light = "가벼움"       // 1MB, 작은 해상도
    case normal = "보통"        // 3MB, 적당한 해상도
    case discord = "디스코드"   // 10MB 제한
    case high = "고화질"        // 큰 파일, 원본 해상도

    var id: String { rawValue }
    var label: String { rawValue }

    var maxWidth: Int {
        switch self {
        case .light: return 400      // 가벼움: 400px
        case .normal: return 640     // 보통: 640px 
        case .discord: return 480    // 디스코드: 480px (10MB 제한)
        case .high: return 0         // 고화질: 원본 해상도
        }
    }
    var quality: GIFQuality {
        switch self {
        case .light: return .low     // 가벼움: 64색
        case .normal: return .medium // 보통: 128색
        case .discord: return .high  // 디스코드: 256색
        case .high: return .high     // 고화질: 256색
        }
    }
    var maxFileSizeKB: Int {
        switch self {
        case .light: return 1000     // 가벼움: 1MB
        case .normal: return 3000    // 보통: 3MB
        case .discord: return 10000  // 디스코드: 10MB
        case .high: return 0         // 고화질: 무제한
        }
    }
    var liqSpeed: Int {
        switch self {
        case .high: return 1         // 고화질: 최고 품질
        case .light: return 8        // 가벼움: 빠른 처리
        default: return 4            // 보통: 균형
        }
    }
}

struct SizePreset: Identifiable {
    let id = UUID()
    let label: String
    let width: Int
    let height: Int
    static let presets: [SizePreset] = [
        .init(label: "320×240", width: 320, height: 240),
        .init(label: "480×360", width: 480, height: 360),
        .init(label: "640×480", width: 640, height: 480),
        .init(label: "800×600", width: 800, height: 600),
        .init(label: "1024×768", width: 1024, height: 768),
        .init(label: "1280×720", width: 1280, height: 720),
        .init(label: "1920×1080", width: 1920, height: 1080),
    ]
}

@MainActor
final class AppState: ObservableObject {
    // Mode
    @Published var mode: AppMode = .home

    // Recording settings
    @Published var fps: Int = 15             // 기본: 15fps (가벼움)
    @Published var customFps: String = "15"
    @Published var cursorCapture: Bool = true
    @Published var countdown: Int = 0  // 0=off, 3, 5
    @Published var skipSameFrames: Bool = true
    @Published var maxRecordSeconds: Int = 60
    @Published var rememberRegion: Bool = false
    @Published var lastRegion: CGRect = .zero
    @Published var captureMode: CaptureMode = .region

    enum CaptureMode: String, CaseIterable { case region = "영역"; case fullscreen = "전체"; case halfscreen = "1/2"; case quarterscreen = "1/4" }

    // Recording state
    @Published var selectedRegion: CGRect = .zero
    @Published var recordingDuration: TimeInterval = 0
    @Published var frameCount: Int = 0

    // Frames
    @Published var frames: [GIFFrame] = []
    @Published var selectedFrameIndex: Int = 0
    @Published var selectedFrameRange: Range<Int>? = nil

    // Export settings
    @Published var outputFormat: OutputFormat = .gif
    @Published var gifQuality: GIFQuality = .medium  // 기본: 중간 품질 (가벼움)
    @Published var quantMethod: QuantMethod = .liq
    @Published var useDither: Bool = true
    @Published var ditherLevel: Float = 1.0
    @Published var centerFocusedDither: Bool = false  // 중심색 포커스 디더링 (꿀캠 IDC_CHK_CENTER_FOCUSED_COLOR_DITHER)
    @Published var skipQuantizeWhenQ100: Bool = true   // Q100이면 양자화 스킵 (꿀캠 IDC_CHK_SKIP_QUANTIZE_WHEN_Q_100)
    @Published var removeSimilarPixels: Bool = false   // 유사 픽셀 제거 (꿀캠 IDC_CHK_GIF_REMOVE_SIMILAR_PIXELS)
    @Published var liqSpeed: Int = 4       // libimagequant speed 1-10 (1=최고품질, 10=최고속도) (꿀캠 IDC_EDIT_GIF_QUANT_SPEED)
    @Published var liqQuality: Int = 90    // libimagequant quality 0-100 (꿀캠 IDC_EDIT_GIF_QUANT_QUALITY)
    @Published var maxWidth: Int = 640       // 기본: 640px (가벼움) 
    @Published var maxFileSizeKB: Int = 3000  // 기본: 3MB 제한
    @Published var loopCount: Int = 0      // 0=infinite
    @Published var webpQuality: Int = 85
    @Published var webpLossless: Bool = false
    @Published var mp4Quality: Int = 80
    @Published var useGifski: Bool = true  // gifski 사용 (크로스프레임 최적화)
    
    // Cursor effects (꿀캠 IDC_CHK_CAPTURE_CURSOR_*)
    @Published var cursorEffect: Bool = false
    @Published var cursorHighlight: Bool = false
    @Published var cursorHighlightColor: NSColor = .yellow.withAlphaComponent(0.3)
    @Published var cursorLeftClickColor: NSColor = .red.withAlphaComponent(0.5)
    @Published var cursorRightClickColor: NSColor = .blue.withAlphaComponent(0.5)
    
    // Direct save (꿀캠 IDC_CHK_DO_NOT_KEEP_FRAME_WHILE_DIRECT_SAVE)
    @Published var directSave: Bool = false
    @Published var directSavePath: String = ""
    @Published var directSaveQuality: Int = 80
    @Published var openEditAfterRecording: Bool = true  // 꿀캠 IDC_CHK_OPEN_EDIT_DIRECTLY_AFTER_RECORDING

    // Status
    @Published var saveProgress: Double = 0
    @Published var statusText: String = ""
    @Published var errorText: String?

    // Crop
    @Published var cropRect: CGRect = .zero
    
    // UI
    @Published var showBatch: Bool = false

    let fpsPresets = [10, 15, 20, 25, 30, 50, 60]
    static let maxFrames = 3000
    static let maxSeconds: TimeInterval = 300

    func reset() {
        mode = .home
        frames = []
        selectedFrameIndex = 0
        selectedFrameRange = nil
        recordingDuration = 0
        frameCount = 0
        saveProgress = 0
        statusText = ""
        errorText = nil
        cropRect = .zero
    }

    func enterEditor(with capturedFrames: [GIFFrame]) {
        // 메모리 보호: 예상 메모리 계산
        if let first = capturedFrames.first {
            let bytesPerFrame = first.image.width * first.image.height * 4
            let totalMB = bytesPerFrame * capturedFrames.count / 1_048_576
            if totalMB > 4096 {
                // 4GB 초과 시 자동 리사이즈
                frames = capturedFrames.map { f in
                    var out = f
                    out.image = downscale(f.image, factor: 2) ?? f.image
                    return out
                }
                statusText = "⚠️ 메모리 보호: 자동 축소됨 (\(totalMB)MB → ~\(totalMB/4)MB)"
            } else {
                frames = capturedFrames.map { f in
                    var out = f
                    if f.image.width > 2560 {
                        out.image = downscale(f.image, factor: 2) ?? f.image
                    }
                    return out
                }
            }
        } else {
            frames = capturedFrames
        }
        selectedFrameIndex = 0
        mode = .editing
    }

    private func downscale(_ img: CGImage, factor: Int) -> CGImage? {
        let nw = img.width / factor, nh = img.height / factor
        guard let ctx = CGContext(
            data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }

    var totalDuration: TimeInterval { frames.reduce(0) { $0 + $1.duration } }
    var frameSize: String { guard let f = frames.first else { return "" }; return "\(f.image.width)×\(f.image.height)" }
    var estimatedSize: String {
        guard let f = frames.first else { return "" }
        let px = f.image.width * f.image.height
        let bpf = Double(px) * Double(gifQuality.maxColors) / 256.0 * 0.4
        let total = bpf * Double(frames.count)
        return total > 1_048_576 ? String(format: "~%.1fMB", total/1_048_576) : String(format: "~%.0fKB", total/1024)
    }

    func parseFps() {
        if let v = Int(customFps), v >= 1, v <= 120 { fps = v }
    }
}

struct GIFFrame: Identifiable {
    let id = UUID()
    var image: CGImage
    var duration: TimeInterval
    var nsImage: NSImage { NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)) }
}
