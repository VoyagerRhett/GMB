import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var blurView: UIVisualEffectView?
  private var screenshotProtectionEnabled = false
  // 产品专用原生通道由 AppDelegate 强引用；钱包严档由共享 Flutter 插件自动注册。
  private var deviceSubkeyChannel: DeviceSubkeyChannel?
  private var deviceDataKeyVaultChannel: DeviceDataKeyVaultChannel?
  private var securityChannel: FlutterMethodChannel?
  private var permissionsChannel: FlutterMethodChannel?
  private var chatNotificationsChannel: FlutterMethodChannel?
  private var squareMediaChannel: SquareMediaChannel?
  private var updateChannel: FlutterMethodChannel?
  private var emergencyWipeBackgroundTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appWillResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )

    return result
  }



  /// 非 Scene 生命周期下接收钱包回跳。WalletConnect 的响应继续走 Relay，本 URL 只负责
  /// 把仍持有 WebView provider 会话的 CitizenApp 拉回前台，不能再推一张 Flutter 路由。
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if Self.isWalletConnectCallback(url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // UIScene 模式下 AppDelegate.window 在启动回调中尚未建立；必须使用 engine
    // 提供的 application registrar 注册通道，确保 iOS 16+ 首次启动也必然可用。
    registerApplicationChannels(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
  }

  private func registerApplicationChannels(binaryMessenger: FlutterBinaryMessenger) {
    deviceSubkeyChannel = DeviceSubkeyChannel(binaryMessenger: binaryMessenger)
    deviceDataKeyVaultChannel = DeviceDataKeyVaultChannel(binaryMessenger: binaryMessenger)
    squareMediaChannel = SquareMediaChannel(binaryMessenger: binaryMessenger)

    let securityChannel = FlutterMethodChannel(
      name: "citizenapp/security",
      binaryMessenger: binaryMessenger
    )
    securityChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "enableScreenshotProtection":
        self?.screenshotProtectionEnabled = true
        result(nil)
      case "disableScreenshotProtection":
        self?.screenshotProtectionEnabled = false
        self?.removeBlur()
        result(nil)
      case "beginEmergencyWipe":
        self?.beginEmergencyWipeBackgroundTask()
        result(nil)
      case "finishEmergencyWipe":
        self?.endEmergencyWipeBackgroundTask()
        result(nil)
      case "isDeviceRooted":
        result(AppDelegate.checkJailbreak())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.securityChannel = securityChannel

    let permissionsChannel = FlutterMethodChannel(
      name: "citizenapp/permissions",
      binaryMessenger: binaryMessenger
    )
    permissionsChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestNotificationPermission":
        // iOS 通知授权必须由 App 主动发起，拒绝后不阻塞进入主界面。
        UNUserNotificationCenter.current().requestAuthorization(
          options: [.alert, .badge, .sound]
        ) { granted, error in
          DispatchQueue.main.async {
            if let error = error {
              result(
                FlutterError(
                  code: "NOTIFICATION_PERMISSION_FAILED",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            } else {
              result(granted)
            }
          }
        }
      case "getNotificationPermissionStatus":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          let granted = settings.authorizationStatus == .authorized ||
            settings.authorizationStatus == .provisional
          DispatchQueue.main.async {
            result(granted)
          }
        }
      case "getApnsEnvironment":
        // APNs Token 的环境由最终 provisioning profile 决定，不能读取构建设置镜像，
        // 也不能根据 Debug/Release 名称或 Dart 参数猜测。App Store/TestFlight 会移除
        // embedded.mobileprovision，此时仅在真实收据存在时按 production 登记。
        do {
          result(try Self.currentApnsEnvironment())
        } catch {
          result(
            FlutterError(
              code: "APNS_ENVIRONMENT_INVALID",
              message: "当前应用签名配置缺少有效 APNs 环境",
              details: nil
            )
          )
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.permissionsChannel = permissionsChannel

    let chatNotificationsChannel = FlutterMethodChannel(
      name: "citizenapp/chat_notifications",
      binaryMessenger: binaryMessenger
    )
    chatNotificationsChannel.setMethodCallHandler { call, result in
      guard call.method == "clearConversationNotifications" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let conversationId = arguments["conversationId"] as? String,
        !conversationId.isEmpty
      else {
        result(
          FlutterError(
            code: "INVALID_CONVERSATION_ID",
            message: "聊天通知缺少会话标识",
            details: nil
          )
        )
        return
      }
      Self.clearDeliveredChatNotifications(
        conversationId: conversationId,
        result: result
      )
    }
    self.chatNotificationsChannel = chatNotificationsChannel

    let updateChannel = FlutterMethodChannel(
      name: "citizenapp/update",
      binaryMessenger: binaryMessenger
    )
    updateChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "getPackageInfo":
        result(
          AppDelegate.packageInfo(
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            bundleIdentifier: Bundle.main.bundleIdentifier ?? ""
          )
        )
      default:
        // APK 安装只属于 Android；iOS 更新通道只公开本机版本。
        result(FlutterMethodNotImplemented)
      }
    }
    self.updateChannel = updateChannel
  }

  /// iOS 不允许应用自行退出后无限运行；这里只申请系统提供的有限后台时间。
  /// 时间耗尽或进程终止后，已经落盘的 pending 门闩会在下次启动前继续擦除。
  private func beginEmergencyWipeBackgroundTask() {
    guard emergencyWipeBackgroundTask == .invalid else { return }
    emergencyWipeBackgroundTask = UIApplication.shared.beginBackgroundTask(
      withName: "EmergencyDataWipe"
    ) { [weak self] in
      self?.endEmergencyWipeBackgroundTask()
    }
  }

  private func endEmergencyWipeBackgroundTask() {
    guard emergencyWipeBackgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(emergencyWipeBackgroundTask)
    emergencyWipeBackgroundTask = .invalid
  }

  /// APNs 使用既有 conversation_id 作为 threadIdentifier；查看会话后只删除该线程，
  /// 不调用 removeAllDeliveredNotifications，避免误清其它聊天和广场通知。
  private static func clearDeliveredChatNotifications(
    conversationId: String,
    result: @escaping FlutterResult
  ) {
    let center = UNUserNotificationCenter.current()
    center.getDeliveredNotifications { notifications in
      let identifiers = notifications.compactMap { notification -> String? in
        let content = notification.request.content
        let payloadConversation = content.userInfo["conversation_id"] as? String
        return content.threadIdentifier == conversationId ||
          payloadConversation == conversationId
          ? notification.request.identifier
          : nil
      }
      center.removeDeliveredNotifications(withIdentifiers: identifiers)
      DispatchQueue.main.async { result(nil) }
    }
  }

  static func currentApnsEnvironment(
    bundle: Bundle = .main,
    fileManager: FileManager = .default
  ) throws -> String {
    let profileURL = bundle.url(
      forResource: "embedded",
      withExtension: "mobileprovision"
    )
    let profileData: Data?
    if let profileURL = profileURL {
      // 文件存在但无法读取时必须失败关闭，不能退化成 production。
      profileData = try Data(contentsOf: profileURL)
    } else {
      profileData = nil
    }
    let hasAppStoreReceipt = bundle.appStoreReceiptURL.map {
      fileManager.fileExists(atPath: $0.path)
    } ?? false
    return try apnsEnvironment(
      provisioningProfileData: profileData,
      hasAppStoreReceipt: hasAppStoreReceipt
    )
  }

  static func apnsEnvironment(
    provisioningProfileData: Data?,
    hasAppStoreReceipt: Bool
  ) throws -> String {
    guard let provisioningProfileData = provisioningProfileData else {
      guard hasAppStoreReceipt else {
        throw NSError(domain: "citizenapp.apns_environment", code: 1)
      }
      return "production"
    }

    let plistStartMarker = Data("<plist".utf8)
    let plistEndMarker = Data("</plist>".utf8)
    guard
      let plistStart = provisioningProfileData.range(of: plistStartMarker)?.lowerBound,
      let plistEnd = provisioningProfileData.range(
        of: plistEndMarker,
        in: plistStart..<provisioningProfileData.endIndex
      )?.upperBound
    else {
      throw NSError(domain: "citizenapp.apns_environment", code: 2)
    }

    let plistData = Data(provisioningProfileData[plistStart..<plistEnd])
    guard
      let profile = try PropertyListSerialization.propertyList(
        from: plistData,
        options: [],
        format: nil
      ) as? [String: Any],
      let entitlements = profile["Entitlements"] as? [String: Any],
      let entitlement = entitlements["aps-environment"] as? String
    else {
      throw NSError(domain: "citizenapp.apns_environment", code: 3)
    }

    switch entitlement {
    case "development":
      return "sandbox"
    case "production":
      return "production"
    default:
      throw NSError(domain: "citizenapp.apns_environment", code: 4)
    }
  }

  @objc private func appWillResignActive() {
    guard screenshotProtectionEnabled else { return }
    addBlur()
  }

  @objc private func appDidBecomeActive() {
    removeBlur()
  }

  private func addBlur() {
    guard blurView == nil, let keyWindow = window else { return }
    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .light))
    blur.frame = keyWindow.bounds
    blur.tag = 999
    keyWindow.addSubview(blur)
    blurView = blur
  }

  private func removeBlur() {
    blurView?.removeFromSuperview()
    blurView = nil
  }

  private static func checkJailbreak() -> Bool {
    #if targetEnvironment(simulator)
    return false
    #else
    let paths = [
      "/Applications/Cydia.app",
      "/Library/MobileSubstrate/MobileSubstrate.dylib",
      "/bin/bash", "/usr/sbin/sshd", "/etc/apt",
      "/private/var/lib/apt/",
      "/usr/bin/ssh",
      "/var/lib/cydia",
      "/var/cache/apt",
      "/var/jb",
    ]
    for path in paths {
      if FileManager.default.fileExists(atPath: path) { return true }
    }
    let testPath = "/private/jailbreak_test_\(UUID().uuidString)"
    do {
      try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
      try FileManager.default.removeItem(atPath: testPath)
      return true
    } catch {
      return false
    }
    #endif
  }

  static func isWalletConnectCallback(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "citizenapp" &&
      url.host?.lowercased() == "walletconnect"
  }

  /// 把 iOS 安装包版本整理成与 Android `getPackageInfo` 相同的跨端结构。
  static func packageInfo(
    infoDictionary: [String: Any],
    bundleIdentifier: String
  ) -> [String: Any] {
    let versionName = infoDictionary["CFBundleShortVersionString"] as? String ?? ""
    let buildText = infoDictionary["CFBundleVersion"] as? String ?? "0"
    return [
      "packageName": bundleIdentifier,
      "versionName": versionName,
      "versionCode": Int(buildText) ?? 0,
    ]
  }
}
