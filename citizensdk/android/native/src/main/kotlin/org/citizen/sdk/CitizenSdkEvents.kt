package org.citizen.sdk

/** Non-secret Core events emitted on one ordered executor. */
object CitizenSdkEvents {
    sealed class Event(open val sequence: String) {
        /** Invalidation only; query the existing history API for the current state. */
        class HistoryChanged(override val sequence: String) : Event(sequence)
        class FinalizedBlockChanged(
            override val sequence: String,
            val finalized: CitizenBlockRef,
        ) : Event(sequence)
        class LifecycleChanged(
            override val sequence: String,
            val lifecycle: CitizenSdkLifecycle,
        ) : Event(sequence)

        /** Carries the complete snapshot; consumers never race a follow-up query. */
        class CapabilitiesChanged(
            override val sequence: String,
            val capabilities: CitizenSdkCapabilities,
        ) : Event(sequence)

    }

    fun interface Listener {
        fun onEvent(event: Event)
    }

}
