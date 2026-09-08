package org.gmb.hardware_secretvault

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/** 不依赖 AndroidKeyStore 的原生边界测试；硬件属性由签名 Release 真机继续验收。 */
class HardwareSecretvaultPluginTest {
    private val plugin = HardwareSecretvaultPlugin()

    @Test
    fun `alias is deterministic and isolated by product and wallet scope`() {
        val first = plugin.aliasFor("citizenapp:1")
        assertEquals(first, plugin.aliasFor("citizenapp:1"))
        assertNotEquals(first, plugin.aliasFor("citizenapp:2"))
        assertNotEquals(first, plugin.aliasFor("citizenwallet:1"))
        assertThrows(HardwareSecretvaultPlugin.VaultFailure::class.java) {
            plugin.aliasFor("CitizenApp:1")
        }
    }

    @Test
    fun `envelope parser enforces version wrapped key length and boundaries`() {
        val wrappedKey = ByteArray(256) { (it and 0xff).toByte() }
        val iv = ByteArray(12) { (it + 1).toByte() }
        val body = ByteArray(17) { (it + 2).toByte() }
        val raw = ByteArray(1 + 2 + wrappedKey.size + iv.size + body.size)
        raw[0] = 1
        raw[1] = 1
        raw[2] = 0
        wrappedKey.copyInto(raw, 3)
        iv.copyInto(raw, 3 + wrappedKey.size)
        body.copyInto(raw, 3 + wrappedKey.size + iv.size)

        val parsed = plugin.parseEnvelope(raw)
        assertArrayEquals(wrappedKey, parsed.wrappedKey)
        assertArrayEquals(iv, parsed.iv)
        assertArrayEquals(body, parsed.body)

        raw[0] = 2
        assertThrows(HardwareSecretvaultPlugin.VaultFailure::class.java) {
            plugin.parseEnvelope(raw)
        }
        raw[0] = 1
        raw[2] = 1
        assertThrows(HardwareSecretvaultPlugin.VaultFailure::class.java) {
            plugin.parseEnvelope(raw)
        }
        parsed.clear()
        assertArrayEquals(ByteArray(256), parsed.wrappedKey)
        assertArrayEquals(ByteArray(12), parsed.iv)
        assertArrayEquals(ByteArray(17), parsed.body)
    }
}
