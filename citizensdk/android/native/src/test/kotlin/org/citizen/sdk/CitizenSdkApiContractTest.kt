package org.citizen.sdk

import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.nio.ByteBuffer
import org.citizen.sdk.ui.CitizenSdkPrivateKeyDisplayBuffer

class CitizenSdkApiContractTest {
    @Test
    fun `QR native UI has one scan and safe signing entry without clocks or raw signatures`() {
        val activity = androidx.fragment.app.FragmentActivity::class.java
        assertEquals(CitizenSdkOperation::class.java, CitizenSdk::class.java.getMethod("qrScan", activity).returnType)
        assertEquals(CitizenSdkOperation::class.java, CitizenSdk::class.java.getMethod("signQrRequest", activity, String::class.java).returnType)
        assertEquals(CitizenQrDocument::class.java, CitizenSdk::class.java.getMethod("qrParse", String::class.java).returnType)
        assertEquals(ByteArray::class.java, CitizenSdk::class.java.getMethod("qrConsumeSignResponse", String::class.java).returnType)
        for (removed in listOf("qrSigningInput", "qrCreateSignResponse", "qrEncodeImage")) {
            assertTrue(CitizenSdk::class.java.methods.none { it.name == removed })
        }
        assertNotNull(CitizenQrSigned::class.java.getMethod("getQrImage"))
    }

    @Test
    fun `private authorization binds exactly one actual host operation and rejects late notification`() {
        val buffer = CitizenSdkPrivateKeyDisplayBuffer()
        buffer.bind(7)
        val registered = mutableListOf<Long>()
        buffer.bindAuthenticationRegistry { registered.add(it); CitizenSdkErrorCode.OK.value }
        assertEquals(CitizenSdkErrorCode.INTEGRITY.value, buffer.authorizing(8, 19))
        assertEquals(CitizenSdkErrorCode.INTEGRITY.value, buffer.authorizing(7, 0))
        assertEquals(null, buffer.authenticationId())
        assertEquals(CitizenSdkErrorCode.OK.value, buffer.authorizing(7, 19))
        assertEquals(19L, buffer.authenticationId())
        assertEquals(CitizenSdkErrorCode.INTEGRITY.value, buffer.authorizing(7, 20))
        buffer.clear()
        assertEquals(CitizenSdkErrorCode.CANCELLED.value, buffer.authorizing(7, 21))
        assertEquals(listOf(19L), registered)
    }

    @Test
    fun `private key view public entry has only a foreground host account and no secret result`() {
        val method = CitizenSdk::class.java.getMethod("viewAccountPrivateKey",
            androidx.fragment.app.FragmentActivity::class.java, ByteArray::class.java)
        assertEquals(CitizenSdkOperation::class.java, method.returnType)
        assertEquals(2, method.parameterCount)
    }

    @Test
    fun `private display uses fixed mutable hex and rejects repeated malformed and cancelled delivery`() {
        val buffer = CitizenSdkPrivateKeyDisplayBuffer()
        buffer.bind(7)
        // 公开合成缓冲仅测试内存/显示合同，不创建钱包或读取设备秘密。
        val source = ByteBuffer.allocateDirect(32)
        repeat(32) { source.put(it, it.toByte()) }
        assertEquals(CitizenSdkErrorCode.CANCELLED.value, buffer.display(8, source))
        assertEquals(CitizenSdkErrorCode.INTEGRITY.value, buffer.display(7, ByteBuffer.allocate(32)))
        assertEquals(CitizenSdkErrorCode.INTEGRITY.value, buffer.display(7, ByteBuffer.allocateDirect(31)))
        assertEquals(CitizenSdkErrorCode.OK.value, buffer.display(7, source))
        buffer.draw { characters ->
            assertEquals(66, characters.size)
            assertEquals('0', characters[0]); assertEquals('x', characters[1])
            assertTrue(characters.drop(2).all { it in '0'..'9' || it in 'a'..'f' })
        }
        assertEquals(CitizenSdkErrorCode.CANCELLED.value, buffer.display(7, source))
        buffer.clear()
        assertTrue(buffer.isClearedForTest())
        assertEquals(CitizenSdkErrorCode.CANCELLED.value, buffer.display(7, source))
        var drawn = false
        buffer.draw { drawn = true }
        assertTrue(!drawn)
        repeat(32) { source.put(it, 0) }
    }

    @Test
    fun `early private settlement retains a no secret notification until the view binds`() {
        val buffer = CitizenSdkPrivateKeyDisplayBuffer()
        buffer.settled(9, CitizenSdkErrorCode.NOT_FOUND.value)
        buffer.bind(9)
        var notifications = 0
        buffer.listen { assertEquals(CitizenSdkErrorCode.NOT_FOUND.value, it); notifications += 1 }
        assertEquals(1, notifications)
        buffer.clear()
        assertTrue(buffer.isClearedForTest())
    }
    @Test
    fun `chain facade exposes one genesis and batch balance entry with bounded input`() {
        assertNotNull(CitizenSdk::class.java.getMethod("getGenesisHash"))
        assertNotNull(CitizenSdk::class.java.getMethod("getAccountBalances", List::class.java))
        for (count in listOf(0, 1, 1990)) CitizenSdkInputLimits.requireBalanceAccountCount(count)
        for (count in listOf(-1, 1991)) {
            assertEquals(CitizenSdkErrorCode.INVALID_ARGUMENT, assertThrows(CitizenSdkException::class.java) {
                CitizenSdkInputLimits.requireBalanceAccountCount(count)
            }.code)
        }
    }

    @Test
    fun `wallet UI rejects unselected Core capability before starting Activity`() {
        for ((supported, enabled) in listOf(true to false, false to true, false to false)) {
            val status = CitizenCapabilityStatus(CitizenCapabilityName.WALLET_PROFILE,
                CitizenCapabilityReason.HOST_DISABLED, supported, true, enabled, false)
            assertEquals(CitizenSdkErrorCode.NOT_READY, assertThrows(CitizenSdkException::class.java) {
                CitizenSdkWalletUiAdmission.check(CitizenSdkCapabilities("1", listOf(status)))
            }.code)
        }
        val enabled = CitizenCapabilityStatus(CitizenCapabilityName.WALLET_PROFILE,
            CitizenCapabilityReason.NONE, true, true, true, true)
        CitizenSdkWalletUiAdmission.check(CitizenSdkCapabilities("1", listOf(enabled)))
        assertThrows(CitizenSdkException::class.java) {
            CitizenSdkWalletUiAdmission.check(CitizenSdkCapabilities("1", emptyList()))
        }
    }

    @Test
    fun `wallet and signing are independent modules with one public signing facade`() {
        assertEquals(listOf(1, 2, 4, 8, 16), listOf(CitizenSdkModules.WALLET,
            CitizenSdkModules.SIGNING, CitizenSdkModules.CHAIN, CitizenSdkModules.TRANSACTIONS,
            CitizenSdkModules.HISTORY))
        assertEquals(31, CitizenSdkModules.FULL)
        assertEquals(0, CitizenSdkModules.WALLET and CitizenSdkModules.SIGNING)
        val names = CitizenSdk::class.java.methods.map { it.name }
        assertTrue("getSigning" in names)
        assertTrue("signWalletPayload" !in names)
        assertNotNull(CitizenSigning::class.java.getMethod("verify", ByteArray::class.java,
            ByteArray::class.java, ByteArray::class.java))
    }

    @Test
    fun `native facade enforces sign and wallet allocation boundaries`() {
        CitizenSdkInputLimits.requireSignPayload(16 * 1024 * 1024)
        CitizenSdkInputLimits.requireSignPayload(0)
        assertEquals(
            CitizenSdkErrorCode.INVALID_ARGUMENT,
            assertThrows(CitizenSdkException::class.java) {
                CitizenSdkInputLimits.requireSignPayload(16 * 1024 * 1024 + 1)
            }.code,
        )
        CitizenSdkInputLimits.requireWalletSecret("mnemonic", 1024)
        assertEquals(
            CitizenSdkErrorCode.INVALID_ARGUMENT,
            assertThrows(CitizenSdkException::class.java) {
                CitizenSdkInputLimits.requireWalletSecret("mnemonic", 1025)
            }.code,
        )
        CitizenSdkInputLimits.requireAddAccountIndices(intArrayOf(1, 1989))
        assertEquals(
            CitizenSdkErrorCode.INVALID_ARGUMENT,
            assertThrows(CitizenSdkException::class.java) {
                CitizenSdkInputLimits.requireAddAccountIndices(IntArray(1990) { 1 })
            }.code,
        )
        assertEquals(
            CitizenSdkErrorCode.INVALID_ARGUMENT,
            assertThrows(CitizenSdkException::class.java) {
                CitizenSdkInputLimits.requireAddAccountIndices(intArrayOf(1, 1))
            }.code,
        )
        CitizenSdkInputLimits.requireWalletAccountNameInput("x".repeat(128))
        assertEquals(
            CitizenSdkErrorCode.INVALID_ARGUMENT,
            assertThrows(CitizenSdkException::class.java) {
                CitizenSdkInputLimits.requireWalletAccountNameInput("x".repeat(129))
            }.code,
        )
        assertThrows(IllegalArgumentException::class.java) {
            CitizenU128("1".repeat(40))
        }
    }

    @Test
    fun `public facade contains no native handle getter`() {
        val type = Class.forName("org.citizen.sdk.CitizenSdk", false, javaClass.classLoader)
        val names = type.methods.map { it.name }
        assertTrue("start" in names)
        assertTrue("stop" in names)
        assertTrue("getTransactionHistory" in names)
        assertTrue("syncTransactionHistory" in names)
        assertTrue(names.none { it.contains("transferWithRemark", ignoreCase = true) })
        assertTrue(names.none { it.contains("handle", ignoreCase = true) })
        assertNotNull(CitizenSdkOperation::class.java.getMethod("cancel"))
    }
}
