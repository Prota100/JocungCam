import Foundation
import CoreGraphics
import ImageIO
import AVFoundation

enum FrameOps {
    // MARK: - Delete
    static func deleteFrame(at i: Int, from frames: inout [GIFFrame]) {
        guard frames.count > 1, frames.indices.contains(i) else { return }
        frames.remove(at: i)
    }

    static func deleteRange(_ range: Range<Int>, from frames: inout [GIFFrame]) {
        let safe = max(0, range.lowerBound)..<min(frames.count, range.upperBound)
        guard frames.count - safe.count >= 1 else { return }
        frames.removeSubrange(safe)
    }

    // MARK: - Speed
    static func adjustSpeed(_ multiplier: Double, frames: inout [GIFFrame]) {
        for i in frames.indices { frames[i].duration = max(0.01, frames[i].duration / multiplier) }
    }

    static func setAllDuration(_ dur: TimeInterval, frames: inout [GIFFrame]) {
        for i in frames.indices { frames[i].duration = max(0.01, dur) }
    }

    // MARK: - Order
    static func reverse(_ frames: inout [GIFFrame]) { frames.reverse() }

    static func yoyo(_ frames: inout [GIFFrame]) {
        let reversed = frames.reversed().dropFirst() // skip last (=first of reversed) to avoid dupe
        frames.append(contentsOf: reversed)
    }

    // MARK: - Reduce
    static func removeEvenFrames(_ frames: inout [GIFFrame]) {
        frames = frames.enumerated().compactMap { $0.offset % 2 == 0 ? $0.element : nil }
    }

    static func removeOddFrames(_ frames: inout [GIFFrame]) {
        frames = frames.enumerated().compactMap { $0.offset % 2 != 0 ? $0.element : nil }
    }

    static func removeEveryNth(_ n: Int, frames: inout [GIFFrame]) {
        guard n > 1 else { return }
        frames = frames.enumerated().compactMap { ($0.offset + 1) % n != 0 ? $0.element : nil }
    }

    static func removeSimilar(threshold: Int = 5, frames: inout [GIFFrame]) {
        guard frames.count > 2 else { return }
        var kept: [GIFFrame] = [frames[0]]
        for i in 1..<frames.count {
            if !framesAreSimilar(frames[i-1].image, frames[i].image, threshold: threshold) {
                kept.append(frames[i])
            } else {
                // Add duration to previous
                kept[kept.count - 1].duration += frames[i].duration
            }
        }
        frames = kept
    }

    private static func framesAreSimilar(_ a: CGImage, _ b: CGImage, threshold: Int) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        guard let da = a.dataProvider?.data, let db = b.dataProvider?.data else { return false }
        guard let pa = CFDataGetBytePtr(da), let pb = CFDataGetBytePtr(db) else { return false }
        let len = min(CFDataGetLength(da), CFDataGetLength(db))
        let step = max(1, len / 1000) // sample ~1000 points
        var diff = 0
        var samples = 0
        var offset = 0
        while offset < len {
            let d = abs(Int(pa[offset]) - Int(pb[offset]))
            diff += d
            samples += 1
            offset += step
        }
        return samples > 0 && (diff / samples) < threshold
    }

    // MARK: - Crop
    static func crop(_ rect: CGRect, frames: inout [GIFFrame]) {
        guard rect.width > 0, rect.height > 0 else { return }
        frames = frames.compactMap { f in
            guard let img = f.image.cropping(to: rect) else { return nil }
            return GIFFrame(image: img, duration: f.duration)
        }
    }

    // MARK: - Resize
    static func resize(maxWidth: Int, frames: inout [GIFFrame]) {
        guard maxWidth > 0, let first = frames.first, first.image.width > maxWidth else { return }
        let scale = CGFloat(maxWidth) / CGFloat(first.image.width)
        frames = frames.compactMap { f in
            let nw = Int(CGFloat(f.image.width) * scale)
            let nh = Int(CGFloat(f.image.height) * scale)
            guard let ctx = CGContext(
                data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return f }
            ctx.interpolationQuality = .high
            ctx.draw(f.image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
            guard let img = ctx.makeImage() else { return f }
            return GIFFrame(image: img, duration: f.duration)
        }
    }

    // MARK: - Import GIF
    static func importGIF(from url: URL) -> [GIFFrame]? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let n = CGImageSourceGetCount(src)
        guard n > 0 else { return nil }
        var out: [GIFFrame] = []
        for i in 0..<n {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            var dur: TimeInterval = 0.1
            if let p = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [String: Any],
               let g = p[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                dur = (g[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double) ??
                      (g[kCGImagePropertyGIFDelayTime as String] as? Double) ?? 0.1
                if dur < 0.01 { dur = 0.1 }
            }
            out.append(GIFFrame(image: img, duration: dur))
        }
        return out.isEmpty ? nil : out
    }

    // MARK: - Import Video
    static func importVideo(from url: URL, fps: Double = 15) async -> [GIFFrame]? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let totalSec = CMTimeGetSeconds(duration)
        
        // 30초 넘으면 fps 줄여서 메모리 보호
        let maxFrames = 900 // 30초 * 30fps 정도
        let interval = max(1.0 / fps, totalSec / Double(maxFrames))
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = CMTime.zero
        generator.requestedTimeToleranceAfter = CMTime.zero
        generator.appliesPreferredTrackTransform = true
        
        // 메모리 최적화
        generator.maximumSize = CGSize(width: 1920, height: 1080) // 풀HD 제한
        
        var frames: [GIFFrame] = []
        var times: [CMTime] = []
        
        // 시간 배열 미리 생성
        var t: Double = 0
        while t < totalSec && times.count < maxFrames {
            times.append(CMTime(seconds: t, preferredTimescale: 600))
            t += interval
        }
        
        // 배치로 처리 (메모리 관리)
        for cmTime in times {
            if let (img, _) = try? await generator.image(at: cmTime) {
                autoreleasepool {
                    frames.append(GIFFrame(image: img, duration: interval))
                }
            }
            // 100프레임마다 잠시 멈춰서 메모리 정리
            if frames.count % 100 == 0 {
                try? await Task.sleep(nanoseconds: 10_000_000) // 0.01초
            }
        }
        
        return frames.isEmpty ? nil : frames
    }
}
