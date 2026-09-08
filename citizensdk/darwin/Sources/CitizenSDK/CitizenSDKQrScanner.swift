import Foundation
@preconcurrency import AVFoundation
import CoreVideo

/// 两个 Apple 平台只采集 8 位亮度帧；识别及协议解析由同一 ZXing/Rust 调用处理。
/// 相机配置、帧借用和关闭在唯一串行队列排空，任何迟到权限回调都不能重开设备。
internal final class CitizenSDKQrCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "org.citizen.sdk.qr-camera")
    private let gate = NSLock()
    private var revoked = false
    private var started = false
    private var notifications: [NSObjectProtocol] = []
    private let output = AVCaptureVideoDataOutput()
    private let frame: @Sendable (Data, UInt32, UInt32, UInt32) -> Void
    private let failure: @Sendable (CitizenSDKError) -> Void
    private var lastFrame: UInt64 = 0

    init(frame: @escaping @Sendable (Data, UInt32, UInt32, UInt32) -> Void,
         failure: @escaping @Sendable (CitizenSDKError) -> Void) {
        self.frame = frame; self.failure = failure
        super.init()
    }

    private var active: Bool {
        gate.lock(); defer { gate.unlock() }
        return !revoked
    }

    func start() {
        guard active else { return }
        guard let usage = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String,
              !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail(.permissionDenied, "宿主须声明 NSCameraUsageDescription 才能使用扫码")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: queue.async { [self] in configure() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                guard let self, self.active else { return }
                if allowed { self.queue.async { [self] in self.configure() } }
                else { self.fail(.permissionDenied, "相机权限未授予") }
            }
        case .denied, .restricted: fail(.permissionDenied, "相机权限不可用")
        @unknown default: fail(.unavailable, "系统相机授权状态不可用")
        }
    }

    func close(_ completion: @escaping @Sendable () -> Void) {
        gate.lock(); revoked = true; gate.unlock()
        queue.async { [self] in
            stopDevice()
            // 同队列中在先的帧回调已返回；界面只能在此后交付扫码终态。
            completion()
        }
    }

    private func configure() {
        guard active, !started else { return }
        guard let device = AVCaptureDevice.default(for: .video) else {
            fail(.unavailable, "没有可用相机"); return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            guard session.canAddInput(input), session.canAddOutput(output),
                  session.canSetSessionPreset(.hd1280x720) else {
                session.commitConfiguration()
                fail(.unavailable, "相机不支持所需采集配置"); return
            }
            session.sessionPreset = .hd1280x720
            session.addInput(input)
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            output.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(output)
            session.commitConfiguration()
            let center = NotificationCenter.default
            for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
                notifications.append(center.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                    self?.fail(.unavailable, "相机采集被系统中断")
                })
            }
            notifications.append(center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil) { [weak self] _ in
                self?.fail(.unavailable, "相机已断开")
            })
            guard active else { stopDevice(); return }
            session.startRunning()
            started = true
            if !session.isRunning { fail(.unavailable, "无法启动相机") }
        } catch {
            fail(.unavailable, "无法配置相机输入")
        }
    }

    private func stopDevice() {
        notifications.forEach(NotificationCenter.default.removeObserver)
        notifications.removeAll()
        output.setSampleBufferDelegate(nil, queue: nil)
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.commitConfiguration()
        started = false
    }

    private func fail(_ code: CitizenSDKErrorCode, _ message: String) {
        gate.lock()
        guard !revoked else { gate.unlock(); return }
        revoked = true
        gate.unlock()
        queue.async { [self] in
            stopDevice()
            failure(CitizenSDKError(code, message))
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard active else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= lastFrame, now - lastFrame >= 100_000_000 else { return }
        lastFrame = now
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer), CVPixelBufferGetPlaneCount(pixel) == 2,
              CVPixelBufferGetPixelFormatType(pixel) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else { return }
        let width = CVPixelBufferGetWidthOfPlane(pixel, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixel, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixel, 0)
        guard width > 0, height > 0, width <= 4096, height <= 4096,
              stride >= width, stride <= 16 * 1024 * 1024 / height else { return }
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        guard let bytes = CVPixelBufferGetBaseAddressOfPlane(pixel, 0) else { return }
        // 像素仅在此有界复制；不保存到文件、日志、相册或跨会话缓存。
        let luminance = Data(bytes: bytes, count: stride * height)
        guard active else { return }
        frame(luminance, UInt32(width), UInt32(height), UInt32(stride))
    }
}

/// UI 只持有 Core 的不可变审阅凭证。关闭先撤销采集/请求，再等待队列、认证及窗口真正结束。
@MainActor
internal final class CitizenSDKQrFlow {
    let sdk: CitizenSdk
    let signText: String?
    private let reservation: UUID
    private var capture: CitizenSDKQrCapture?
    private var review: CitizenSDKQrReview?
    private var reviewOperation: CitizenSDKOperation<CitizenSDKQrReview>?
    private var signOperation: CitizenSDKOperation<CitizenQRDocument>?
    private var terminal: Result<CitizenQRDocument, Error>?
    private var captureDrained = true
    private var delivering = false
    private(set) var confirmed = false
    var onReview: ((String) -> Void)?
    var onClear: (() -> Void)?
    var onDismiss: ((@escaping () -> Void) -> Void)?
    lazy var operation = CitizenSDKOperation<CitizenQRDocument> { [weak self] in
        Task { @MainActor [weak self] in self?.cancel() }
        return true
    }

    init(sdk: CitizenSdk, signText: String?) throws {
        try sdk.requireQRUI()
        self.sdk = sdk; self.signText = signText
        reservation = try CitizenSDKWalletFlowRegistry.shared.reserve(sdk)
    }

    func start() -> AVCaptureSession? {
        guard terminal == nil else { return nil }
        if let signText {
            do {
                let pending = try sdk.reviewQrSignRequest(signText)
                reviewOperation = pending
                pending.observe { [self] outcome in
                    Task { @MainActor [self] in
                        self.reviewOperation = nil
                        switch outcome {
                        case let .success(value):
                            if self.terminal != nil { value.release() }
                            else { self.review = value; self.onReview?(value.text) }
                        case let .failure(error): self.end(.failure(error))
                        }
                        self.drain()
                    }
                }
            } catch { end(.failure(error)) }
            return nil
        }
        let camera = CitizenSDKQrCapture(frame: { [weak self, sdk] bytes, width, height, stride in
            do {
                let document = try sdk.qrDecodeLuminance(bytes, width: width, height: height, rowStride: stride)
                Task { @MainActor [weak self] in self?.end(.success(document)) }
            } catch let error as CitizenSDKError where error.code == .notFound {
                // 没有码是正常视频帧；多个码、损坏协议或不支持类型必须准确失败，不能旁路解析。
            } catch {
                Task { @MainActor [weak self] in self?.end(.failure(error)) }
            }
        }, failure: { [weak self] error in
            Task { @MainActor [weak self] in self?.end(.failure(error)) }
        })
        capture = camera; captureDrained = false
        camera.start()
        return camera.session
    }

    func confirm() {
        guard terminal == nil, !confirmed, let review else { return }
        confirmed = true
        do {
            let pending = try sdk.signQrReview(review)
            self.review = nil
            signOperation = pending
            pending.observe { [self] outcome in
                Task { @MainActor [self] in
                    self.signOperation = nil
                    if self.terminal == nil {
                        self.end(outcome.flatMap { document in Result {
                            var value = document
                            value.signedImage = try self.sdk.qrEncode(document.canonicalText)
                            return value
                        } })
                    }
                    self.drain()
                }
            }
        } catch { end(.failure(error)) }
    }

    func cancel() { end(.failure(CitizenSDKError(.cancelled, "扫码或签名窗口已关闭"))) }

    private func end(_ outcome: Result<CitizenQRDocument, Error>) {
        guard terminal == nil else { drain(); return }
        terminal = outcome
        onClear?()
        review?.release(); review = nil
        _ = try? reviewOperation?.cancel()
        _ = try? signOperation?.cancel()
        if let capture {
            self.capture = nil
            capture.close { [self] in
                Task { @MainActor [self] in self.captureDrained = true; self.drain() }
            }
        }
        drain()
    }

    private func drain() {
        guard let terminal, captureDrained, reviewOperation == nil, signOperation == nil, !delivering else { return }
        delivering = true
        let complete = { [self] in
            CitizenSDKWalletFlowRegistry.shared.finish(sdk, token: reservation)
            operation.complete(terminal)
            onReview = nil; onClear = nil; onDismiss = nil
        }
        if let onDismiss { onDismiss(complete) } else { complete() }
    }
}

#if os(iOS)
import UIKit

public extension CitizenSdk {
    /// SDK 自有相机窗口；调用方不提供识别器或协议解析器，也不需要钱包、金库或轻节点。
    @MainActor
    func qrScan(from presenter: UIViewController) throws -> CitizenSDKOperation<CitizenQRDocument> {
        try presentQr(from: presenter, signText: nil)
    }

    /// 完整展示 Core 审阅内容；用户确认后只消费该一次性凭证并执行真实安全签名。
    @MainActor
    func signQrRequest(from presenter: UIViewController, text: String) throws -> CitizenSDKOperation<CitizenQRSigned> {
        try signedQrOperation(presentQr(from: presenter, signText: text))
    }

    @MainActor
    private func presentQr(from presenter: UIViewController, signText: String?) throws -> CitizenSDKOperation<CitizenQRDocument> {
        guard presenter.viewIfLoaded?.window != nil, UIApplication.shared.applicationState == .active else {
            throw CitizenSDKError(.unavailable, "扫码签名需要前台窗口")
        }
        let flow = try CitizenSDKQrFlow(sdk: self, signText: signText)
        let controller = CitizenSDKQrControllerIOS(flow: flow)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet; navigation.isModalInPresentation = true
        presenter.present(navigation, animated: true)
        return flow.operation
    }
}

@MainActor
private final class CitizenSDKQrControllerIOS: UIViewController {
    private let flow: CitizenSDKQrFlow
    private let text = UITextView()
    private let confirm = UIButton(type: .system)
    private let preview = AVCaptureVideoPreviewLayer()
    private var tokens: [NSObjectProtocol] = []
    private var started = false
    private var ending = false
    init(flow: CitizenSDKQrFlow) { self.flow = flow; super.init(nibName: nil, bundle: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        title = flow.signText == nil ? "扫描二维码" : "审阅并签名"
        text.isEditable = false; text.isSelectable = false
        text.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        text.text = flow.signText == nil ? "正在打开相机…" : "正在核验已终结链元数据…"
        confirm.setTitle("我已核对完整内容，确认签名", for: .normal)
        confirm.isHidden = true; confirm.addTarget(self, action: #selector(confirmed), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [text, confirm]); stack.axis = .vertical; stack.spacing = 12
        view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelled))
        preview.videoGravity = .resizeAspectFill; view.layer.insertSublayer(preview, at: 0)
        flow.onReview = { [weak self] value in self?.text.text = value; self?.confirm.isHidden = false }
        flow.onClear = { [weak self] in
            self?.ending = true; self?.text.text = "正在安全关闭…"; self?.confirm.isEnabled = false
            self?.preview.isHidden = true
        }
        flow.onDismiss = { [weak self] complete in
            guard let self else { complete(); return }
            self.tokens.forEach(NotificationCenter.default.removeObserver); self.tokens.removeAll()
            self.preview.session = nil
            if self.presentingViewController != nil { self.dismiss(animated: false, completion: complete) }
            else { complete() }
        }
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.text.isHidden = true; self.preview.isHidden = true
                // 相机授权和已确认后的系统认证允许临时失焦；真实后台始终结束。
                if self.flow.signText != nil {
                    if !self.flow.confirmed { self.flow.cancel() }
                } else if AVCaptureDevice.authorizationStatus(for: .video) != .notDetermined {
                    self.flow.cancel()
                }
            }
        })
        tokens.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.ending else { return }
                self.text.isHidden = self.flow.signText == nil; self.preview.isHidden = false
            }
        })
        tokens.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flow.cancel() }
        })
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }; started = true
        preview.session = flow.start()
        text.isHidden = flow.signText == nil
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview.frame = view.bounds }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !ending { flow.cancel() }
    }
    @objc private func confirmed() { confirm.isEnabled = false; flow.confirm() }
    @objc private func cancelled() { flow.cancel() }
}
#elseif os(macOS)
import AppKit

public extension CitizenSdk {
    @MainActor
    func qrScan(from window: NSWindow) throws -> CitizenSDKOperation<CitizenQRDocument> {
        try presentQr(from: window, signText: nil)
    }
    @MainActor
    func signQrRequest(from window: NSWindow, text: String) throws -> CitizenSDKOperation<CitizenQRSigned> {
        try signedQrOperation(presentQr(from: window, signText: text))
    }
    @MainActor
    private func presentQr(from window: NSWindow, signText: String?) throws -> CitizenSDKOperation<CitizenQRDocument> {
        guard NSApp.isActive, window.isVisible, window.attachedSheet == nil else {
            throw CitizenSDKError(.unavailable, "扫码签名需要空闲前台窗口")
        }
        let flow = try CitizenSDKQrFlow(sdk: self, signText: signText)
        let controller = CitizenSDKQrControllerMacOS(flow: flow, parent: window)
        controller.present()
        return flow.operation
    }
}

@MainActor
private final class CitizenSDKQrControllerMacOS: NSViewController, NSWindowDelegate {
    private let flow: CitizenSDKQrFlow
    private weak var parentWindow: NSWindow?
    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 620), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private let text = NSTextView()
    private let confirm = NSButton(title: "我已核对完整内容，确认签名", target: nil, action: nil)
    private let preview = AVCaptureVideoPreviewLayer()
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var ending = false
    init(flow: CitizenSDKQrFlow, parent: NSWindow) {
        self.flow = flow; parentWindow = parent
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 620)); view.wantsLayer = true
        preview.videoGravity = .resizeAspectFill; view.layer?.addSublayer(preview)
        text.isEditable = false; text.isSelectable = false; text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        text.string = flow.signText == nil ? "正在打开相机…" : "正在核验已终结链元数据…"
        let scroll = NSScrollView(); scroll.documentView = text; scroll.hasVerticalScroller = true
        text.autoresizingMask = [.width]; text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        confirm.target = self; confirm.action = #selector(confirmed); confirm.isHidden = true
        let cancel = NSButton(title: "取消并关闭", target: self, action: #selector(cancelled))
        let buttons = NSStackView(views: [confirm, cancel]); buttons.orientation = .horizontal
        let stack = NSStackView(views: [scroll, buttons]); stack.orientation = .vertical; stack.spacing = 12
        view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        if flow.signText == nil { scroll.isHidden = true }
    }
    func present() {
        panel.contentViewController = self; panel.delegate = self; panel.sharingType = .none
        panel.title = flow.signText == nil ? "扫描二维码" : "审阅并签名"
        flow.onReview = { [weak self] value in self?.text.string = value; self?.confirm.isHidden = false }
        flow.onClear = { [weak self] in
            self?.ending = true; self?.text.string = "正在安全关闭…"; self?.confirm.isEnabled = false; self?.preview.isHidden = true
        }
        flow.onDismiss = { [self] complete in
            tokens.forEach { $0.0.removeObserver($0.1) }; tokens.removeAll()
            preview.session = nil
            if let parentWindow { parentWindow.endSheet(panel) }
            panel.orderOut(nil); panel.contentViewController = nil
            complete()
        }
        observe(NotificationCenter.default, NSApplication.didResignActiveNotification) { [weak self] in
            guard let self else { return }
            self.preview.isHidden = true; self.text.isHidden = true
            if self.flow.signText != nil {
                if !self.flow.confirmed { self.flow.cancel() }
            } else if AVCaptureDevice.authorizationStatus(for: .video) != .notDetermined {
                self.flow.cancel()
            }
        }
        observe(NotificationCenter.default, NSApplication.didBecomeActiveNotification) { [weak self] in
            guard let self, !self.ending else { return }; self.preview.isHidden = false; self.text.isHidden = false
        }
        observe(NotificationCenter.default, NSApplication.didHideNotification) { [weak self] in self?.flow.cancel() }
        observe(NotificationCenter.default, NSWindow.willCloseNotification, object: parentWindow) { [weak self] in self?.flow.cancel() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.flow.cancel() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.flow.cancel() }
        tokens.append((NSWorkspace.shared.notificationCenter, NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notice in
            let other = notice.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                // 只有切到另一个正常应用才算真正后台；认证代理短暂抢焦点不等于离开应用。
                if let other, other.processIdentifier != ProcessInfo.processInfo.processIdentifier, other.activationPolicy == .regular { self?.flow.cancel() }
            }
        }))
        parentWindow?.beginSheet(panel)
        preview.session = flow.start()
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: Any? = nil,
                         _ action: @escaping @MainActor @Sendable () -> Void) {
        tokens.append((center, center.addObserver(forName: name, object: object, queue: .main) { _ in MainActor.assumeIsolated { action() } }))
    }
    override func viewDidLayout() { super.viewDidLayout(); preview.frame = view.bounds }
    func windowShouldClose(_ sender: NSWindow) -> Bool { flow.cancel(); return false }
    @objc private func confirmed() { confirm.isEnabled = false; flow.confirm() }
    @objc private func cancelled() { flow.cancel() }
}
#endif

internal extension CitizenSdk {
    func signedQrOperation(_ source: CitizenSDKOperation<CitizenQRDocument>) -> CitizenSDKOperation<CitizenQRSigned> {
        let target = CitizenSDKOperation<CitizenQRSigned>(operationID: source.operationID, cancel: source.cancel)
        source.observe { outcome in
            target.complete(outcome.flatMap { document in
                Result {
                    guard let image = document.signedImage else { throw CitizenSDKError(.integrity, "签名二维码结果缺失") }
                    return CitizenQRSigned(document: document, qrImage: image)
                }
            })
        }
        return target
    }
}
