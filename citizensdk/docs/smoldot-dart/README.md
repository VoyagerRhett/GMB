# Archived Dart/smoldot implementation

The files beside this README are a source-preserved Dart wrapper around the
smoldot baseline copied from CitizenApp. CitizenSDK keeps them for provenance,
behavioral comparison and migration tests only.

They are not the CitizenSDK public API and are not published as a package named
`smoldot`. Applications use the typed API exported by:

```dart
import 'package:citizen_sdk/citizen_sdk.dart';
```

## Product boundary

The production dependency direction is fixed:

```text
Dart / Swift / Kotlin / C consumer
              -> stable citizensdk_* C ABI
              -> CitizenSDK Core Engine
              -> VerifiedChainClient
              -> smoldot provider
              -> CitizenChain
```

The public SDK deliberately does not expose this wrapper's arbitrary
`request(method, params)` JSON-RPC surface, raw smoldot handles, low-level
subscriptions or direct native symbols. Chain reads, wallet actions,
transactions, history, capabilities and events are available only through the
typed CitizenSDK contracts. Wallet secrets and sr25519 material remain inside
the Rust/platform vault boundary and never cross the Flutter channel.

The Hosted package excludes this whole archived directory through
`.pubignore`. Keeping the source in the GitHub audit candidate does not make it
a supported implementation import or a second runtime.

## Supported product projections at this task stage

- Android through the Kotlin/Java API, Flutter adapter and AAR; current ABI is
  `arm64-v8a`.
- iOS device variant through the Swift API, Flutter adapter and
  `CitizenSDK.xcframework`.
- iOS simulator variant as a separate Apple ABI slice for compile and simulator
  integration; device-only vault/biometric claims still require real hardware.
- macOS through the same Swift source and XCFramework. The product name is
  simply `macOS`; the current Apple machine architecture value is `arm64`.

LinuxARM, LinuxAMD and Windows official projections are intentionally deferred to their
task-card steps. The presence of portable Rust or archived Dart source is not
evidence that those product projections have already shipped.

## Build and test use

All official native builds use `scripts/build-native.sh`. All local build,
test, cache, generated and candidate state must stay below:

```text
CITIZENSDK_NATIVE_OUTPUT_DIR
```

See `BUILD.md` for the exact current target matrix and output boundary. Do not
copy generated libraries into this directory or create a smoldot-only release
flow.

Differential tests may load a centrally built macOS `arm64` legacy host library
to compare the copied baseline with the product Core. That library is a test
fixture only: it is excluded from the Apple product framework, Hosted runtime
closure and formal CitizenSDK release artifacts.
