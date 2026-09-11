package org.citizen.sdk

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test
import java.util.concurrent.CompletableFuture

class CitizenSdkFlutterSessionsTest {
    @Test
    fun `verification projection needs no context session activity or event subscription`() {
        val request = CitizenSdkFlutterCodec.decode("verifySignature",
            listOf(1, "0x" + "11".repeat(32), ByteArray(64), byteArrayOf())) as CitizenSdkFlutterCodec.Request.VerifySignature
        var calls = 0
        // 只替换密码学叶节点；生产使用同一静态分派，测试无需构造任何 Android 宿主。
        repeat(2) {
            val response = CitizenSdkFlutterSessions.verifySignature(request) { account, signature, payload ->
                calls++
                assertEquals(32, account.size)
                assertEquals(64, signature.size)
                assertTrue(payload.isEmpty())
                false
            }
            assertEquals(listOf(1, false), response)
        }
        assertEquals(2, calls)
        assertThrows(CitizenSdkException::class.java) {
            CitizenSdkFlutterSessions.verifySignature(request) { _, _, _ ->
                throw CitizenSdkException(CitizenSdkErrorCode.INTEGRITY, "fixture")
            }
        }
    }

    @Test
    fun `request sequence is strictly contiguous and never advances on rejection`() {
        val gate = CitizenSdkFlutterSequenceGate()
        assertFalse(gate.accept(2))
        assertTrue(gate.accept(1))
        assertFalse(gate.accept(1))
        assertFalse(gate.accept(3))
        assertTrue(gate.accept(2))
        assertTrue(gate.accept(3))
    }

    @Test
    fun `queued event token cannot cross cancel and relisten generation`() {
        val gate = CitizenSdkFlutterSubscriptionGate<Any>()
        val firstSink = Any()
        val first = checkNotNull(gate.open(firstSink))
        assertTrue(gate.owns(first))
        assertNull(gate.open(Any()))

        gate.close()
        val secondSink = Any()
        val second = checkNotNull(gate.open(secondSink))
        assertFalse(gate.owns(first))
        assertTrue(gate.owns(second))
    }

    @Test
    fun `supervised close stops only a running provider`() {
        assertEquals(
            CitizenSdkFlutterCloseAction.STOP_THEN_CLOSE,
            citizenSdkFlutterCloseAction(CitizenSdkLifecycle.RUNNING),
        )
        for (lifecycle in listOf(
            CitizenSdkLifecycle.CREATED,
            CitizenSdkLifecycle.STOPPED,
            CitizenSdkLifecycle.START_FAILED,
            CitizenSdkLifecycle.DISPOSED,
        )) {
            assertEquals(CitizenSdkFlutterCloseAction.CLOSE, citizenSdkFlutterCloseAction(lifecycle))
        }
        for (lifecycle in listOf(
            CitizenSdkLifecycle.STARTING,
            CitizenSdkLifecycle.IMPORTING_STATE,
        )) {
            assertEquals(
                CitizenSdkFlutterCloseAction.REJECT_UNSTABLE,
                citizenSdkFlutterCloseAction(lifecycle),
            )
        }
    }

    @Test
    fun `running close checkpoints before dispose and stop failure never disposes`() {
        val stop = CompletableFuture<Void>()
        var disposeCount = 0
        val close = citizenSdkFlutterCloseLifecycle(
            CitizenSdkLifecycle.RUNNING,
            { stop },
            { disposeCount++ },
        )
        assertFalse(close.isDone)
        assertEquals(0, disposeCount)

        stop.complete(null)
        assertTrue(close.isDone)
        assertFalse(close.isCompletedExceptionally)
        assertEquals(1, disposeCount)

        var failedDisposeCount = 0
        val failed = citizenSdkFlutterCloseLifecycle(
            CitizenSdkLifecycle.RUNNING,
            { failedFuture(IllegalStateException("checkpoint failed")) },
            { failedDisposeCount++ },
        )
        assertTrue(failed.isCompletedExceptionally)
        assertEquals(0, failedDisposeCount)
    }

    @Test
    fun `start failed disposes without stop while unstable lifecycle fails closed`() {
        var stopCount = 0
        var disposeCount = 0
        val startFailed = citizenSdkFlutterCloseLifecycle(
            CitizenSdkLifecycle.START_FAILED,
            { stopCount++; CompletableFuture.completedFuture(null) },
            { disposeCount++ },
        )
        assertTrue(startFailed.isDone)
        assertEquals(0, stopCount)
        assertEquals(1, disposeCount)

        val unstable = citizenSdkFlutterCloseLifecycle(
            CitizenSdkLifecycle.STARTING,
            { stopCount++; CompletableFuture.completedFuture(null) },
            { disposeCount++ },
        )
        assertTrue(unstable.isCompletedExceptionally)
        assertEquals(0, stopCount)
        assertEquals(1, disposeCount)
    }

    @Test
    fun `process orphan supervisor retains detach ownership and retries a failed close`() {
        val scheduled = ArrayDeque<() -> Unit>()
        var closeAttempts = 0
        val supervisor = CitizenSdkFlutterOrphanSupervisor<String>(
            scheduler = CitizenSdkFlutterRetryScheduler { _, task -> scheduled.addLast(task) },
            close = {
                closeAttempts++
                if (closeAttempts == 1) failedFuture(IllegalStateException("stop failed"))
                else CompletableFuture.completedFuture(null)
            },
        )

        supervisor.supervise("detached-registry")
        assertEquals(1, supervisor.sizeForTest())
        assertEquals(1, supervisor.failuresForTest("detached-registry"))
        assertEquals(1, scheduled.size)

        scheduled.removeFirst().invoke()
        assertEquals(2, closeAttempts)
        assertEquals(0, supervisor.sizeForTest())
        assertNull(supervisor.failuresForTest("detached-registry"))
    }

    @Test
    fun `repeated detach close failures remain supervised without a destroy fallback`() {
        val scheduled = ArrayDeque<() -> Unit>()
        var supervisedCloseAttempts = 0
        val supervisor = CitizenSdkFlutterOrphanSupervisor<String>(
            scheduler = CitizenSdkFlutterRetryScheduler { _, task -> scheduled.addLast(task) },
            close = {
                supervisedCloseAttempts++
                failedFuture(IllegalStateException("checkpoint unavailable"))
            },
        )

        supervisor.supervise("detached-registry")
        repeat(4) { scheduled.removeFirst().invoke() }

        assertEquals(5, supervisedCloseAttempts)
        assertEquals(1, supervisor.sizeForTest())
        assertEquals(5, supervisor.failuresForTest("detached-registry"))
        assertEquals(1, scheduled.size)
        assertEquals(250L, CitizenSdkFlutterOrphanSupervisor.retryDelayMillis(1))
        assertEquals(30_000L, CitizenSdkFlutterOrphanSupervisor.retryDelayMillis(128))
    }

    @Test
    fun `accepted work settlement is bounded without completing or destroying the work`() {
        val scheduled = ArrayDeque<() -> Unit>()
        val pending = CompletableFuture<Void>()
        val settlement = citizenSdkFlutterSettleWithin(
            listOf(pending),
            CitizenSdkFlutterSessions.CLOSE_SETTLEMENT_TIMEOUT_MILLIS,
            CitizenSdkFlutterRetryScheduler { _, task -> scheduled.addLast(task) },
        )

        assertFalse(settlement.isDone)
        assertFalse(pending.isDone)
        scheduled.removeFirst().invoke()
        assertTrue(settlement.isCompletedExceptionally)
        assertFalse(pending.isDone)
    }

    @Test
    fun `accepted work failure still counts as settled before lifecycle close`() {
        val scheduled = ArrayDeque<() -> Unit>()
        val failed = failedFuture<Void>(IllegalStateException("operation failed"))
        val settlement = citizenSdkFlutterSettleWithin(
            listOf(failed),
            CitizenSdkFlutterSessions.CLOSE_SETTLEMENT_TIMEOUT_MILLIS,
            CitizenSdkFlutterRetryScheduler { _, task -> scheduled.addLast(task) },
        )

        assertTrue(settlement.isDone)
        assertFalse(settlement.isCompletedExceptionally)
    }

    private fun <T> failedFuture(error: Throwable): CompletableFuture<T> =
        CompletableFuture<T>().also { it.completeExceptionally(error) }
}
