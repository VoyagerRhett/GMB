# Archived smoldot Dart baseline build boundary

This directory documents the Dart/smoldot implementation copied from the
verified CitizenApp baseline. It is retained for source provenance,
differential tests and migration review. It is **not** an independently
published package, a public CitizenSDK API, or a second native build flow.

## Canonical product build

CitizenSDK has one native build entry point:

```text
/Users/rhett/GMB/citizensdk/scripts/build-native.sh
```

Local callers must provide both `CITIZENSDK_WORK_DIR` and
`CITIZENSDK_NATIVE_OUTPUT_DIR` as absolute descendants of:

```text
CITIZENSDK_NATIVE_OUTPUT_DIR
```

The script also places `CARGO_TARGET_DIR`, module caches, Gradle state,
DerivedData-equivalent state, staging frameworks and candidate outputs below
that controlled work root. Nothing generated may be written below
`/Users/rhett/GMB/citizensdk`.

Do not run ad-hoc `cargo build`, copy libraries into this documentation tree,
or restore the retired `native/{platform}` output layout. 调用方 and the
repository workflows call the same product script; no smoldot-only build or
release path exists.

## Current mobile and Apple target contract

The current public platform names and compiler targets are exact:

| Platform | Technical variant | Rust target | Purpose |
|---|---|---|---|
| Android | ABI `arm64-v8a` | `aarch64-linux-android` | Product Core and JNI/AAR projection |
| iOS | device | `aarch64-apple-ios` | Physical iPhone/iPad device ABI |
| iOS | simulator | `aarch64-apple-ios-sim` | Apple-silicon Simulator ABI |
| macOS | machine value `arm64` | `aarch64-apple-darwin` | Product ABI |

The two iOS slices both use Apple machine architecture value `arm64` but have
different Apple platform ABIs and SDKs. They therefore remain separate
XCFramework technical variants while sharing the single public platform name
`iOS`. The macOS product name is always `macOS`; it has no architecture suffix.

`CitizenSDK.xcframework` contains the iOS device and simulator variants plus
macOS. The two iOS variants use a shallow framework with install ID
`@rpath/CitizenSDK.framework/CitizenSDK`; macOS uses the standard `Versions/A`
framework with install ID
`@rpath/CitizenSDK.framework/Versions/A/CitizenSDK`. Only the five canonical
relative links required by that macOS framework are permitted in a candidate.
The framework carries the public C headers, the Swift module, the one Rust
CitizenSDK Core, the three verified `citizenchain` assets and the privacy
manifest. A legacy `libsmoldot.dylib` may be built under the central work root
only for Dart differential tests; it is a macOS test binary with machine value
`arm64`, is not a product ABI and
must never enter a CitizenSDK candidate.

LinuxARM, LinuxAMD and Windows official projections are implemented only in their later
task-card steps. This archived document does not claim that they are already
available.

## Verification boundary

The canonical script and release verifier must reject:

- any generated file or cache in the CitizenSDK source tree;
- any Apple slice other than the three listed above;
- any macOS x86 or universal binary;
- a product framework that leaks legacy `smoldot_*`, signer, dependency or
  other non-CitizenSDK symbols;
- chain assets that differ from `assets/citizenchain`;
- a Flutter/Hosted package that exposes this archived implementation as a
  runtime import path.

Source format, unit, contract, differential and consumer tests use temporary
copies and target directories below 调用方's central CitizenSDK work
root. CI and Release execution remain separate task-card steps; this document
does not authorize either operation.
