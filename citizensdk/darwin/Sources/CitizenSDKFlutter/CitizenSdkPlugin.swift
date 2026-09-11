#if os(iOS)
@preconcurrency import Flutter
import UIKit
#elseif os(macOS)
import AppKit
@preconcurrency import FlutterMacOS
#endif

/// Flutter registration for the shared, secret-free CitizenSDK protocol v1.
@MainActor
public final class CitizenSdkPlugin: NSObject, @preconcurrency FlutterPlugin {
    private let sessions = CitizenSdkFlutterSessions()
    private let detachCoordinator = CitizenSdkFlutterDetachCoordinator()
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?

    /// Flutter's generated iOS/macOS registrants expose a synchronous,
    /// nonisolated function. Engine registration is nevertheless a main-actor
    /// operation because messenger/channel/delegate objects are UI-thread
    /// confined. `assumeIsolated` preserves synchronous completion and traps a
    /// host that violates Flutter's main-thread registration contract; using an
    /// asynchronous Task here would return before handlers were installed.
    public nonisolated static func register(with registrar: FlutterPluginRegistrar) {
        MainActor.assumeIsolated {
            registerOnMainActor(with: registrar)
        }
    }

    private static func registerOnMainActor(with registrar: FlutterPluginRegistrar) {
        #if os(iOS)
        let messenger = registrar.messenger()
        #elseif os(macOS)
        let messenger = registrar.messenger
        #endif
        let instance = CitizenSdkPlugin()
        let method = FlutterMethodChannel(name: CitizenSdkFlutterCodec.methodChannel, binaryMessenger: messenger)
        let events = FlutterEventChannel(name: CitizenSdkFlutterCodec.eventChannel, binaryMessenger: messenger)
        instance.methodChannel = method
        instance.eventChannel = events
        registrar.addMethodCallDelegate(instance, channel: method)
        events.setStreamHandler(instance.sessions)
        // iOS invokes detachFromEngine(for:) only for published instances.
        // FlutterMacOS also retains the published value until engine shutdown;
        // current macOS hosts may call the same explicit teardown entry point.
        registrar.publish(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            sessions.dispatch(try CitizenSdkFlutterCodec.decode(method: call.method, arguments: call.arguments), result: result)
        } catch let failure as CitizenSdkFlutterCodec.ContractFailure {
            result(FlutterError(
                code: "citizensdk.\(CitizenSdkFlutterCodec.errorName(failure.code))",
                message: failure.message,
                details: CitizenSdkFlutterCodec.error(failure.code, failure.message,
                                                      session: failure.session, sequence: failure.sequence,
                                                      method: call.method, stage: failure.stage)
            ))
        } catch {
            result(FlutterError(code: "citizensdk.internal", message: "CitizenSDK Flutter request decoding failed",
                                details: CitizenSdkFlutterCodec.error(.internalFailure,
                                    "CitizenSDK Flutter request decoding failed", session: nil, sequence: nil,
                                    method: call.method)))
        }
    }

    /// Official iOS engine-detach callback and the shared explicit Darwin
    /// teardown entry point. FlutterMacOS currently does not declare this
    /// callback in its registrar protocol, but publishing the instance gives a
    /// native host access to this same idempotent entry point before shutdown.
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        beginDetach()
    }

    private func beginDetach() {
        let method = methodChannel
        let events = eventChannel
        let sdkSessions = sessions
        guard detachCoordinator.begin(
            revokeMethodHandler: { method?.setMethodCallHandler(nil) },
            revokeEventHandler: { events?.setStreamHandler(nil) },
            invalidateEventEpoch: { sdkSessions.invalidateEventEpochForDetach() }
        ) else { return }

        methodChannel = nil
        eventChannel = nil
        Task { @MainActor in
            sdkSessions.detachEventSink()
            await sdkSessions.closeAll()
        }
    }

    isolated deinit {
        // A conforming iOS engine calls detach explicitly. The bundled
        // FlutterMacOS API has no registrar detach callback, so deinit remains
        // its final safety net.
        // The coordinator makes this harmless after an explicit teardown.
        beginDetach()
    }
}
