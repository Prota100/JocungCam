import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recorder: ScreenRecorder
    @State private var isDragOver = false
    @State private var showAdvanced = false
    @State private var showPermissionAlert = false
    @State private var isHoverCapture = false

    var body: some View {
        VStack(spacing: 0) {
            // Title bar area
            HStack {
                HStack(spacing: 6) {
                    Text("🍯").font(.system(size: 18))
                    Text("JocungCam").font(.system(size: 15, weight: .bold, design: .rounded))
                }
                Spacer()
                HCTag("v1.0-beta", color: HCTheme.textTertiary)
            }
            .padding(.horizontal, HCTheme.padLg).padding(.top, 12).padding(.bottom, 4)

            ScrollView {
                VStack(spacing: HCTheme.pad) {
                    // Hero capture button + drop zone
                    captureZone

                    // Settings cards
                    HCCard {
                        VStack(spacing: 10) {
                            captureSettings
                            Divider().opacity(0.3)
                            outputSettings
                            Divider().opacity(0.3)
                            toggleSettings
                        }
                    }

                    // Advanced
                    DisclosureGroup(isExpanded: $showAdvanced) {
                        HCCard {
                            advancedSettings
                        }.padding(.top, 4)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape").font(.system(size: 10))
                            Text("고급 설정").font(HCTheme.caption)
                        }.foregroundColor(HCTheme.textTertiary)
                    }
                }
                .padding(.horizontal, HCTheme.padLg).padding(.bottom, HCTheme.pad)
            }

            // Error
            if let err = appState.errorText {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                    Text(err).font(HCTheme.caption)
                }
                .foregroundColor(HCTheme.danger)
                .padding(.horizontal, HCTheme.padLg).padding(.vertical, 4)
            }

            // Footer
            Divider().opacity(0.3)
            HStack(spacing: 16) {
                Label("⌘⇧G 캡처", systemImage: "keyboard").font(HCTheme.micro)
                Label("드래그&드롭", systemImage: "square.and.arrow.down.on.square").font(HCTheme.micro)
            }
            .foregroundColor(HCTheme.textTertiary)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 400, minHeight: showAdvanced ? 560 : 440)
        .alert("화면 녹화 권한", isPresented: $showPermissionAlert) {
            Button("시스템 설정 열기") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
            Button("확인", role: .cancel) {}
        } message: {
            Text("시스템 설정 → 개인정보 보호 및 보안 → 화면 녹화에서 JocungCam을 활성화하세요.")
        }
        .overlay {
            if showCountdown {
                ZStack {
                    Color.black.opacity(0.85)
                    VStack(spacing: 8) {
                        Text("\(countdownValue)")
                            .font(.system(size: 100, weight: .bold, design: .rounded))
                            .foregroundColor(HCTheme.accent)
                        Text("녹화 시작 준비").font(HCTheme.caption).foregroundColor(HCTheme.textTertiary)
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
    }

    // MARK: - Capture Zone
    var captureZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isDragOver ? HCTheme.accent.opacity(0.08) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isDragOver ? HCTheme.accent : HCTheme.border,
                            style: StrokeStyle(lineWidth: isDragOver ? 2 : 1, dash: isDragOver ? [] : [8, 5])
                        )
                )

            VStack(spacing: 10) {
                // Big capture button
                Button(action: startCapture) {
                    HStack(spacing: 8) {
                        Circle().fill(HCTheme.danger).frame(width: 10, height: 10)
                        Text("캡처 시작").font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isHoverCapture ? HCTheme.surfaceHover : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(HCTheme.border))
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHoverCapture = $0 }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 9))
                    Text("QuickTime(MOV) · MP4 · GIF · 이미지 드롭").font(HCTheme.micro)
                }.foregroundColor(HCTheme.textTertiary)
            }
        }
        .frame(height: 100)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { handleDrop($0) }
    }

    // MARK: - Capture Settings
    var captureSettings: some View {
        HCSection("캡처 모드") {
            HStack(spacing: 4) {
                ForEach(AppState.CaptureMode.allCases, id: \.rawValue) { m in
                    HCPillButton(m.rawValue, icon: modeIcon(m), isActive: appState.captureMode == m) {
                        appState.captureMode = m
                    }
                }
            }

            HStack(spacing: 4) {
                Text("FPS").font(HCTheme.micro).foregroundColor(HCTheme.textTertiary).frame(width: 24)
                ForEach([10, 15, 20, 25, 30, 60], id: \.self) { f in
                    HCPillButton("\(f)", isActive: appState.fps == f) {
                        appState.fps = f; appState.customFps = "\(f)"
                    }
                }
                TextField("", text: $appState.customFps)
                    .frame(width: 28).font(HCTheme.microMono)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { appState.parseFps() }
            }
        }
    }

    func modeIcon(_ m: AppState.CaptureMode) -> String {
        switch m {
        case .region: return "rectangle.dashed"
        case .fullscreen: return "rectangle.inset.filled"
        case .halfscreen: return "rectangle.split.2x1"
        case .quarterscreen: return "square.split.2x2"
        }
    }

    // MARK: - Output Settings
    var outputSettings: some View {
        HCSection("출력") {
            HStack(spacing: 4) {
                ForEach(OutputFormat.allCases) { fmt in
                    HCPillButton(fmt.rawValue, isActive: appState.outputFormat == fmt) {
                        appState.outputFormat = fmt
                    }
                }
                Spacer()
                if appState.outputFormat == .gif {
                    ForEach(GIFQuality.allCases) { q in
                        HCPillButton(q.rawValue, isActive: appState.gifQuality == q) {
                            appState.gifQuality = q
                        }
                    }
                }
            }
        }
    }

    // MARK: - Toggles
    var toggleSettings: some View {
        HStack(spacing: 14) {
            Toggle("커서", isOn: $appState.cursorCapture).toggleStyle(.checkbox).font(HCTheme.caption)
            Toggle("동일프레임 스킵", isOn: $appState.skipSameFrames).toggleStyle(.checkbox).font(HCTheme.caption)
            Toggle("디더링", isOn: $appState.useDither).toggleStyle(.checkbox).font(HCTheme.caption)
            Spacer()
        }
    }

    // MARK: - Advanced
    var advancedSettings: some View {
        VStack(spacing: 8) {
            HStack {
                Text("카운트다운").font(HCTheme.caption).foregroundColor(HCTheme.textSecondary)
                Picker("", selection: $appState.countdown) {
                    Text("없음").tag(0); Text("3초").tag(3); Text("5초").tag(5)
                }.frame(width: 80).controlSize(.mini)
                Spacer()
            }
            settingRow("최대 녹화", "\(appState.maxRecordSeconds)", suffix: "초") { appState.maxRecordSeconds = Int($0) ?? 60 }
            settingRow("최대 너비", "\(appState.maxWidth)", suffix: "px (0=자동)") { appState.maxWidth = Int($0) ?? 0 }
            settingRow("파일 제한", "\(appState.maxFileSizeKB)", suffix: "KB (0=무제한)") { appState.maxFileSizeKB = Int($0) ?? 0 }

            if appState.outputFormat == .gif {
                Divider().opacity(0.3)
                HStack {
                    Text("양자화").font(HCTheme.caption).foregroundColor(HCTheme.textSecondary)
                    Picker("", selection: $appState.quantMethod) {
                        ForEach(QuantMethod.allCases) { q in Text(q.rawValue).tag(q) }
                    }.frame(width: 100).controlSize(.mini)
                    Spacer()
                }
                HStack {
                    Text("디더 레벨").font(HCTheme.caption).foregroundColor(HCTheme.textSecondary)
                    Slider(value: $appState.ditherLevel, in: 0...1).frame(width: 100)
                    Text(String(format: "%.1f", appState.ditherLevel)).font(HCTheme.microMono)
                    Spacer()
                }
                HStack {
                    Text("LIQ 속도").font(HCTheme.caption).foregroundColor(HCTheme.textSecondary)
                    Slider(value: Binding(get: { Double(appState.liqSpeed) }, set: { appState.liqSpeed = Int($0) }), in: 1...10, step: 1).frame(width: 100)
                    Text("\(appState.liqSpeed)").font(HCTheme.microMono).frame(width: 16)
                    Spacer()
                }
                HStack {
                    Text("LIQ 품질").font(HCTheme.caption).foregroundColor(HCTheme.textSecondary)
                    Slider(value: Binding(get: { Double(appState.liqQuality) }, set: { appState.liqQuality = Int($0) }), in: 1...100, step: 1).frame(width: 100)
                    Text("\(appState.liqQuality)").font(HCTheme.microMono).frame(width: 24)
                    Spacer()
                }
            }

            Divider().opacity(0.3)
            VStack(alignment: .leading, spacing: 4) {
                Toggle("커서 이펙트 (하이라이트 + 클릭)", isOn: $appState.cursorEffect).font(HCTheme.caption)
                Toggle("gifski 사용 (크로스프레임 최적화)", isOn: $appState.useGifski).font(HCTheme.caption)
                Toggle("다이렉트 세이브 (편집 스킵)", isOn: $appState.directSave).font(HCTheme.caption)
                Toggle("영역 기억", isOn: $appState.rememberRegion).font(HCTheme.caption)
                Toggle("유사 픽셀 제거", isOn: $appState.removeSimilarPixels).font(HCTheme.caption)
            }
        }
    }

    func settingRow(_ label: String, _ value: String, suffix: String, onCommit: @escaping (String) -> Void) -> some View {
        HStack {
            Text(label).font(HCTheme.caption).foregroundColor(HCTheme.textSecondary)
            let binding = Binding(get: { value }, set: { onCommit($0) })
            TextField("", text: binding).frame(width: 50).textFieldStyle(.roundedBorder).font(HCTheme.microMono)
            Text(suffix).font(HCTheme.micro).foregroundColor(HCTheme.textTertiary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func startCapture() {
        appState.errorText = nil
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            appState.errorText = "화면 녹화 권한이 필요합니다"
            showPermissionAlert = true
            return
        }
        if appState.captureMode != .region, let rect = recorder.getRegionForMode(appState.captureMode) {
            beginRecording(region: rect); return
        }
        if appState.rememberRegion, appState.lastRegion != .zero {
            beginRecording(region: appState.lastRegion); return
        }
        appState.mode = .selecting
        let selector = RegionSelectorWindow()
        selector.onSelected = { rect in beginRecording(region: rect) }
        selector.onCancelled = { appState.mode = .home }
        selector.makeKeyAndOrderFront(nil)
    }

    @State private var countdownValue: Int = 0
    @State private var showCountdown: Bool = false

    private func beginRecording(region: CGRect) {
        if appState.countdown > 0 {
            countdownValue = appState.countdown; showCountdown = true
            countdownTick(region: region)
        } else { doRecord(region: region) }
    }

    private func countdownTick(region: CGRect) {
        if countdownValue <= 0 { showCountdown = false; doRecord(region: region); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { countdownValue -= 1; countdownTick(region: region) }
    }

    private func doRecord(region: CGRect) {
        Task {
            do { try await recorder.startRecording(region: region, appState: appState) }
            catch { appState.errorText = error.localizedDescription; appState.mode = .home }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                let ext = url.pathExtension.lowercased()
                if ["gif", "webp", "apng", "png"].contains(ext) {
                    if let frames = FrameOps.importGIF(from: url) { appState.enterEditor(with: frames) }
                    else { appState.errorText = "파일을 열 수 없습니다" }
                } else if ["mp4", "mov", "m4v", "webm", "avi"].contains(ext) {
                    appState.statusText = "임포트 중..."
                    if let frames = await FrameOps.importVideo(from: url, fps: Double(appState.fps)) { appState.enterEditor(with: frames) }
                    else { appState.errorText = "영상을 열 수 없습니다" }
                } else { appState.errorText = "지원하지 않는 형식" }
            }
        }
        return true
    }
}
