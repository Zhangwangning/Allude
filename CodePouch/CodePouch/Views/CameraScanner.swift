import AVFoundation
import SwiftUI
import UIKit

// MARK: ============================================================================
// 相机扫码（二维码 + 常见一维码）
//
// 用 AVFoundation 的 metadata output 而不是 VisionKit 的 DataScannerViewController：
// 后者要求 A12 及以上且不支持模拟器，而元数据输出在真机上的兼容面更宽、
// 且「识别到什么就回调什么」这一行为完全可控。
//
// ⚠️ 必须在 Info.plist 提供 NSCameraUsageDescription，否则进程会被系统直接终止。
// ============================================================================

/// 扫码能力的可用性三态 —— 用于在模拟器 / 拒绝授权时给出正确降级界面，
/// 而不是丢给用户一块黑屏。
enum ScannerAvailability {
    case ready
    case denied
    case unsupported

    static func current() -> ScannerAvailability {
        guard AVCaptureDevice.default(for: .video) != nil else { return .unsupported }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .ready
        case .notDetermined: return .ready          // 交给系统在首次进入时弹权限
        default: return .denied
        }
    }
}

struct CameraScannerView: UIViewControllerRepresentable {
    /// 每次成功识别到一个 code 内容时回调（已做同一次进入内的去重）
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerHostController {
        let controller = ScannerHostController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ controller: ScannerHostController, context: Context) {
        controller.onScan = onScan
    }
}

final class ScannerHostController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onScan: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    /// 一次进入只上报一次结果：扫码是「秒级」动作，连续回调只会造成重复写入
    private var hasReported = false
    private var isConfigured = false

    /// 扫码类型：二维码 + 取件凭证最常见的几种一维码
    private static let wantedTypes: [AVMetadataObject.ObjectType] = [
        .qr, .aztec, .dataMatrix, .pdf417,
        .ean13, .ean8, .upce, .code128, .code39, .code93, .itf14,
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.startSession() }
            }
        } else {
            startSession()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 预览层不参与 Auto Layout，尺寸靠这里跟随容器
        previewLayer?.frame = view.bounds
    }

    // MARK: 会话装配

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        // 类型必须在 addOutput 之后设置，且只能取交集 —— 直接赋本机不支持的类型会崩
        let available = Set(output.availableMetadataObjectTypes)
        output.metadataObjectTypes = Self.wantedTypes.filter { available.contains($0) }
        output.setMetadataObjectsDelegate(self, queue: .main)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        isConfigured = true
    }

    private func startSession() {
        configureIfNeeded()
        guard isConfigured, !session.isRunning else { return }
        // startRunning 是同步阻塞调用，放主线程会卡住进入动画
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    private func stopSession() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }

    // MARK: 回调

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasReported else { return }
        guard let object = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
            .first(where: { ($0.stringValue ?? "").isEmpty == false }),
              let value = object.stringValue else { return }

        hasReported = true
        stopSession()

        // 轻微触觉反馈：让「扫到了」这件事有实感，不用盯着屏幕
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onScan?(value)
    }

    /// 允许外部重置，供「重新扫描」使用
    func reset() {
        hasReported = false
        startSession()
    }
}
