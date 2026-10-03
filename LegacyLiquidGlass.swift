import Foundation
import UIKit
import SwiftUI
import Metal
import MetalKit
import QuartzCore
import ObjectiveC

// MARK: - 00. Public Namespace

public enum LegacyLiquidGlass {
    public static let version = "2.0.0-final"
    public static let minimumOS = 13

    public enum Backend: Equatable {
        case automatic
        case legacy
        case system
    }

    public enum Quality: Int, CaseIterable, Sendable {
        case low = 0
        case medium = 1
        case high = 2
        case ultra = 3

        fileprivate var scale: CGFloat {
            switch self {
            case .low: return 0.30
            case .medium: return 0.42
            case .high: return 0.58
            case .ultra: return 0.72
            }
        }

        fileprivate var captureFPS: Int {
            switch self {
            case .low: return 15
            case .medium: return 24
            case .high: return 30
            case .ultra: return 45
            }
        }
    }

    public enum Style {
        case regular
        case clear
        case prominent
        case tinted(UIColor)
        case custom(tint: UIColor, opacity: CGFloat, blur: CGFloat)
    }

    public struct Configuration {
        public var backend: Backend = .automatic
        public var quality: Quality = .high
        public var style: Style = .regular
        public var cornerRadius: CGFloat = 24
        public var opacity: CGFloat = 1
        public var blurRadius: CGFloat = 18
        public var tintStrength: CGFloat = 0.12
        public var specularStrength: CGFloat = 0.28
        public var edgeLightStrength: CGFloat = 0.34
        public var refractionStrength: CGFloat = 0.016
        public var refractionScale: CGFloat = 0.55
        public var highlightWidth: CGFloat = 0.18
        public var rimWidth: CGFloat = 0.075
        public var shadowOpacity: Float = 0.16
        public var shadowRadius: CGFloat = 20
        public var shadowOffset = CGSize(width: 0, height: 10)
        public var interactive = true
        public var morphing = true
        public var animated = true
        public var liveCapture = true
        public var captureScale: CGFloat = 0.58
        public var maxCapturePixels: Int = 1_000_000
        public var preferredFrameRate: Int = 60
        public var useNativeUIKitOn26 = true
        public var useNativeSwiftUIOn26 = true
        public var reduceEffectsForBattery = true
        public var cacheStaticBackdrops = true
        public var enableDiagnostics = false

        public init() {}
    }

    public static var configuration = Configuration()

    public static var effectiveBackend: Backend {
        switch configuration.backend {
        case .automatic:
            if #available(iOS 26.0, *), configuration.useNativeUIKitOn26 {
                return .system
            }
            return .legacy
        default:
            return configuration.backend
        }
    }

    public static func start() {
        LLGlassBootstrap.start()
    }

    public static func stop() {
        LLGlassBootstrap.stop()
    }
}

// MARK: - 01. Environment / Accessibility

public final class LLGlassEnvironment {
    public static let shared = LLGlassEnvironment()

    public private(set) var reduceMotion = UIAccessibility.isReduceMotionEnabled
    public private(set) var reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
    public private(set) var darkerSystemColors = UIAccessibility.darkerSystemColorsStatus
    public private(set) var boldText = UIAccessibility.isBoldTextEnabled

    private var observers: [NSObjectProtocol] = []

    private init() {
        let names: [Notification.Name] = [
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            UIAccessibility.boldTextStatusDidChangeNotification
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: .LLGlassThemeDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    public func refresh() {
        reduceMotion = UIAccessibility.isReduceMotionEnabled
        reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        darkerSystemColors = UIAccessibility.darkerSystemColorsStatus
        boldText = UIAccessibility.isBoldTextEnabled
        NotificationCenter.default.post(name: .LLGlassEnvironmentDidChange, object: self)
    }
}

public extension Notification.Name {
    static let LLGlassEnvironmentDidChange = Notification.Name("LegacyLiquidGlass.EnvironmentDidChange")
    static let LLGlassThemeDidChange = Notification.Name("LegacyLiquidGlass.ThemeDidChange")
    static let LLGlassPerformanceDidChange = Notification.Name("LegacyLiquidGlass.PerformanceDidChange")
}

// MARK: - 02. Material Model

public struct LLGlassMaterial {
    public var tint: UIColor?
    public var opacity: CGFloat
    public var blurRadius: CGFloat
    public var refraction: CGFloat
    public var specular: CGFloat
    public var edgeLight: CGFloat
    public var darkness: CGFloat
    public var saturation: CGFloat
    public var contrast: CGFloat
    public var scale: CGFloat

    public init(
        tint: UIColor? = nil,
        opacity: CGFloat = 1,
        blurRadius: CGFloat = 18,
        refraction: CGFloat = 0.016,
        specular: CGFloat = 0.28,
        edgeLight: CGFloat = 0.34,
        darkness: CGFloat = 0.03,
        saturation: CGFloat = 1.05,
        contrast: CGFloat = 1.025,
        scale: CGFloat = 0.58
    ) {
        self.tint = tint
        self.opacity = opacity
        self.blurRadius = blurRadius
        self.refraction = refraction
        self.specular = specular
        self.edgeLight = edgeLight
        self.darkness = darkness
        self.saturation = saturation
        self.contrast = contrast
        self.scale = scale
    }

    public static var regular: LLGlassMaterial {
        LLGlassMaterial()
    }

    public static var clear: LLGlassMaterial {
        LLGlassMaterial(opacity: 0.90, blurRadius: 10, refraction: 0.010, specular: 0.20, edgeLight: 0.26, darkness: 0.02, saturation: 1.0, contrast: 1.01, scale: 0.72)
    }

    public static var prominent: LLGlassMaterial {
        LLGlassMaterial(opacity: 1.0, blurRadius: 24, refraction: 0.020, specular: 0.34, edgeLight: 0.40, darkness: 0.06, saturation: 1.08, contrast: 1.04, scale: 0.54)
    }

    public func tinted(_ color: UIColor) -> LLGlassMaterial {
        var copy = self
        copy.tint = color
        return copy
    }

    public func adjusted(quality: LegacyLiquidGlass.Quality, reduceTransparency: Bool, reduceMotion: Bool) -> LLGlassMaterial {
        var copy = self
        let multiplier: CGFloat
        switch quality {
        case .low: multiplier = 0.55
        case .medium: multiplier = 0.72
        case .high: multiplier = 1.0
        case .ultra: multiplier = 1.16
        }
        copy.blurRadius *= multiplier
        copy.refraction *= multiplier
        copy.specular *= multiplier
        copy.edgeLight *= multiplier
        copy.scale = quality.scale
        if reduceTransparency {
            copy.opacity = min(1, copy.opacity + 0.16)
            copy.blurRadius *= 0.60
            copy.refraction = 0
        }
        if reduceMotion {
            copy.refraction *= 0.45
        }
        return copy
    }
}

public enum LLGlassMaterialResolver {
    public static func resolve(_ configuration: LegacyLiquidGlass.Configuration, environment: LLGlassEnvironment = .shared) -> LLGlassMaterial {
        let base: LLGlassMaterial
        switch configuration.style {
        case .regular:
            base = .regular
        case .clear:
            base = .clear
        case .prominent:
            base = .prominent
        case .tinted(let color):
            base = .regular.tinted(color)
        case let .custom(tint, opacity, blur):
            base = LLGlassMaterial(tint: tint, opacity: opacity, blurRadius: blur)
        }
        let scale = configuration.captureScale > 0 ? configuration.captureScale : configuration.quality.scale
        var material = base
        material.opacity *= configuration.opacity
        material.refraction = configuration.refractionStrength
        material.specular = configuration.specularStrength
        material.edgeLight = configuration.edgeLightStrength
        material.scale = scale
        return material.adjusted(quality: configuration.quality, reduceTransparency: environment.reduceTransparency, reduceMotion: environment.reduceMotion)
    }
}

// MARK: - 03. Runtime / Device Performance

public final class LLGlassPerformanceGovernor {
    public static let shared = LLGlassPerformanceGovernor()

    public private(set) var currentQuality: LegacyLiquidGlass.Quality
    public private(set) var measuredFPS: Double = 60
    public private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    public private(set) var activeGlassCount: Int = 0

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var sampleAccumulator: CFTimeInterval = 0
    private var frameCount = 0
    private let lock = NSLock()
    private var started = false

    private init() {
        currentQuality = LegacyLiquidGlass.configuration.quality
        NotificationCenter.default.addObserver(self, selector: #selector(thermalDidChange), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }

    deinit {
        displayLink?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    public func start() {
        guard !started else { return }
        started = true
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFramesPerSecond = min(max(LegacyLiquidGlass.configuration.preferredFrameRate, 30), 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
        started = false
    }

    public func registerGlass() {
        lock.lock(); activeGlassCount += 1; lock.unlock()
    }

    public func unregisterGlass() {
        lock.lock(); activeGlassCount = max(0, activeGlassCount - 1); lock.unlock()
    }

    public func chooseQuality() -> LegacyLiquidGlass.Quality {
        guard LegacyLiquidGlass.configuration.reduceEffectsForBattery else { return LegacyLiquidGlass.configuration.quality }
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .critical || thermal == .serious || measuredFPS < 38 {
            return .medium
        }
        if activeGlassCount > 10 || measuredFPS < 50 {
            return .high
        }
        return LegacyLiquidGlass.configuration.quality
    }

    @objc private func tick(_ link: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }
        let delta = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        guard delta > 0.0001 else { return }
        frameCount += 1
        sampleAccumulator += delta
        if sampleAccumulator >= 1.0 {
            measuredFPS = Double(frameCount) / sampleAccumulator
            frameCount = 0
            sampleAccumulator = 0
            let next = chooseQuality()
            if next != currentQuality {
                currentQuality = next
                NotificationCenter.default.post(name: .LLGlassPerformanceDidChange, object: self)
            }
        }
    }

    @objc private func thermalDidChange() {
        thermalState = ProcessInfo.processInfo.thermalState
        NotificationCenter.default.post(name: .LLGlassPerformanceDidChange, object: self)
    }
}

// MARK: - 04. Color / Geometry Utilities

public enum LLGlassColorMath {
    public static func components(_ color: UIColor) -> SIMD4<Float> {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            var white: CGFloat = 0
            color.getWhite(&white, alpha: &a)
            return SIMD4(Float(white), Float(white), Float(white), Float(a))
        }
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }

    public static func appearanceTint() -> UIColor {
        if #available(iOS 13.0, *) {
            return UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.10) : UIColor(white: 1, alpha: 0.20)
            }
        }
        return UIColor(white: 1, alpha: 0.18)
    }

    public static func blend(_ a: UIColor, _ b: UIColor, amount: CGFloat) -> UIColor {
        let ca = components(a)
        let cb = components(b)
        let t = max(0, min(1, amount))
        return UIColor(
            red: CGFloat(ca.x + (cb.x - ca.x) * Float(t)),
            green: CGFloat(ca.y + (cb.y - ca.y) * Float(t)),
            blue: CGFloat(ca.z + (cb.z - ca.z) * Float(t)),
            alpha: CGFloat(ca.w + (cb.w - ca.w) * Float(t))
        )
    }
}

public enum LLGlassGeometry {
    public static func roundedPath(bounds: CGRect, radius: CGFloat) -> UIBezierPath {
        UIBezierPath(roundedRect: bounds, cornerRadius: min(max(radius, 0), min(bounds.width, bounds.height) * 0.5))
    }

    public static func insetRadius(_ radius: CGFloat, inset: CGFloat) -> CGFloat {
        max(0, radius - inset)
    }
}

// MARK: - 05. Backdrop Capture

public final class LLBackdropSnapshot: NSObject {
    public let image: CGImage
    public let size: CGSize
    public let timestamp: CFTimeInterval

    public init(image: CGImage, size: CGSize, timestamp: CFTimeInterval = CACurrentMediaTime()) {
        self.image = image
        self.size = size
        self.timestamp = timestamp
    }
}

public final class LLBackdropCapture {
    public weak var sourceView: UIView?
    public weak var exclusionView: UIView?
    public var captureScale: CGFloat = 0.58
    public var maxPixels: Int = 1_000_000
    public var live = true

    private(set) public var latest: LLBackdropSnapshot?
    private var lastCaptureTime: CFTimeInterval = 0
    private var minimumInterval: CFTimeInterval = 1.0 / 30.0
    private var rendering = false

    public init(sourceView: UIView? = nil) {
        self.sourceView = sourceView
    }

    public func invalidate() {
        latest = nil
    }

    public func captureIfNeeded(force: Bool = false) -> LLBackdropSnapshot? {
        guard let source = sourceView, !source.bounds.isEmpty else { return latest }
        let now = CACurrentMediaTime()
        if !force && (!live || now - lastCaptureTime < minimumInterval), let latest {
            return latest
        }
        if rendering { return latest }
        rendering = true
        defer { rendering = false }

        let bounds = source.bounds
        let scale = outputScale(for: bounds.size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        let image = renderer.image { context in
            let target = exclusionView
            let wasHidden = target?.isHidden ?? false
            target?.isHidden = true
            source.layer.render(in: context.cgContext)
            target?.isHidden = wasHidden
        }
        if let cg = image.cgImage {
            let result = LLBackdropSnapshot(image: cg, size: image.size)
            latest = result
            lastCaptureTime = now
            return result
        }
        return latest
    }

    public func captureRegion(around rect: CGRect, margin: CGFloat = 48) -> LLBackdropSnapshot? {
        guard let source = sourceView else { return nil }
        let expanded = rect.insetBy(dx: -margin, dy: -margin).intersection(source.bounds)
        guard !expanded.isEmpty else { return nil }
        let scale = outputScale(for: expanded.size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: expanded.size, format: format)
        let image = renderer.image { context in
            let target = exclusionView
            let wasHidden = target?.isHidden ?? false
            target?.isHidden = true
            context.cgContext.translateBy(x: -expanded.minX, y: -expanded.minY)
            source.layer.render(in: context.cgContext)
            target?.isHidden = wasHidden
        }
        return image.cgImage.map { LLBackdropSnapshot(image: $0, size: image.size) }
    }

    private func outputScale(for size: CGSize) -> CGFloat {
        let requested = max(0.25, min(1.0, captureScale))
        let pixels = max(1, Int(size.width * size.height * requested * requested))
        if pixels <= maxPixels { return requested }
        let factor = sqrt(CGFloat(maxPixels) / CGFloat(max(1, Int(size.width * size.height))))
        return max(0.25, min(requested, factor))
    }
}

// MARK: - 06. Metal Shader / Renderer

private let llGlassMetalSource = """
#include <metal_stdlib>
using namespace metal;

struct LLVertex {
    float2 position;
    float2 uv;
};

struct LLUniforms {
    float2 size;
    float2 pointer;
    float cornerRadius;
    float refraction;
    float specular;
    float edgeLight;
    float tintStrength;
    float opacity;
    float darkness;
    float time;
    float2 invTextureSize;
    float quality;
    float3 tint;
};

struct LLOut {
    float4 position [[position]];
    float2 uv;
};

vertex LLOut ll_vertex(const device LLVertex *vertices [[buffer(0)]], uint id [[vertex_id]]) {
    LLOut out;
    out.position = float4(vertices[id].position, 0.0, 1.0);
    out.uv = vertices[id].uv;
    return out;
}

float roundedBoxSDF(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float gauss(float x, float sigma) {
    return exp(-(x*x) / max(0.0001, 2.0*sigma*sigma));
}

float3 sampleBlur(texture2d<float, access::sample> tex, sampler s, float2 uv, float2 dir, float radius) {
    float3 sum = float3(0.0);
    float weightSum = 0.0;
    const int taps = 7;
    for (int i = -taps; i <= taps; ++i) {
        float fi = float(i);
        float w = gauss(fi, max(1.0, radius * 0.35));
        sum += tex.sample(s, uv + dir * fi) .rgb * w;
        weightSum += w;
    }
    return sum / max(weightSum, 0.0001);
}

fragment float4 ll_fragment(
    LLOut in [[stage_in]],
    texture2d<float, access::sample> source [[texture(0)]],
    constant LLUniforms &u [[buffer(1)]]) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);

    float2 centered = in.uv - 0.5;
    float2 radial = centered * 2.0;
    float edge = saturate(length(radial));
    float2 normal = normalize(centered + float2(0.0001));

    float pulse = sin(u.time * 1.7) * 0.5 + 0.5;
    float dynamicRefraction = u.refraction * (0.85 + pulse * 0.15);
    float2 warp = centered * dynamicRefraction * (0.45 + edge * 1.7);
    warp += normal * dynamicRefraction * 0.08;

    float2 uv = saturate(in.uv + warp);
    float2 texelX = float2(u.invTextureSize.x, 0.0);
    float2 texelY = float2(0.0, u.invTextureSize.y);

    float3 centerColor = source.sample(linearSampler, uv).rgb;
    float3 blurX = sampleBlur(source, linearSampler, uv, texelX, max(1.0, u.quality * 4.0));
    float3 blurY = sampleBlur(source, linearSampler, uv, texelY, max(1.0, u.quality * 4.0));
    float3 background = mix(centerColor, (blurX + blurY) * 0.5, 0.74);

    float3 l1 = source.sample(linearSampler, saturate(uv + float2(texelX.x * 10.0, 0.0))).rgb;
    float3 l2 = source.sample(linearSampler, saturate(uv - float2(texelX.x * 10.0, 0.0))).rgb;
    float3 edgeGradient = abs(l1 - l2);
    float opticalEdge = saturate(length(edgeGradient) * 1.4);

    float3 tint = u.tint;
    background = mix(background, tint, u.tintStrength);
    background = background * (1.0 - u.darkness);
    background = (background - 0.5) * 1.035 + 0.5;
    background = saturate(background);

    float centerSpec = pow(saturate(1.0 - edge), 2.7);
    float rim = pow(saturate(edge), 3.8);
    float directional = saturate(dot(normalize(float2(-0.55, -0.85)), normalize(centered + float2(0.001))));
    float spec = centerSpec * (0.34 + directional * 0.66) + opticalEdge * 0.14;
    float edgeGlow = rim * (0.40 + opticalEdge * 1.4);
    float highlight = pow(saturate(0.5 + in.uv.x * 0.5), 8.0) * 0.12;

    background += spec * u.specular;
    background += edgeGlow * u.edgeLight;
    background += highlight * u.specular;

    float2 px = float2(u.size.x * 0.5, u.size.y * 0.5);
    float radius = u.cornerRadius;
    float2 p = (in.uv - 0.5) * u.size;
    float2 b = px - radius;
    float sdf = roundedBoxSDF(p, b, radius);
    float aa = max(1.0, 1.5 * length(float2(dfdx(sdf), dfdy(sdf))));
    float mask = 1.0 - smoothstep(-aa, aa, sdf);

    float alpha = mask * u.opacity;
    return float4(background, alpha);
}
"""

public final class LLMetalGlassRenderer: NSObject, MTKViewDelegate {
    public struct Settings {
        public var cornerRadius: CGFloat = 24
        public var refraction: CGFloat = 0.016
        public var specular: CGFloat = 0.28
        public var edgeLight: CGFloat = 0.34
        public var tintStrength: CGFloat = 0.12
        public var opacity: CGFloat = 1
        public var darkness: CGFloat = 0.03
        public var tint = SIMD3<Float>(repeating: 1)
        public var quality: CGFloat = 3
        public var time: CGFloat = 0

        public init() {}
    }

    public let view: MTKView
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private var sourceTexture: MTLTexture?
    private var vertexBuffer: MTLBuffer?
    private var settings = Settings()
    private var textureSize = CGSize(width: 1, height: 1)

    public init?(frame: CGRect = .zero) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        guard let library = try? device.makeLibrary(source: llGlassMetalSource, options: nil),
              let vertex = library.makeFunction(name: "ll_vertex"),
              let fragment = library.makeFunction(name: "ll_fragment") else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let sampler = Self.makeSampler(device: device) else { return nil }

        self.device = device
        self.commandQueue = queue
        self.pipeline = pipeline
        self.sampler = sampler
        self.view = MTKView(frame: frame, device: device)
        super.init()

        self.view.delegate = self
        self.view.isPaused = true
        self.view.enableSetNeedsDisplay = false
        self.view.framebufferOnly = true
        self.view.isOpaque = false
        self.view.backgroundColor = .clear
        self.view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        self.view.colorPixelFormat = .bgra8Unorm
        self.view.contentScaleFactor = UIScreen.main.scale

        let vertices: [Float] = [
            -1, -1, 0, 1,
             1, -1, 1, 1,
            -1,  1, 0, 0,
             1,  1, 1, 0
        ]
        self.vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.stride, options: .storageModeShared)
    }

    public func update(source image: CGImage?, settings: Settings) {
        self.settings = settings
        guard let image else {
            sourceTexture = nil
            view.drawableSize = drawableSize(for: view.bounds.size)
            DispatchQueue.main.async { [weak self] in self?.view.draw() }
            return
        }
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
        ]
        sourceTexture = try? loader.newTexture(cgImage: image, options: options)
        textureSize = CGSize(width: sourceTexture?.width ?? 1, height: sourceTexture?.height ?? 1)
        view.drawableSize = drawableSize(for: view.bounds.size)
        DispatchQueue.main.async { [weak self] in self?.view.draw() }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let sourceTexture,
              let vertexBuffer,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        struct Uniforms {
            var size: SIMD2<Float>
            var pointer: SIMD2<Float>
            var cornerRadius: Float
            var refraction: Float
            var specular: Float
            var edgeLight: Float
            var tintStrength: Float
            var opacity: Float
            var darkness: Float
            var time: Float
            var invTextureSize: SIMD2<Float>
            var quality: Float
            var tint: SIMD3<Float>
        }

        let uniforms = Uniforms(
            size: SIMD2(Float(max(1, view.bounds.width)), Float(max(1, view.bounds.height))),
            pointer: SIMD2(0.5, 0.5),
            cornerRadius: Float(settings.cornerRadius),
            refraction: Float(settings.refraction),
            specular: Float(settings.specular),
            edgeLight: Float(settings.edgeLight),
            tintStrength: Float(settings.tintStrength),
            opacity: Float(settings.opacity),
            darkness: Float(settings.darkness),
            time: Float(settings.time),
            invTextureSize: SIMD2(1 / Float(max(1, textureSize.width)), 1 / Float(max(1, textureSize.height))),
            quality: Float(settings.quality),
            tint: settings.tint
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        var mutableUniforms = uniforms
        encoder.setFragmentBytes(&mutableUniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private static func makeSampler(device: MTLDevice) -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: descriptor)
    }

    private func drawableSize(for size: CGSize) -> CGSize {
        let scale = view.contentScaleFactor
        return CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
    }
}

// MARK: - 07. Native iOS 26 Bridge

@available(iOS 26.0, *)
public enum LLNativeLiquidGlass {
    public static func effect(style: LegacyLiquidGlass.Style, interactive: Bool, tint: UIColor?) -> UIGlassEffect {
        let systemStyle: UIGlassEffect.Style
        switch style {
        case .clear:
            systemStyle = .clear
        default:
            systemStyle = .regular
        }
        let effect = UIGlassEffect(style: systemStyle)
        effect.isInteractive = interactive
        if case .tinted(let color) = style {
            effect.tintColor = color
        } else if case .custom(let color, _, _) = style {
            effect.tintColor = color
        } else {
            effect.tintColor = tint
        }
        return effect
    }

    public static func container(spacing: CGFloat) -> UIGlassContainerEffect {
        let container = UIGlassContainerEffect()
        container.spacing = spacing
        return container
    }
}

// MARK: - 08. Legacy Visual Fallback

public final class LLLegacyVisualGlass: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let tintView = UIView()
    private let highlightView = UIView()
    private let rimLayer = CAShapeLayer()
    private let innerRimLayer = CAShapeLayer()

    public var material: LLGlassMaterial = .regular {
        didSet { applyMaterial() }
    }

    public var cornerRadius: CGFloat = 24 {
        didSet { setNeedsLayout() }
    }

    public var highlighted = false {
        didSet { animateInteraction() }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.masksToBounds = false
        blurView.isUserInteractionEnabled = false
        tintView.isUserInteractionEnabled = false
        highlightView.isUserInteractionEnabled = false
        highlightView.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        addSubview(blurView)
        addSubview(tintView)
        addSubview(highlightView)
        layer.addSublayer(rimLayer)
        layer.addSublayer(innerRimLayer)
        applyMaterial()
    }

    private func applyMaterial() {
        let alpha = material.opacity
        tintView.backgroundColor = (material.tint ?? LLGlassColorMath.appearanceTint()).withAlphaComponent(0.12 * alpha)
        blurView.alpha = material.opacity
        blurView.effect = UIBlurEffect(style: material.blurRadius > 20 ? .systemMaterial : .systemThinMaterial)
        rimLayer.fillColor = UIColor.clear.cgColor
        rimLayer.strokeColor = UIColor.white.withAlphaComponent(material.edgeLight).cgColor
        rimLayer.lineWidth = 1
        innerRimLayer.fillColor = UIColor.clear.cgColor
        innerRimLayer.strokeColor = UIColor.white.withAlphaComponent(material.specular * 0.45).cgColor
        innerRimLayer.lineWidth = 0.6
        setNeedsLayout()
    }

    private func animateInteraction() {
        guard !LLGlassEnvironment.shared.reduceMotion else { return }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.highlightView.alpha = self.highlighted ? 1 : 0
            self.highlightView.transform = self.highlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        tintView.frame = bounds
        highlightView.frame = bounds.insetBy(dx: 1, dy: 1)
        let path = LLGlassGeometry.roundedPath(bounds: bounds, radius: cornerRadius)
        rimLayer.path = path.cgPath
        innerRimLayer.path = LLGlassGeometry.roundedPath(bounds: bounds.insetBy(dx: 1.0, dy: 1.0), radius: LLGlassGeometry.insetRadius(cornerRadius, inset: 1.0)).cgPath
        highlightView.layer.cornerRadius = cornerRadius
        highlightView.layer.masksToBounds = true
        highlightView.alpha = highlighted ? 1 : 0
    }
}

// MARK: - 09. Interaction / Motion

public final class LLGlassInteractionDriver {
    public weak var view: UIView?
    public var enabled = true
    public var pressScale: CGFloat = 0.965
    public var highlight = true

    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    private lazy var longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
    private var installed = false

    public init(view: UIView) {
        self.view = view
    }

    public func install() {
        guard !installed, let view else { return }
        installed = true
        tap.cancelsTouchesInView = false
        longPress.minimumPressDuration = 0.01
        longPress.cancelsTouchesInView = false
        view.addGestureRecognizer(longPress)
        view.addGestureRecognizer(tap)
    }

    public func uninstall() {
        guard installed, let view else { return }
        view.removeGestureRecognizer(longPress)
        view.removeGestureRecognizer(tap)
        installed = false
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard enabled, recognizer.state == .ended else { return }
        pulse()
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard enabled, let view else { return }
        switch recognizer.state {
        case .began, .changed:
            setPressed(true, view: view)
        default:
            setPressed(false, view: view)
        }
    }

    private func setPressed(_ value: Bool, view: UIView) {
        guard !LLGlassEnvironment.shared.reduceMotion else { return }
        let apply = {
            view.transform = value ? CGAffineTransform(scaleX: self.pressScale, y: self.pressScale) : .identity
            if let glass = view as? LLGlassView { glass.isHighlighted = value }
        }
        UIView.animate(withDuration: value ? 0.11 : 0.28, delay: 0, usingSpringWithDamping: value ? 1 : 0.72, initialSpringVelocity: 0.6, options: [.beginFromCurrentState, .allowUserInteraction], animations: apply)
    }

    private func pulse() {
        guard let view else { return }
        guard !LLGlassEnvironment.shared.reduceMotion else { return }
        UIView.animate(withDuration: 0.10, animations: { view.transform = CGAffineTransform(scaleX: 0.985, y: 0.985) }) { _ in
            UIView.animate(withDuration: 0.30, delay: 0, usingSpringWithDamping: 0.60, initialSpringVelocity: 0.4, options: [.beginFromCurrentState], animations: { view.transform = .identity })
        }
    }
}

// MARK: - 10. Core Glass View

public final class LLGlassView: UIView {
    public var configuration: LegacyLiquidGlass.Configuration {
        didSet { rebuild() }
    }

    public var isHighlighted = false {
        didSet { updateHighlight(animated: true) }
    }

    public var glassContentView: UIView { contentView }

    private let contentView = UIView()
    private let systemEffectView = UIVisualEffectView()
    private let legacyRenderer = LLLegacyVisualGlass()
    private let metalContainer = UIView()
    private let highlightOverlay = UIView()
    private let shadowView = UIView()
    private let backdrop = LLBackdropCapture()
    private var metalRenderer: LLMetalGlassRenderer?
    private var performanceObservers: [NSObjectProtocol] = []
    private var displayLink: CADisplayLink?
    private var interactionDriver: LLGlassInteractionDriver?
    private var capturePending = false
    private var time: CGFloat = 0
    private var lastFrame = CACurrentMediaTime()
    private var lastCaptureRequest = 0.0
    private var lastLayoutBounds = CGRect.zero
    private var hierarchyObserver: NSObjectProtocol?
    private var didRegisterPerformance = false

    public override init(frame: CGRect) {
        configuration = LegacyLiquidGlass.configuration
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        configuration = LegacyLiquidGlass.configuration
        super.init(coder: coder)
        setup()
    }

    public convenience init(configuration: LegacyLiquidGlass.Configuration) {
        self.init(frame: .zero)
        self.configuration = configuration
        rebuild()
    }

    deinit {
        displayLink?.invalidate()
        performanceObservers.forEach(NotificationCenter.default.removeObserver)
        if let hierarchyObserver { NotificationCenter.default.removeObserver(hierarchyObserver) }
        if didRegisterPerformance { LLGlassPerformanceGovernor.shared.unregisterGlass() }
    }

    private func setup() {
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        layer.masksToBounds = false
        layer.cornerCurve = .continuous

        shadowView.backgroundColor = .clear
        shadowView.isUserInteractionEnabled = false
        addSubview(shadowView)

        metalContainer.backgroundColor = .clear
        metalContainer.isUserInteractionEnabled = false
        addSubview(metalContainer)

        legacyRenderer.isUserInteractionEnabled = false
        addSubview(legacyRenderer)

        systemEffectView.isUserInteractionEnabled = false
        addSubview(systemEffectView)

        highlightOverlay.isUserInteractionEnabled = false
        highlightOverlay.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        highlightOverlay.alpha = 0
        highlightOverlay.layer.masksToBounds = true
        addSubview(highlightOverlay)

        contentView.backgroundColor = .clear
        addSubview(contentView)

        installObservers()
        rebuild()
    }

    private func installObservers() {
        performanceObservers.append(NotificationCenter.default.addObserver(forName: .LLGlassEnvironmentDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        })
        performanceObservers.append(NotificationCenter.default.addObserver(forName: .LLGlassPerformanceDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.requestCapture(force: false)
        })
        performanceObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.restartRenderingIfNeeded()
        })
        performanceObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopRendering()
        })
        hierarchyObserver = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.requestCapture(force: true)
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if !didRegisterPerformance {
                LLGlassPerformanceGovernor.shared.registerGlass()
                didRegisterPerformance = true
            }
            restartRenderingIfNeeded()
        } else {
            stopRendering()
            if didRegisterPerformance {
                LLGlassPerformanceGovernor.shared.unregisterGlass()
                didRegisterPerformance = false
            }
        }
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        attachBackdropSource()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = configuration.cornerRadius
        shadowView.frame = bounds.offsetBy(dx: configuration.shadowOffset.width, dy: configuration.shadowOffset.height)
        shadowView.layer.shadowPath = LLGlassGeometry.roundedPath(bounds: shadowView.bounds, radius: configuration.cornerRadius).cgPath
        shadowView.layer.shadowOpacity = configuration.shadowOpacity
        shadowView.layer.shadowRadius = configuration.shadowRadius
        shadowView.layer.shadowOffset = .zero

        metalContainer.frame = bounds
        legacyRenderer.frame = bounds
        systemEffectView.frame = bounds
        highlightOverlay.frame = bounds.insetBy(dx: 1, dy: 1)
        contentView.frame = bounds

        metalRenderer?.view.frame = metalContainer.bounds
        metalRenderer?.view.layer.cornerRadius = configuration.cornerRadius
        if lastLayoutBounds != bounds {
            lastLayoutBounds = bounds
            requestCapture(force: true)
        }
    }

    private func attachBackdropSource() {
        guard let parent = superview else { return }
        backdrop.sourceView = parent
        backdrop.exclusionView = self
        backdrop.captureScale = configuration.captureScale
        backdrop.maxPixels = configuration.maxCapturePixels
    }

    private func rebuild() {
        let effective = configuration
        let environment = LLGlassEnvironment.shared
        let material = LLGlassMaterialResolver.resolve(effective, environment: environment)
        let backend = effective.backend == .automatic ? LegacyLiquidGlass.effectiveBackend : effective.backend

        shadowView.isHidden = environment.reduceTransparency
        shadowView.layer.cornerRadius = effective.cornerRadius
        shadowView.layer.shadowColor = UIColor.black.cgColor

        if backend == .system {
            if #available(iOS 26.0, *) {
                configureSystem(material: material)
            } else {
                configureLegacy(material: material)
            }
        } else {
            configureLegacy(material: material)
        }
        updateHighlight(animated: false)
        updateInteraction()
    }

    @available(iOS 26.0, *)
    private func configureSystem(material: LLGlassMaterial) {
        metalContainer.isHidden = true
        legacyRenderer.isHidden = true
        systemEffectView.isHidden = false
        let tint: UIColor? = material.tint
        let effect = LLNativeLiquidGlass.effect(style: configuration.style, interactive: configuration.interactive, tint: tint)
        UIView.performWithoutAnimation {
            self.systemEffectView.effect = effect
        }
        systemEffectView.layer.cornerRadius = configuration.cornerRadius
        systemEffectView.layer.cornerCurve = .continuous
        contentView.layer.cornerRadius = configuration.cornerRadius
        contentView.layer.cornerCurve = .continuous
        highlightOverlay.backgroundColor = UIColor.white.withAlphaComponent(0.10)
    }

    private func configureLegacy(material: LLGlassMaterial) {
        systemEffectView.isHidden = true
        legacyRenderer.isHidden = !shouldUseVisualFallback()
        metalContainer.isHidden = shouldUseVisualFallback()
        legacyRenderer.material = material
        legacyRenderer.cornerRadius = configuration.cornerRadius
        highlightOverlay.backgroundColor = UIColor.white.withAlphaComponent(min(0.22, material.specular * 0.70))

        if !shouldUseVisualFallback() {
            if metalRenderer == nil {
                metalRenderer = LLMetalGlassRenderer(frame: bounds)
                if let rendererView = metalRenderer?.view {
                    metalContainer.addSubview(rendererView)
                }
            }
            updateMetal(material: material)
        }
        attachBackdropSource()
    }

    private static let metalAvailable = MTLCreateSystemDefaultDevice() != nil

    private func shouldUseVisualFallback() -> Bool {
        return LegacyLiquidGlass.configuration.quality == .low || !Self.metalAvailable || LLGlassEnvironment.shared.reduceTransparency
    }

    private func updateMetal(material: LLGlassMaterial) {
        guard let renderer = metalRenderer else { return }
        let c = LLGlassColorMath.components(material.tint ?? UIColor(white: 1, alpha: 1))
        var settings = LLMetalGlassRenderer.Settings()
        settings.cornerRadius = configuration.cornerRadius
        settings.refraction = material.refraction
        settings.specular = material.specular
        settings.edgeLight = material.edgeLight
        settings.tintStrength = configuration.tintStrength
        settings.opacity = material.opacity
        settings.darkness = material.darkness
        settings.time = time
        settings.quality = CGFloat(max(1, LLGlassPerformanceGovernor.shared.currentQuality.rawValue + 1))
        settings.tint = SIMD3<Float>(c.x, c.y, c.z)
        metalRenderer = renderer
        metalRenderer?.view.frame = bounds
        if let snapshot = backdrop.latest {
            renderer.update(source: snapshot.image, settings: settings)
        }
    }

    private func requestCapture(force: Bool) {
        guard window != nil, !metalContainer.isHidden else { return }
        attachBackdropSource()
        guard !capturePending else { return }
        capturePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.capturePending = false
            guard let snapshot = self.backdrop.captureIfNeeded(force: force) else { return }
            let material = LLGlassMaterialResolver.resolve(self.configuration)
            self.updateMetal(material: material)
            self.metalRenderer?.update(source: snapshot.image, settings: self.currentMetalSettings(material: material))
        }
    }

    private func currentMetalSettings(material: LLGlassMaterial) -> LLMetalGlassRenderer.Settings {
        let c = LLGlassColorMath.components(material.tint ?? UIColor(white: 1, alpha: 1))
        var settings = LLMetalGlassRenderer.Settings()
        settings.cornerRadius = configuration.cornerRadius
        settings.refraction = material.refraction
        settings.specular = material.specular
        settings.edgeLight = material.edgeLight
        settings.tintStrength = configuration.tintStrength
        settings.opacity = material.opacity
        settings.darkness = material.darkness
        settings.time = time
        settings.quality = CGFloat(max(1, LLGlassPerformanceGovernor.shared.currentQuality.rawValue + 1))
        settings.tint = SIMD3<Float>(c.x, c.y, c.z)
        return settings
    }

    private func updateInteraction() {
        guard configuration.interactive else {
            interactionDriver?.uninstall()
            interactionDriver = nil
            return
        }
        if interactionDriver == nil {
            interactionDriver = LLGlassInteractionDriver(view: self)
            interactionDriver?.install()
        }
    }

    private func updateHighlight(animated: Bool) {
        let alpha = isHighlighted && !LLGlassEnvironment.shared.reduceTransparency ? 1.0 : 0.0
        let changes = {
            self.highlightOverlay.alpha = alpha
            self.highlightOverlay.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.992, y: 0.992) : .identity
        }
        if animated && configuration.animated && !LLGlassEnvironment.shared.reduceMotion {
            UIView.animate(withDuration: isHighlighted ? 0.12 : 0.26, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.3, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        } else {
            changes()
        }
    }

    private func restartRenderingIfNeeded() {
        guard window != nil else { return }
        guard configuration.animated || configuration.liveCapture else { return }
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(renderTick(_:)))
            link.preferredFramesPerSecond = min(configuration.quality.captureFPS, configuration.preferredFrameRate)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        LLGlassPerformanceGovernor.shared.start()
        requestCapture(force: true)
    }

    private func stopRendering() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func renderTick(_ link: CADisplayLink) {
        let now = link.timestamp
        if lastFrame == 0 { lastFrame = now }
        let delta = CGFloat(max(0, now - lastFrame))
        lastFrame = now
        time += delta
        guard configuration.liveCapture else { return }
        let targetFPS = LLGlassPerformanceGovernor.shared.currentQuality.captureFPS
        let captureInterval = 1.0 / Double(max(1, targetFPS))
        if now - lastCaptureRequest >= captureInterval {
            lastCaptureRequest = now
            requestCapture(force: false)
        } else if metalRenderer != nil {
            var material = LLGlassMaterialResolver.resolve(configuration)
            material.refraction *= configuration.interactive && isHighlighted ? 1.35 : 1.0
            metalRenderer?.update(source: backdrop.latest?.image, settings: currentMetalSettings(material: material))
        }
    }
}

// MARK: - 11. Glass Container / Morphing

public final class LLGlassContainer: UIView {
    public var spacing: CGFloat = 10 {
        didSet { setNeedsLayout() }
    }

    public var morphing = true
    public var axis: NSLayoutConstraint.Axis = .horizontal {
        didSet { setNeedsLayout() }
    }

    private var glassItems: [LLGlassView] = []
    private var lastBounds = CGRect.zero

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        clipsToBounds = false
    }

    public func addGlass(_ glass: LLGlassView) {
        glassItems.append(glass)
        addSubview(glass)
        setNeedsLayout()
    }

    public func removeGlass(_ glass: LLGlassView) {
        glassItems.removeAll { $0 === glass }
        glass.removeFromSuperview()
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard !glassItems.isEmpty else { return }
        let sizes = glassItems.map { preferredSize(for: $0) }
        if axis == .horizontal {
            var x: CGFloat = 0
            for (index, glass) in glassItems.enumerated() {
                let size = sizes[index]
                glass.frame = CGRect(x: x, y: (bounds.height - size.height) * 0.5, width: size.width, height: size.height)
                x += size.width + (index == glassItems.count - 1 ? 0 : spacing)
            }
        } else {
            var y: CGFloat = 0
            for (index, glass) in glassItems.enumerated() {
                let size = sizes[index]
                glass.frame = CGRect(x: (bounds.width - size.width) * 0.5, y: y, width: size.width, height: size.height)
                y += size.height + (index == glassItems.count - 1 ? 0 : spacing)
            }
        }
        if lastBounds != bounds {
            lastBounds = bounds
            updateMorphing()
        }
    }

    private func preferredSize(for view: UIView) -> CGSize {
        let target = view.intrinsicContentSize
        let width = target.width > 0 ? target.width : max(44, bounds.width / max(1, CGFloat(glassItems.count)))
        let height = target.height > 0 ? target.height : 44
        return CGSize(width: min(width, bounds.width), height: min(height, bounds.height))
    }

    private func updateMorphing() {
        guard morphing, glassItems.count > 1 else { return }
        for index in 0..<glassItems.count {
            let glass = glassItems[index]
            let current = glass.configuration
            let nearLeft = index > 0
            let nearRight = index < glassItems.count - 1
            var radius = current.cornerRadius
            if nearLeft || nearRight {
                radius = min(radius, 18)
            }
            var config = current
            config.cornerRadius = radius
            glass.configuration = config
        }
    }
}

// MARK: - 12. UIKit Glass Button

public final class LLGlassButton: UIButton {
    public var glassConfiguration: LegacyLiquidGlass.Configuration = .init() {
        didSet { rebuildGlass() }
    }

    private let glass = LLGlassView()

    public override var isHighlighted: Bool {
        didSet { glass.isHighlighted = isHighlighted }
    }

    public override var isSelected: Bool {
        didSet { rebuildGlass() }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        setTitleColor(.label, for: .normal)
        layer.cornerCurve = .continuous
        contentHorizontalAlignment = .center
        contentVerticalAlignment = .center
        insertSubview(glass, at: 0)
        rebuildGlass()
    }

    private func rebuildGlass() {
        var config = glassConfiguration
        if isSelected {
            if case .regular = config.style { config.style = .prominent }
        }
        glass.configuration = config
        sendSubviewToBack(glass)
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()
        if tintColor != nil && glassConfiguration.style == .regular {
            glassConfiguration.style = .tinted(tintColor)
        }
    }
}

// MARK: - 13. UIKit Glass Toolbar

public final class LLGlassToolbar: UIView {
    public let contentView = UIView()
    private let glass = LLGlassView()
    public var configuration: LegacyLiquidGlass.Configuration {
        didSet { glass.configuration = configuration }
    }

    public override init(frame: CGRect) {
        configuration = LegacyLiquidGlass.Configuration()
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        configuration = LegacyLiquidGlass.Configuration()
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        addSubview(glass)
        addSubview(contentView)
        contentView.backgroundColor = .clear
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds.insetBy(dx: 12, dy: 6)
        contentView.frame = glass.frame
    }
}

// MARK: - 14. UIKit Glass Search Bar

public final class LLGlassSearchBar: UIView {
    public let textField = UITextField()
    private let glass = LLGlassView()
    private let iconView = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private let clearButton = UIButton(type: .system)

    public var placeholder: String = LLGlassLocalization.string("search") {
        didSet { textField.placeholder = placeholder }
    }

    public var onClear: (() -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        addSubview(glass)
        addSubview(iconView)
        addSubview(textField)
        addSubview(clearButton)
        iconView.tintColor = .secondaryLabel
        textField.borderStyle = .none
        textField.clearButtonMode = .never
        textField.placeholder = placeholder
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = .tertiaryLabel
        clearButton.addTarget(self, action: #selector(clearText), for: .touchUpInside)
        glass.configuration.style = .clear
        glass.configuration.cornerRadius = 18
    }

    @objc private func clearText() {
        textField.text = nil
        onClear?()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        iconView.frame = CGRect(x: 12, y: 0, width: 20, height: bounds.height)
        textField.frame = CGRect(x: 38, y: 0, width: max(0, bounds.width - 78), height: bounds.height)
        clearButton.frame = CGRect(x: max(0, bounds.width - 38), y: 0, width: 30, height: bounds.height)
    }
}

// MARK: - 15. UIKit Glass Tab Bar

public final class LLGlassTabBar: UIView {
    public struct Item {
        public var title: String
        public var image: UIImage?
        public var selectedImage: UIImage?

        public init(title: String, image: UIImage? = nil, selectedImage: UIImage? = nil) {
            self.title = title
            self.image = image
            self.selectedImage = selectedImage
        }
    }

    public var items: [Item] = [] { didSet { rebuildItems() } }
    public var selectedIndex: Int = 0 { didSet { updateSelection(animated: true) } }
    public var onSelectionChanged: ((Int) -> Void)?

    private let glass = LLGlassView()
    private var buttons: [LLGlassButton] = []

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(glass)
        glass.configuration.cornerRadius = 26
        glass.configuration.style = .regular
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        addSubview(glass)
        glass.configuration.cornerRadius = 26
    }

    private func rebuildItems() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        for item in items {
            let button = LLGlassButton(type: .system)
            button.setTitle(item.title, for: .normal)
            button.setImage(item.image, for: .normal)
            addSubview(button)
            buttons.append(button)
            let target = LLClosureControlTarget { [weak self, weak button] in
                guard let self, let button, let index = self.buttons.firstIndex(where: { $0 === button }) else { return }
                self.selectedIndex = index
                self.onSelectionChanged?(index)
            }
            button.llStoreActionTarget(target)
        }
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        let count = max(1, buttons.count)
        let width = bounds.width / CGFloat(count)
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: CGFloat(index) * width + 4, y: 4, width: width - 8, height: max(0, bounds.height - 8))
        }
        updateSelection(animated: false)
    }

    private func updateSelection(animated: Bool) {
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedIndex
            var config = button.glassConfiguration
            config.style = selected ? .prominent : .clear
            button.glassConfiguration = config
            if let item = index < items.count ? items[index] : nil {
                let image = selected ? (item.selectedImage ?? item.image) : item.image
                button.setImage(image, for: .normal)
            }
        }
        if animated && !LLGlassEnvironment.shared.reduceMotion {
            UIView.animate(withDuration: 0.26, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.5, options: [.beginFromCurrentState, .allowUserInteraction]) {}
        }
    }
}

// MARK: - 16. UIKit Glass Navigation Bar

public final class LLGlassNavigationBar: UIView {
    public let contentView = UIView()
    public let titleLabel = UILabel()
    public let subtitleLabel = UILabel()

    private let glass = LLGlassView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        addSubview(glass)
        addSubview(contentView)
        contentView.backgroundColor = .clear
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabel
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        glass.configuration.cornerRadius = 22
        glass.configuration.style = .regular
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds.insetBy(dx: 10, dy: 6)
        contentView.frame = glass.frame
        let titleHeight = min(24, contentView.bounds.height)
        titleLabel.frame = CGRect(x: 18, y: max(0, (contentView.bounds.height - titleHeight) * 0.5 - 6), width: max(0, contentView.bounds.width - 36), height: titleHeight)
        subtitleLabel.frame = CGRect(x: 18, y: min(contentView.bounds.height - 18, titleLabel.frame.maxY), width: max(0, contentView.bounds.width - 36), height: 16)
    }
}

// MARK: - 17. UIKit Glass Sheet / Card

public final class LLGlassCard: UIView {
    private let glass = LLGlassView()
    public let contentView = UIView()

    public var cornerRadius: CGFloat = 28 {
        didSet {
            glass.configuration.cornerRadius = cornerRadius
            setNeedsLayout()
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        addSubview(glass)
        addSubview(contentView)
        contentView.backgroundColor = .clear
        glass.configuration.cornerRadius = cornerRadius
        glass.configuration.style = .prominent
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        contentView.frame = bounds.insetBy(dx: 12, dy: 12)
    }
}

// MARK: - 18. SwiftUI System / Legacy Bridge

public struct LLGlassModifier: ViewModifier {
    public var configuration: LegacyLiquidGlass.Configuration

    public init(configuration: LegacyLiquidGlass.Configuration = .init()) {
        self.configuration = configuration
    }

    public func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *), configuration.backend != .legacy, configuration.useNativeSwiftUIOn26 {
                nativeBody(content: content)
            } else {
                legacyBody(content: content)
            }
        }
    }

    @available(iOS 26.0, *)
    private func nativeBody(content: Content) -> some View {
        let glass: Glass = {
            switch configuration.style {
            case .clear:
                return .clear
            case .tinted(let color):
                return .regular.tint(Color(uiColor: color))
            case .custom(let color, _, _):
                return .regular.tint(Color(uiColor: color))
            case .prominent:
                return .regular
            case .regular:
                return .regular
            }
        }()
        let configured = configuration.interactive ? glass.interactive(true) : glass
        return content
            .glassEffect(configured, in: .rect(cornerRadius: configuration.cornerRadius))
    }

    private func legacyBody(content: Content) -> some View {
        content.background(
            LLGlassRepresentable(configuration: configuration)
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: configuration.cornerRadius, style: .continuous))
        )
    }
}

public extension View {
    func llGlass(_ configuration: LegacyLiquidGlass.Configuration = .init()) -> some View {
        modifier(LLGlassModifier(configuration: configuration))
    }

    func llGlassClear(cornerRadius: CGFloat = 20, interactive: Bool = true) -> some View {
        var configuration = LegacyLiquidGlass.Configuration()
        configuration.style = .clear
        configuration.cornerRadius = cornerRadius
        configuration.interactive = interactive
        return modifier(LLGlassModifier(configuration: configuration))
    }

    func llGlassProminent(cornerRadius: CGFloat = 22, interactive: Bool = true) -> some View {
        var configuration = LegacyLiquidGlass.Configuration()
        configuration.style = .prominent
        configuration.cornerRadius = cornerRadius
        configuration.interactive = interactive
        return modifier(LLGlassModifier(configuration: configuration))
    }

    func llGlassTinted(_ tint: Color, cornerRadius: CGFloat = 22, interactive: Bool = true) -> some View {
        var configuration = LegacyLiquidGlass.Configuration()
        configuration.style = .tinted(LLGlassColorBridge.color(tint))
        configuration.cornerRadius = cornerRadius
        configuration.interactive = interactive
        return modifier(LLGlassModifier(configuration: configuration))
    }
}

public struct LLGlassRepresentable: UIViewRepresentable {
    public var configuration: LegacyLiquidGlass.Configuration

    public init(configuration: LegacyLiquidGlass.Configuration) {
        self.configuration = configuration
    }

    public func makeUIView(context: Context) -> LLGlassView {
        LLGlassView(configuration: configuration)
    }

    public func updateUIView(_ uiView: LLGlassView, context: Context) {
        uiView.configuration = configuration
    }
}

// MARK: - 19. SwiftUI Glass Container

public struct LLGlassContainer<Content: View>: View {
    public var spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        Group {
            if #available(iOS 26.0, *), LegacyLiquidGlass.configuration.useNativeSwiftUIOn26 {
                GlassEffectContainer(spacing: spacing) { content }
            } else {
                HStack(spacing: spacing) { content }
            }
        }
    }
}

// MARK: - 20. SwiftUI Buttons / Controls

public struct LLGlassButtonStyle: ButtonStyle {
    public var prominent: Bool
    public var tint: Color?

    public init(prominent: Bool = false, tint: Color? = nil) {
        self.prominent = prominent
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .modifier(LLGlassModifier(configuration: makeConfiguration(isPressed: configuration.isPressed)))
            .scaleEffect(configuration.isPressed && !LLGlassEnvironment.shared.reduceMotion ? 0.97 : 1)
            .animation(LLGlassEnvironment.shared.reduceMotion ? nil : .interactiveSpring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
    }

    private func makeConfiguration(isPressed: Bool) -> LegacyLiquidGlass.Configuration {
        var config = LegacyLiquidGlass.Configuration()
        config.style = prominent ? (tint.map { .tinted(UIColor($0)) } ?? .prominent) : (tint.map { .tinted(UIColor($0)) } ?? .regular)
        config.interactive = true
        config.cornerRadius = 20
        config.specularStrength = isPressed ? 0.34 : 0.28
        config.refractionStrength = isPressed ? 0.022 : 0.016
        return config
    }
}

public struct LLGlassActionButton: View {
    private let title: String
    private let systemImage: String?
    private let prominent: Bool
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = prominent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage ?? "")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(LLGlassButtonStyle(prominent: prominent))
    }
}

// MARK: - 21. SwiftUI Tab / Toolbar Helpers

public struct LLGlassToolbarItem<Label: View>: View {
    private let label: () -> Label
    private let prominent: Bool
    private let action: () -> Void

    public init(prominent: Bool = false, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.prominent = prominent
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(LLGlassButtonStyle(prominent: prominent))
    }
}

// MARK: - 22. Shape / Material Helpers

public struct LLLiquidRoundedRectangle: Shape {
    public var radius: CGFloat
    public var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    public init(radius: CGFloat) {
        self.radius = radius
    }

    public func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, cornerRadius: min(radius, min(rect.width, rect.height) * 0.5)).cgPath)
    }
}

public struct LLGlassBackgroundStyle: ViewModifier {
    public var style: LegacyLiquidGlass.Style
    public var cornerRadius: CGFloat

    public init(style: LegacyLiquidGlass.Style = .regular, cornerRadius: CGFloat = 24) {
        self.style = style
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        var config = LegacyLiquidGlass.Configuration()
        config.style = style
        config.cornerRadius = cornerRadius
        return content.modifier(LLGlassModifier(configuration: config))
    }
}

public extension View {
    func llGlassBackground(style: LegacyLiquidGlass.Style = .regular, cornerRadius: CGFloat = 24) -> some View {
        modifier(LLGlassBackgroundStyle(style: style, cornerRadius: cornerRadius))
    }
}

// MARK: - 23. Localization

public enum LLGlassLocalization {
    public enum Language: String, CaseIterable {
        case system
        case english = "en"
        case simplifiedChinese = "zh-Hans"
        case traditionalChinese = "zh-Hant"
        case japanese = "ja"
    }

    public static var language: Language = .system

    private static let table: [String: [Language: String]] = [
        "search": [
            .english: "Search",
            .simplifiedChinese: "搜索",
            .traditionalChinese: "搜尋",
            .japanese: "検索"
        ],
        "cancel": [
            .english: "Cancel",
            .simplifiedChinese: "取消",
            .traditionalChinese: "取消",
            .japanese: "キャンセル"
        ],
        "done": [
            .english: "Done",
            .simplifiedChinese: "完成",
            .traditionalChinese: "完成",
            .japanese: "完了"
        ],
        "close": [
            .english: "Close",
            .simplifiedChinese: "关闭",
            .traditionalChinese: "關閉",
            .japanese: "閉じる"
        ],
        "settings": [
            .english: "Settings",
            .simplifiedChinese: "设置",
            .traditionalChinese: "設定",
            .japanese: "設定"
        ],
        "open": [
            .english: "Open",
            .simplifiedChinese: "打开",
            .traditionalChinese: "開啟",
            .japanese: "開く"
        ],
        "save": [
            .english: "Save",
            .simplifiedChinese: "保存",
            .traditionalChinese: "儲存",
            .japanese: "保存"
        ],
        "delete": [
            .english: "Delete",
            .simplifiedChinese: "删除",
            .traditionalChinese: "刪除",
            .japanese: "削除"
        ],
        "confirm": [
            .english: "Confirm",
            .simplifiedChinese: "确认",
            .traditionalChinese: "確認",
            .japanese: "確認"
        ],
        "share": [
            .english: "Share",
            .simplifiedChinese: "共享",
            .traditionalChinese: "分享",
            .japanese: "共有"
        ],
        "more": [
            .english: "More",
            .simplifiedChinese: "更多",
            .traditionalChinese: "更多",
            .japanese: "その他"
        ],
        "loading": [
            .english: "Loading…",
            .simplifiedChinese: "正在加载…",
            .traditionalChinese: "正在載入…",
            .japanese: "読み込み中…"
        ],
        "error": [
            .english: "Error",
            .simplifiedChinese: "错误",
            .traditionalChinese: "錯誤",
            .japanese: "エラー"
        ]
    ]

    public static func string(_ key: String, language: Language? = nil) -> String {
        let requested = language ?? self.language
        let selected: Language
        switch requested {
        case .system:
            let code = Locale.preferredLanguages.first ?? "en"
            if code.hasPrefix("zh-Hans") || code.hasPrefix("zh-CN") { selected = .simplifiedChinese }
            else if code.hasPrefix("zh-Hant") || code.hasPrefix("zh-TW") || code.hasPrefix("zh-HK") { selected = .traditionalChinese }
            else if code.hasPrefix("ja") { selected = .japanese }
            else { selected = .english }
        default:
            selected = requested
        }
        return table[key]?[selected] ?? table[key]?[.english] ?? key
    }

    public static func setLanguage(_ language: Language) {
        self.language = language
        NotificationCenter.default.post(name: .LLGlassThemeDidChange, object: nil)
    }
}

// MARK: - 24. Diagnostics / Profiling

public struct LLGlassDiagnosticsReport: Sendable {
    public let version: String
    public let backend: String
    public let quality: String
    public let fps: Double
    public let thermalState: String
    public let glassCount: Int
    public let reduceTransparency: Bool
    public let reduceMotion: Bool

    public var dictionary: [String: Any] {
        [
            "version": version,
            "backend": backend,
            "quality": quality,
            "fps": fps,
            "thermalState": thermalState,
            "glassCount": glassCount,
            "reduceTransparency": reduceTransparency,
            "reduceMotion": reduceMotion
        ]
    }
}

public enum LLGlassDiagnostics {
    public static func report() -> LLGlassDiagnosticsReport {
        let governor = LLGlassPerformanceGovernor.shared
        let environment = LLGlassEnvironment.shared
        return LLGlassDiagnosticsReport(
            version: LegacyLiquidGlass.version,
            backend: String(describing: LegacyLiquidGlass.effectiveBackend),
            quality: String(describing: governor.currentQuality),
            fps: governor.measuredFPS,
            thermalState: String(describing: governor.thermalState),
            glassCount: governor.activeGlassCount,
            reduceTransparency: environment.reduceTransparency,
            reduceMotion: environment.reduceMotion
        )
    }
}

// MARK: - 25. UIView Convenience

public extension UIView {
    @discardableResult
    func llApplyGlass(_ configuration: LegacyLiquidGlass.Configuration = .init()) -> LLGlassView {
        let glass = LLGlassView(configuration: configuration)
        insertSubview(glass, at: 0)
        glass.frame = bounds
        glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return glass
    }
}

// MARK: - 26. Runtime Bootstrap

public enum LLGlassBootstrap {
    private static var started = false

    public static func start() {
        guard !started else { return }
        started = true
        _ = LLGlassEnvironment.shared
        LLGlassPerformanceGovernor.shared.start()
    }

    public static func stop() {
        guard started else { return }
        started = false
        LLGlassPerformanceGovernor.shared.stop()
    }
}

// MARK: - 27. Safe Color Bridge

public enum LLGlassColorBridge {
    public static func color(_ color: Color) -> UIColor {
        #if canImport(UIKit)
        if #available(iOS 14.0, *) {
            return UIColor(color)
        }
        #endif
        return .white
    }
}

// MARK: - 28. UIColor / SwiftUI Bridge

// MARK: - 29. Public Presets

public enum LLGlassPresets {
    public static var regular: LegacyLiquidGlass.Configuration {
        var configuration = LegacyLiquidGlass.Configuration()
        configuration.style = .regular
        configuration.cornerRadius = 24
        return configuration
    }

    public static var clear: LegacyLiquidGlass.Configuration {
        var configuration = LegacyLiquidGlass.Configuration()
        configuration.style = .clear
        configuration.cornerRadius = 20
        configuration.blurRadius = 10
        configuration.refractionStrength = 0.010
        return configuration
    }

    public static var prominent: LegacyLiquidGlass.Configuration {
        var configuration = LegacyLiquidGlass.Configuration()
        configuration.style = .prominent
        configuration.cornerRadius = 24
        configuration.blurRadius = 24
        configuration.specularStrength = 0.34
        configuration.edgeLightStrength = 0.40
        configuration.refractionStrength = 0.020
        return configuration
    }

    public static func tinted(_ color: UIColor, cornerRadius: CGFloat = 22) -> LegacyLiquidGlass.Configuration {
        var configuration = regular
        configuration.style = .tinted(color)
        configuration.cornerRadius = cornerRadius
        return configuration
    }
}

// MARK: - 30. Debug Overlay

public final class LLGlassDebugOverlay: UIView {
    private let label = UILabel()
    private var timer: CADisplayLink?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit { timer?.invalidate() }

    private func setup() {
        backgroundColor = UIColor.black.withAlphaComponent(0.48)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        let link = CADisplayLink(target: self, selector: #selector(update))
        link.add(to: .main, forMode: .common)
        timer = link
    }

    @objc private func update() {
        let report = LLGlassDiagnostics.report()
        label.text = [
            "LegacyLiquidGlass \(report.version)",
            "backend: \(report.backend)",
            "quality: \(report.quality)",
            String(format: "fps: %.1f", report.fps),
            "thermal: \(report.thermalState)",
            "glass: \(report.glassCount)"
        ].joined(separator: "\n")
        sizeToFit()
    }
}

// MARK: - 31. Material Animation Helpers

public enum LLGlassAnimations {
    public static func materialize(_ view: UIView, animated: Bool = true) {
        guard animated, !LLGlassEnvironment.shared.reduceMotion else {
            view.alpha = 1
            view.transform = .identity
            return
        }
        view.alpha = 0
        view.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.15, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
            view.alpha = 1
            view.transform = .identity
        })
    }

    public static func dematerialize(_ view: UIView, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard animated, !LLGlassEnvironment.shared.reduceMotion else {
            view.alpha = 0
            completion?()
            return
        }
        UIView.animate(withDuration: 0.24, animations: {
            view.alpha = 0
            view.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        }) { _ in
            completion?()
        }
    }

    public static func merge(_ views: [UIView], into target: CGRect, duration: TimeInterval = 0.42) {
        guard !LLGlassEnvironment.shared.reduceMotion else {
            views.forEach { $0.frame = target }
            return
        }
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.2, options: [.beginFromCurrentState, .allowUserInteraction]) {
            views.forEach { $0.frame = target }
        }
    }
}

// MARK: - 32. Accessibility Adaptation

public enum LLGlassAccessibility {
    public static func apply(to view: UIView) {
        let environment = LLGlassEnvironment.shared
        if environment.reduceTransparency {
            view.layer.opacity = 0.96
        }
        if environment.boldText {
            view.accessibilityTraits.insert(.updatesFrequently)
        }
    }
}

// MARK: - 33. Scroll-aware Capture Helper

public final class LLGlassScrollCoordinator: NSObject, UIScrollViewDelegate {
    public weak var scrollView: UIScrollView?
    private var registeredViews: NSHashTable<LLGlassView> = .weakObjects()

    public init(scrollView: UIScrollView) {
        self.scrollView = scrollView
        super.init()
    }

    public func register(_ glass: LLGlassView) {
        registeredViews.add(glass)
    }

    public func unregister(_ glass: LLGlassView) {
        registeredViews.remove(glass)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        for glass in registeredViews.allObjects {
            glass.setNeedsLayout()
        }
    }
}

private final class LLClosureControlTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init()
    }

    @objc func invoke() {
        action()
    }
}

private var llActionTargetKey: UInt8 = 0

private extension UIButton {
    func llStoreActionTarget(_ target: LLClosureControlTarget) {
        objc_setAssociatedObject(self, &llActionTargetKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        addTarget(target, action: #selector(LLClosureControlTarget.invoke), for: .touchUpInside)
    }
}

// MARK: - 34. Final API Entry Points

public extension LegacyLiquidGlass {
    static func makeGlass(configuration: Configuration = Configuration()) -> LLGlassView {
        LLGlassView(configuration: configuration)
    }

    static func makeButton(title: String, configuration: Configuration = Configuration(), action: @escaping () -> Void) -> UIButton {
        let button = LLGlassButton(type: .system)
        button.setTitle(title, for: .normal)
        button.glassConfiguration = configuration
        button.llStoreActionTarget(LLClosureControlTarget(action: action))
        return button
    }
}
