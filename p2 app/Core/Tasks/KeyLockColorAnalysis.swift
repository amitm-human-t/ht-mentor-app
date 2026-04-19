import Foundation
import CoreGraphics
import AVFoundation

/// Swift port of KeyLockV2 color-analysis pipeline used by test-app:
/// 1) refine_to_yellow_edges
/// 2) find_orange_component_inside_red (non-yellow component scoring)
/// 3) compute_red_pct (HSV dual red mask)
enum KeyLockColorAnalysis {
    struct KeyResult {
        let redPct: Double
        let refinedRect: CGRect
        let contourRect: CGRect
    }

    static func analyze(
        frame: TaskInputs.VideoFrame,
        keyDetections: [String: TaskDetection],
        inDetections: [TaskDetection]
    ) -> [String: KeyResult] {
        var results: [String: KeyResult] = [:]
        CVPixelBufferLockBaseAddress(frame.pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame.pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(frame.pixelBuffer) else { return results }
        let width = CVPixelBufferGetWidth(frame.pixelBuffer)
        let height = CVPixelBufferGetHeight(frame.pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(frame.pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        for (keyName, keyDet) in keyDetections {
            guard let inRegion = inDetections.first(where: { overlap(keyDet.boundingBox, $0.boundingBox) }) else { continue }
            guard let roi = normalizedToPixelRect(inRegion.boundingBox, width: width, height: height) else { continue }

            guard let refined = refineToYellowEdges(
                ptr: ptr,
                imageWidth: width,
                imageHeight: height,
                bytesPerRow: bytesPerRow,
                roi: roi,
                yellowRatioThreshold: 0.90,
                maxGap: 2
            ) else { continue }

            guard let component = findBestNonYellowComponent(
                ptr: ptr,
                imageWidth: width,
                imageHeight: height,
                bytesPerRow: bytesPerRow,
                roi: refined
            ) else { continue }

            let redPct = computeRedPct(
                ptr: ptr,
                imageWidth: width,
                imageHeight: height,
                bytesPerRow: bytesPerRow,
                component: component
            )

            let refinedNorm = pixelToNormalizedRect(refined, width: width, height: height)
            let contourNorm = pixelToNormalizedRect(component.bbox, width: width, height: height)
            results[keyName] = KeyResult(redPct: redPct, refinedRect: refinedNorm, contourRect: contourNorm)
        }

        return results
    }

    private struct Component {
        let bbox: CGRect
        let pixels: [(Int, Int)]
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && a.maxX > b.minX && a.minY < b.maxY && a.maxY > b.minY
    }

    private static func normalizedToPixelRect(_ rect: CGRect, width: Int, height: Int) -> CGRect? {
        guard width > 0, height > 0 else { return nil }
        // Vision boxes are bottom-left origin; pixel buffer is top-left origin.
        let x = max(0, min(CGFloat(width), rect.minX * CGFloat(width)))
        let y = max(0, min(CGFloat(height), (1 - rect.maxY) * CGFloat(height)))
        let w = max(1, min(CGFloat(width) - x, rect.width * CGFloat(width)))
        let h = max(1, min(CGFloat(height) - y, rect.height * CGFloat(height)))
        let r = CGRect(x: x, y: y, width: w, height: h).integral
        guard r.width >= 2, r.height >= 2 else { return nil }
        return r
    }

    private static func pixelToNormalizedRect(_ rect: CGRect, width: Int, height: Int) -> CGRect {
        let x = rect.minX / CGFloat(width)
        let y = 1 - ((rect.minY + rect.height) / CGFloat(height))
        let w = rect.width / CGFloat(width)
        let h = rect.height / CGFloat(height)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func bgraToHSV(_ b: UInt8, _ g: UInt8, _ r: UInt8) -> (h: Int, s: Int, v: Int) {
        let rf = Double(r) / 255.0
        let gf = Double(g) / 255.0
        let bf = Double(b) / 255.0
        let maxV = max(rf, gf, bf)
        let minV = min(rf, gf, bf)
        let delta = maxV - minV

        let hueDeg: Double
        if delta == 0 {
            hueDeg = 0
        } else if maxV == rf {
            hueDeg = 60 * (((gf - bf) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxV == gf {
            hueDeg = 60 * (((bf - rf) / delta) + 2)
        } else {
            hueDeg = 60 * (((rf - gf) / delta) + 4)
        }
        let normalizedHue = hueDeg < 0 ? hueDeg + 360 : hueDeg
        let h = Int((normalizedHue / 2).rounded()) // OpenCV 0...179
        let s = Int(((maxV == 0 ? 0 : delta / maxV) * 255.0).rounded())
        let v = Int((maxV * 255.0).rounded())
        return (max(0, min(179, h)), max(0, min(255, s)), max(0, min(255, v)))
    }

    private static func isYellow(h: Int, s: Int, v: Int) -> Bool {
        (18...45).contains(h) && (15...255).contains(s) && (100...255).contains(v)
    }

    private static func isRed(h: Int, s: Int, v: Int) -> Bool {
        (((0...27).contains(h) && s >= 35 && v >= 70)
        || ((170...180).contains(h) && s >= 70 && v >= 70))
    }

    private static func morph(_ src: [UInt8], width: Int, height: Int, operation: String) -> [UInt8] {
        guard width > 2, height > 2 else { return src }
        var out = src
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                var count = 0
                for yy in (y - 1)...(y + 1) {
                    for xx in (x - 1)...(x + 1) {
                        if src[yy * width + xx] > 0 { count += 1 }
                    }
                }
                out[y * width + x] = switch operation {
                case "erode": count == 9 ? 1 : 0
                case "dilate": count > 0 ? 1 : 0
                default: src[y * width + x]
                }
            }
        }
        return out
    }

    private static func openClose(_ src: [UInt8], width: Int, height: Int) -> [UInt8] {
        let opened = morph(morph(src, width: width, height: height, operation: "erode"), width: width, height: height, operation: "dilate")
        return morph(morph(opened, width: width, height: height, operation: "dilate"), width: width, height: height, operation: "erode")
    }

    private static func longestZeroRun(_ values: [UInt8]) -> Int {
        var best = 0
        var cur = 0
        for v in values {
            if v == 0 {
                cur += 1
                best = max(best, cur)
            } else {
                cur = 0
            }
        }
        return best
    }

    private static func refineToYellowEdges(
        ptr: UnsafePointer<UInt8>,
        imageWidth: Int,
        imageHeight: Int,
        bytesPerRow: Int,
        roi: CGRect,
        yellowRatioThreshold: Double,
        maxGap: Int
    ) -> CGRect? {
        let x0 = Int(roi.minX), y0 = Int(roi.minY)
        let w = Int(roi.width), h = Int(roi.height)
        guard w > 2, h > 2 else { return nil }

        var yellow = Array(repeating: UInt8(0), count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let px = x0 + x
                let py = y0 + y
                guard px >= 0, py >= 0, px < imageWidth, py < imageHeight else { continue }
                let idx = py * bytesPerRow + px * 4
                let hsv = bgraToHSV(ptr[idx], ptr[idx + 1], ptr[idx + 2])
                yellow[y * w + x] = isYellow(h: hsv.h, s: hsv.s, v: hsv.v) ? 1 : 0
            }
        }

        yellow = openClose(yellow, width: w, height: h)
        if !yellow.contains(1) { return nil }

        var left = 0
        var right = w - 1
        var top = 0
        var bottom = h - 1

        func faceScore(_ edge: [UInt8]) -> (ok: Bool, score: Double) {
            guard !edge.isEmpty else { return (false, -1_000_000) }
            let yCount = edge.reduce(0) { $0 + Int($1) }
            let ratio = Double(yCount) / Double(edge.count)
            let gap = longestZeroRun(edge)
            return (ratio >= yellowRatioThreshold && gap <= maxGap, ratio - 0.15 * Double(gap))
        }

        for _ in 0..<200 {
            if left >= right || top >= bottom { return nil }

            let leftEdge = (top...bottom).map { yellow[$0 * w + left] }
            let rightEdge = (top...bottom).map { yellow[$0 * w + right] }
            let topEdge = (left...right).map { yellow[top * w + $0] }
            let bottomEdge = (left...right).map { yellow[bottom * w + $0] }

            let faces: [(String, (ok: Bool, score: Double))] = [
                ("left", faceScore(leftEdge)),
                ("right", faceScore(rightEdge)),
                ("top", faceScore(topEdge)),
                ("bottom", faceScore(bottomEdge))
            ]
            if faces.allSatisfy({ $0.1.ok }) { break }
            let worst = faces.min(by: { $0.1.score < $1.1.score })?.0
            switch worst {
            case "left": left += 1
            case "right": right -= 1
            case "top": top += 1
            case "bottom": bottom -= 1
            default: break
            }
        }

        if left >= right || top >= bottom { return nil }
        if Double(right - left) < Double(w) * 0.15 || Double(bottom - top) < Double(h) * 0.15 { return nil }

        return CGRect(
            x: x0 + left,
            y: y0 + top,
            width: (right - left + 1),
            height: (bottom - top + 1)
        )
    }

    private static func findBestNonYellowComponent(
        ptr: UnsafePointer<UInt8>,
        imageWidth: Int,
        imageHeight: Int,
        bytesPerRow: Int,
        roi: CGRect
    ) -> Component? {
        let x0 = Int(roi.minX), y0 = Int(roi.minY)
        let w = Int(roi.width), h = Int(roi.height)
        guard w > 2, h > 2 else { return nil }

        var nonYellow = Array(repeating: UInt8(0), count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let px = x0 + x
                let py = y0 + y
                guard px >= 0, py >= 0, px < imageWidth, py < imageHeight else { continue }
                let idx = py * bytesPerRow + px * 4
                let hsv = bgraToHSV(ptr[idx], ptr[idx + 1], ptr[idx + 2])
                nonYellow[y * w + x] = isYellow(h: hsv.h, s: hsv.s, v: hsv.v) ? 0 : 1
            }
        }

        nonYellow = openClose(nonYellow, width: w, height: h)
        if !nonYellow.contains(1) { return nil }

        var visited = Array(repeating: false, count: w * h)
        var bestScore = -Double.greatestFiniteMagnitude
        var best: Component?
        let refX = Double(w) / 2
        let refY = Double(h) / 2

        for sy in 0..<h {
            for sx in 0..<w {
                let start = sy * w + sx
                guard nonYellow[start] == 1, !visited[start] else { continue }
                var queue = [(sx, sy)]
                var qi = 0
                visited[start] = true

                var pixels: [(Int, Int)] = []
                var minX = sx, maxX = sx, minY = sy, maxY = sy
                while qi < queue.count {
                    let (x, y) = queue[qi]
                    qi += 1
                    pixels.append((x, y))
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)

                    let neighbors = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
                    for (nx, ny) in neighbors where nx >= 0 && ny >= 0 && nx < w && ny < h {
                        let ni = ny * w + nx
                        if nonYellow[ni] == 1 && !visited[ni] {
                            visited[ni] = true
                            queue.append((nx, ny))
                        }
                    }
                }

                let area = Double(pixels.count)
                if area < 12 { continue }
                let bw = maxX - minX + 1
                let bh = maxY - minY + 1
                let boxArea = Double(bw * bh)
                if bw <= 0 || bh <= 0 || boxArea < 16 { continue }
                let frac = boxArea / Double(w * h)
                if frac > 0.60 { continue }

                let aspect = Double(bw) / Double(bh)
                let minMarginInt = min(min(minX, minY), min(w - (maxX + 1), h - (maxY + 1)))
                let minMargin = Double(minMarginInt)
                let cx = Double(minX + maxX) / 2.0
                let cy = Double(minY + maxY) / 2.0
                let dist2 = (cx - refX) * (cx - refX) + (cy - refY) * (cy - refY)
                let score = (2.0 * area) + (1.5 * boxArea) + (8.0 * minMargin) - (0.03 * dist2) - (40.0 * abs(aspect - 0.8))

                if score > bestScore {
                    bestScore = score
                    best = Component(
                        bbox: CGRect(x: x0 + minX, y: y0 + minY, width: bw, height: bh),
                        pixels: pixels.map { (x0 + $0.0, y0 + $0.1) }
                    )
                }
            }
        }

        return best
    }

    private static func computeRedPct(
        ptr: UnsafePointer<UInt8>,
        imageWidth: Int,
        imageHeight: Int,
        bytesPerRow: Int,
        component: Component
    ) -> Double {
        guard !component.pixels.isEmpty else { return 0 }
        var redCount = 0
        for (px, py) in component.pixels where px >= 0 && py >= 0 && px < imageWidth && py < imageHeight {
            let idx = py * bytesPerRow + px * 4
            let hsv = bgraToHSV(ptr[idx], ptr[idx + 1], ptr[idx + 2])
            if isRed(h: hsv.h, s: hsv.s, v: hsv.v) {
                redCount += 1
            }
        }
        return (100.0 * Double(redCount)) / Double(component.pixels.count)
    }
}
