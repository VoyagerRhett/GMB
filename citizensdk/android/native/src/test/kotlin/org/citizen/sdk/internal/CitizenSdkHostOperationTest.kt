package org.citizen.sdk.internal

import org.citizen.sdk.CitizenSdkErrorCode
import org.citizen.sdk.CitizenSdkException
import org.citizen.sdk.CitizenSdkClosePolicy
import org.citizen.sdk.CitizenSdkLifecycle
import org.citizen.sdk.CitizenAccountBalance
import org.citizen.sdk.CitizenBlockRef
import org.citizen.sdk.CitizenFinality
import org.citizen.sdk.CitizenU128
import org.citizen.sdk.ui.CitizenSdkWalletFlowAttachmentPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

class CitizenSdkHostOperationTest {
    @Test
    fun `QR close waits only for owned surfaces and frames while a shared camera may remain open`() {
        val gate = org.citizen.sdk.ui.CitizenSdkQrOwnedDrain()
        gate.surfaceBorrowed(); gate.surfaceBorrowed()
        gate.revoke(); gate.framesReturned()
        assertFalse(gate.isReady())
        gate.surfaceReturned(); assertFalse(gate.isReady())
        gate.surfaceReturned(); assertTrue(gate.isReady())
        // 不输入共享 CameraState.CLOSED；另一用例继续 OPEN 不阻碍本次真实归还。
        assertThrows(IllegalStateException::class.java) { gate.surfaceBorrowed() }
        assertThrows(IllegalStateException::class.java) { gate.surfaceReturned() }
        val noDevice = org.citizen.sdk.ui.CitizenSdkQrOwnedDrain()
        noDevice.revoke(); assertFalse(noDevice.isReady())
        noDevice.framesReturned(); assertTrue(noDevice.isReady())
    }

    @Test
    fun `QR review ownership is released on orphan failed admission and failed decode`() {
        val released = mutableListOf<Long>()
        val router = CitizenSdkRequestRouter({ false }) { if (it is CitizenSdkNativeResult.QrReview) released += it.token }
        fun value(token: Long) = CitizenSdkNativeCodec.Decoded(CitizenSdkNativeResult.QrReview(token, "{}"), null)
        router.onCompletion(91, value(1))
        assertEquals(listOf(1L), released)
        assertThrows(IllegalStateException::class.java) {
            router.submitOperation<Int>({ router.onCompletion(92, value(2)); error("admission rejected") }, { 1 }, null)
        }
        val pending = router.submitOperation<Int>({ 93 }, { error("projection rejected") }, null)
        router.onCompletion(93, value(3))
        assertTrue(pending.future.isCompletedExceptionally)
        assertEquals(listOf(1L, 2L, 3L), released)
        router.requireIdle(); router.close()
    }

    @Test
    fun `QR cancellation waits for a real completion and preserves successful review ownership`() {
        val cancelled = mutableListOf<Long>(); val released = mutableListOf<Long>()
        val router = CitizenSdkRequestRouter({ cancelled += it; true }) { if (it is CitizenSdkNativeResult.QrReview) released += it.token }
        val pending = router.submitOperation({ 71 }, { it as CitizenSdkNativeResult.QrReview }, null)
        assertTrue(pending.cancel()); assertEquals(listOf(71L), cancelled)
        assertFalse(pending.future.isDone)
        router.onCompletion(71, CitizenSdkNativeCodec.Decoded(null, CitizenSdkException(CitizenSdkErrorCode.CANCELLED, "cancelled")))
        assertTrue(pending.future.isCompletedExceptionally)
        val retained = router.submitOperation({ 72 }, { it as CitizenSdkNativeResult.QrReview }, null)
        router.onCompletion(72, CitizenSdkNativeCodec.Decoded(CitizenSdkNativeResult.QrReview(9, "{}"), null))
        assertEquals(9L, retained.future.join().token)
        assertTrue(released.isEmpty())
        router.requireIdle(); router.close()
    }

    @Test
    fun `batch balance wire uses kind eighteen and rejects truncated or excessive results`() {
        fun wire(count: Int, includeBalances: Boolean = true): ByteArray {
            val stored = if (includeBalances) count else 0
            val output = ByteBuffer.allocate(24 + stored * 124).order(ByteOrder.LITTLE_ENDIAN)
                .putInt(1).putInt(0).putInt(0).putInt(18).putInt(0).putInt(count)
            repeat(stored) {
                output.put(ByteArray(32) { 3 }).putLong(7).putInt(2)
                output.put(ByteArray(32) { 1 })
                output.putLong(7).putLong(0).putLong(3).putLong(0).putLong(10).putLong(0)
            }
            return output.array()
        }
        for (count in listOf(0, 2)) {
            val result = CitizenSdkNativeCodec.decode(wire(count)).result as CitizenSdkNativeResult.Balances
            assertEquals(count, result.value.size)
            result.value.forEach { value ->
                assertEquals("10", value.totalFen.toString())
                assertEquals(CitizenFinality.FINALIZED, value.block.finality)
            }
        }
        for (invalid in listOf(wire(2).dropLast(1).toByteArray(), wire(1991, false))) {
            assertEquals(CitizenSdkErrorCode.INTEGRITY, assertThrows(CitizenSdkException::class.java) {
                CitizenSdkNativeCodec.decode(invalid)
            }.code)
        }
    }

    @Test
    fun `batch balance result correlation preserves duplicates and rejects partial reordered mixed blocks`() {
        val first = ByteArray(32) { 1 }
        val second = ByteArray(32) { 2 }
        val finalized = CitizenBlockRef(ByteArray(32) { 3 }, "7", CitizenFinality.FINALIZED)
        fun balance(accountId: ByteArray, block: CitizenBlockRef = finalized) =
            CitizenAccountBalance(block, accountId, CitizenU128("7"), CitizenU128("3"), CitizenU128("10"))
        val a = balance(first)
        val b = balance(second)
        assertTrue(CitizenSdkNativeCodec.validateBalances(emptyList(), emptyArray()).isEmpty())
        assertEquals(listOf(b, a, b), CitizenSdkNativeCodec.validateBalances(listOf(b, a, b), arrayOf(second, first, second)))
        for (values in listOf(listOf(a), listOf(b, a),
            listOf(a, balance(second, CitizenBlockRef(ByteArray(32) { 4 }, "8", CitizenFinality.FINALIZED))),
            listOf(a, balance(second, CitizenBlockRef(finalized.hash(), "7", CitizenFinality.BEST))))) {
            assertEquals(CitizenSdkErrorCode.INTEGRITY, assertThrows(CitizenSdkException::class.java) {
                CitizenSdkNativeCodec.validateBalances(values, arrayOf(first, second))
            }.code)
        }
    }

    @Test
    fun `close barrier allows callback reentry to fail immediately without holding admission lock`() {
        val calls = CitizenSdkNativeCalls()
        val destroyEntered = CountDownLatch(1)
        val callbackReturned = CountDownLatch(1)
        val closeFinished = CountDownLatch(1)
        val closer = thread {
            calls.close {
                destroyEntered.countDown()
                assertTrue(callbackReturned.await(2, TimeUnit.SECONDS))
            }
            closeFinished.countDown()
        }
        assertTrue(destroyEntered.await(2, TimeUnit.SECONDS))
        assertThrows(IllegalStateException::class.java) { calls.call { error("entered closing bridge") } }
        assertEquals(CitizenSdkErrorCode.BUSY, assertThrows(CitizenSdkException::class.java) {
            calls.close { error("destroyed twice") }
        }.code)
        callbackReturned.countDown()
        assertTrue(closeFinished.await(2, TimeUnit.SECONDS))
        closer.join()
        calls.close { error("destroyed after successful close") }
    }

    @Test
    fun `native lease prevents destruction and failed teardown is retry only`() {
        val calls = CitizenSdkNativeCalls()
        calls.call {
            assertEquals(CitizenSdkErrorCode.BUSY, assertThrows(CitizenSdkException::class.java) {
                calls.close { error("destroyed a leased bridge") }
            }.code)
        }
        var attempts = 0
        assertThrows(IllegalStateException::class.java) {
            calls.close { attempts += 1; error("injected teardown failure") }
        }
        assertFalse(calls.isClosed())
        assertThrows(IllegalStateException::class.java) { calls.call { error("reopened partially destroyed bridge") } }
        calls.close { attempts += 1 }
        assertEquals(2, attempts)
        assertTrue(calls.isClosed())
    }

    @Test
    fun `terminal vault ownership wipes error output and never touches borrowed buffer twice`() {
        val output = ByteBuffer.allocateDirect(32)
        repeat(32) { output.put(it, 9) }
        val wrapped = ByteArray(16) { 7 }
        var completions = 0
        val operation = CitizenSdkVaultOperation(output, wrapped) { code ->
            assertEquals(CitizenSdkErrorCode.AUTHENTICATION_CANCELLED.value, code)
            assertTrue((0 until 32).all { output.get(it) == 0.toByte() })
            assertTrue(wrapped.all { it == 0.toByte() })
            completions += 1
        }
        operation.finish { CitizenSdkErrorCode.AUTHENTICATION_CANCELLED }
        // 模拟 completion 后 Rust 已回收并复用该区域，迟到 callback 不得再写。
        output.put(0, 42)
        operation.finish { output.put(0, 99); CitizenSdkErrorCode.OK }
        assertEquals(42.toByte(), output.get(0))
        assertEquals(1, completions)
    }

    @Test
    fun `concurrent vault terminal callbacks execute only one cipher operation`() {
        val output = ByteBuffer.allocateDirect(32)
        val ready = CountDownLatch(1)
        val release = CountDownLatch(1)
        val operation = CitizenSdkVaultOperation(output, ByteArray(1)) { }
        var executions = 0
        val winner = thread {
            operation.finish {
                executions += 1
                ready.countDown()
                assertTrue(release.await(2, TimeUnit.SECONDS))
                CitizenSdkErrorCode.OK
            }
        }
        assertTrue(ready.await(2, TimeUnit.SECONDS))
        val loser = thread { operation.finish { executions += 1; CitizenSdkErrorCode.INTERNAL } }
        release.countDown()
        winner.join(); loser.join()
        assertEquals(1, executions)
    }

    @Test
    fun `successful vault output survives late error and thrown cipher is wiped`() {
        val output = ByteBuffer.allocateDirect(32)
        val wrapped = ByteArray(8) { 4 }
        var completions = 0
        val success = CitizenSdkVaultOperation(output, wrapped) { code ->
            assertEquals(CitizenSdkErrorCode.OK.value, code)
            assertTrue(wrapped.all { it == 0.toByte() })
            completions += 1
        }
        success.finish {
            repeat(32) { output.put(it, 8) }
            CitizenSdkErrorCode.OK
        }
        success.finish { error("late authentication error reached consumed output") }
        assertEquals(1, completions)
        assertTrue((0 until 32).all { output.get(it) == 8.toByte() })
        val failed = CitizenSdkVaultOperation(output, ByteArray(1)) { code ->
            assertEquals(CitizenSdkErrorCode.INTERNAL.value, code)
            assertTrue((0 until 32).all { output.get(it) == 0.toByte() })
        }
        failed.finish { error("injected cipher failure") }
    }

    @Test
    fun `claimed wallet Activity cannot cross a concurrent terminal boundary`() {
        assertTrue(
            CitizenSdkWalletFlowAttachmentPolicy.canClaim(
                completionStarted = false,
                finished = false,
                terminalKnown = false,
                claimPending = false,
            ),
        )
        assertFalse(
            CitizenSdkWalletFlowAttachmentPolicy.canClaim(
                completionStarted = false,
                finished = false,
                terminalKnown = false,
                claimPending = true,
            ),
        )
        assertTrue(
            CitizenSdkWalletFlowAttachmentPolicy.finishWithoutContent(
                completionStarted = true,
                finished = false,
                terminalKnown = false,
            ),
        )
    }

    @Test
    fun `wallet secret encoding is bounded before proportional allocation`() {
        CitizenSdkSensitiveBytes.utf8("a".repeat(1024)).use { value ->
            assertEquals(1024, value.size)
        }
        assertEquals(
            CitizenSdkErrorCode.INVALID_ARGUMENT,
            assertThrows(CitizenSdkException::class.java) {
                CitizenSdkSensitiveBytes.utf8("a".repeat(1025))
            }.code,
        )
    }

    @Test
    fun `malformed UTF-8 and unknown errors fail as integrity`() {
        val malformedText = ByteBuffer.allocate(4 * 5 + 1)
            .order(ByteOrder.LITTLE_ENDIAN)
            .putInt(1)
            .putInt(CitizenSdkErrorCode.INVALID_ARGUMENT.value)
            .putInt(CitizenSdkFailureStage.VALIDATION.value)
            .putInt(0)
            .putInt(1)
            .put(0xc3.toByte())
            .array()
        assertEquals(
            CitizenSdkErrorCode.INTEGRITY,
            assertThrows(CitizenSdkException::class.java) {
                CitizenSdkNativeCodec.decode(malformedText)
            }.code,
        )
        listOf(-1, 23, Int.MAX_VALUE).forEach { unknown ->
            val wire = ByteBuffer.allocate(4 * 5)
                .order(ByteOrder.LITTLE_ENDIAN)
                .putInt(1)
                .putInt(unknown)
                .putInt(CitizenSdkFailureStage.ADMISSION.value)
                .putInt(0)
                .putInt(0)
                .array()
            assertEquals(
                CitizenSdkErrorCode.INTEGRITY,
                assertThrows(CitizenSdkException::class.java) {
                    CitizenSdkNativeCodec.decode(wire)
                }.code,
            )
        }
        assertEquals(
            CitizenSdkErrorCode.INTEGRITY,
            assertThrows(CitizenSdkException::class.java) {
                CitizenSdkNativeCodec.decodeCapabilities(ByteArray(4))
            }.code,
        )
    }

    @Test
    fun `wallet accounts kind remains distinct from wallet profile`() {
        val wire = ByteBuffer.allocate(4 * 7 + 32 + 4 + 1 + 1 + 8 + 1)
            .order(ByteOrder.LITTLE_ENDIAN)
            .putInt(1) // wire version
            .putInt(0) // error
            .putInt(0) // successful result has no failure stage
            .putInt(13) // WALLET_ACCOUNTS
            .putInt(0) // error message length
            .putInt(1) // account count
            .putInt(1) // derivation index
            .put(ByteArray(32) { 7 })
            .putInt(1)
            .put('x'.code.toByte())
            .put(0.toByte()) // no name
            .putLong(9)
            .put(0.toByte()) // add result has no active account projection
            .array()
        val result = CitizenSdkNativeCodec.decode(wire).result
        assertTrue(result is CitizenSdkNativeResult.Accounts)
        assertEquals(1L, (result as CitizenSdkNativeResult.Accounts).value.single().index)
    }

    @Test
    fun `watch codec preserves full unsigned u32 peer count`() {
        val wire = ByteBuffer.allocate(4 + 4 + 4 + 1 + 1)
            .order(ByteOrder.LITTLE_ENDIAN)
            .putInt(1)
            .putInt(1)
            .putInt(-1)
            .put(0.toByte())
            .put(0.toByte())
            .array()
        assertEquals(4_294_967_295L, CitizenSdkNativeCodec.decodeWatch(wire).peerCount)
    }

    @Test
    fun `close policy requires a completed stop checkpoint`() {
        assertEquals(
            CitizenSdkClosePolicy.Decision.DESTROY,
            CitizenSdkClosePolicy.validate(CitizenSdkLifecycle.STOPPED),
        )
        assertEquals(
            CitizenSdkErrorCode.INVALID_STATE,
            assertThrows(CitizenSdkException::class.java) {
                CitizenSdkClosePolicy.validate(CitizenSdkLifecycle.RUNNING)
            }.code,
        )
        assertEquals(
            CitizenSdkErrorCode.BUSY,
            assertThrows(CitizenSdkException::class.java) {
                CitizenSdkClosePolicy.validate(CitizenSdkLifecycle.STARTING)
            }.code,
        )
    }

    @Test
    fun `completion racing before accepting return maps by exact core id`() {
        lateinit var router: CitizenSdkRequestRouter
        router = CitizenSdkRequestRouter(cancelNative = { true })
        val operation = router.submitOperation(
            begin = {
                router.onCompletion(41, CitizenSdkNativeCodec.Decoded(CitizenSdkNativeResult.Empty, null))
                41
            },
            decode = { "done" },
            progressListener = null,
        )
        assertEquals("done", operation.future.get(1, TimeUnit.SECONDS))
        assertFalse(operation.cancel())
        router.requireIdle()
    }

    @Test
    fun `cancel remains in admission gate and never completes future locally`() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val router = CitizenSdkRequestRouter(cancelNative = { requestId ->
            assertEquals(9L, requestId)
            entered.countDown()
            release.await(1, TimeUnit.SECONDS)
            true
        })
        val operation = router.submitOperation(
            begin = { 9 },
            decode = { Unit },
            progressListener = null,
        )
        val cancelThread = thread { assertTrue(operation.cancel()) }
        assertTrue(entered.await(1, TimeUnit.SECONDS))
        assertThrows(CitizenSdkException::class.java) { router.requireIdle() }.also {
            assertEquals(CitizenSdkErrorCode.BUSY, it.code)
        }
        assertFalse(operation.future.isDone)
        release.countDown()
        cancelThread.join()
        router.onCompletion(
            9,
            CitizenSdkNativeCodec.Decoded(
                null,
                CitizenSdkException(CitizenSdkErrorCode.CANCELLED, "cancelled"),
            ),
        )
        assertTrue(operation.future.isCompletedExceptionally)
        router.requireIdle()
    }
}
