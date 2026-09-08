import Foundation

internal struct CitizenSDKAssets {
    let manifest: Data
    let chainSpec: Data
    let lightSyncState: Data

    static func load(bundle: Bundle = Bundle(for: CitizenSDKBundleMarker.self)) throws -> CitizenSDKAssets {
        // The candidate builder projects the canonical root assets into one
        // `citizenchain` resource directory. It never creates root-level
        // copies or a second asset source of truth.
        let roots = [
            bundle.resourceURL?.appendingPathComponent("citizenchain", isDirectory: true),
            bundle.resourceURL?.appendingPathComponent("Resources/citizenchain", isDirectory: true),
            bundle.resourceURL?
                .appendingPathComponent("CitizenSDKResources.bundle", isDirectory: true)
                .appendingPathComponent("citizenchain", isDirectory: true),
        ].compactMap { $0 }

        func read(_ name: String) throws -> Data {
            guard let url = roots.lazy.map({ $0.appendingPathComponent(name) }).first(where: {
                FileManager.default.fileExists(atPath: $0.path)
            }) else {
                throw CitizenSDKError(.integrity, "CitizenSDK resource \(name) is missing")
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard !data.isEmpty else { throw CitizenSDKError(.integrity, "CitizenSDK resource \(name) is empty") }
            return data
        }

        // Asset identity, genesis binding and all manifest hashes are
        // revalidated by Rust during `citizensdk_create_with_modules`; Swift only
        // locates and supplies the exact packaged bytes.
        return try CitizenSDKAssets(
            manifest: read("manifest.json"),
            chainSpec: read("chainspec.json"),
            lightSyncState: read("light_sync_state.json")
        )
    }
}

private final class CitizenSDKBundleMarker: NSObject {}
