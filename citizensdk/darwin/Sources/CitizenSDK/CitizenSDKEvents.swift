import Foundation

public enum CitizenSDKEvent: Equatable, Sendable {
    /// Invalidation only; read the latest state with the existing history API.
    case historyChanged(sequence: UInt64)
    case finalizedBlockChanged(sequence: UInt64, finalized: CitizenBlockRef)
    case lifecycleChanged(sequence: UInt64, lifecycle: CitizenSDKLifecycle)
    case capabilitiesChanged(sequence: UInt64, capabilities: CitizenSDKCapabilities)
}
