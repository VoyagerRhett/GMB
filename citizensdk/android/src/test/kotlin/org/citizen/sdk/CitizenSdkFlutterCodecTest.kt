package org.citizen.sdk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class CitizenSdkFlutterCodecTest {
    @Test
    fun `QR UI routes reject clocks signatures and retired methods`() {
        val scan = CitizenSdkFlutterCodec.decode("qrScan", listOf(1, "session", 1L)) as CitizenSdkFlutterCodec.Request.Qr
        assertEquals(emptyList<Any?>(), scan.fields)
        for (method in listOf("qrParse", "qrConsumeSignResponse", "signQrRequest")) {
            CitizenSdkFlutterCodec.decode(method, listOf(1, "session", 2L, "{}"))
            for (extra in listOf(123L, ByteArray(64))) assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
                CitizenSdkFlutterCodec.decode(method, listOf(1, "session", 2L, "{}", extra))
            }
        }
        for (method in listOf("qrSigningInput", "qrCreateSignResponse", "qrEncodeImage")) {
            assertEquals(false, CitizenSdkFlutterCodec.methods.contains(method))
            assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
                CitizenSdkFlutterCodec.decode(method, listOf(1, "session", 3L, "{}"))
            }
        }
    }

    @Test
    fun `private key view carries one public account and rejects any additional field`() {
        val account = "0x" + "11".repeat(32)
        val request = CitizenSdkFlutterCodec.decode("viewAccountPrivateKey", listOf(1, "session", 7L, account))
            as CitizenSdkFlutterCodec.Request.Account
        assertEquals("session", request.sessionId); assertEquals(7L, request.requestSequence)
        assertEquals(account, CitizenSdkFlutterCodec.encodeHash32(request.accountId))
        for (tuple in listOf(listOf(1, "session", 7L), listOf(1, "session", 7L, account, "extra"),
            listOf(1, "session", 7L, "0X" + "11".repeat(32)))) {
            assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
                CitizenSdkFlutterCodec.decode("viewAccountPrivateKey", tuple)
            }
        }
    }

    @Test
    fun `chain queries retain session shape and batch order duplicates and empty input`() {
        val first = "0x" + "11".repeat(32)
        val second = "0x" + "22".repeat(32)
        val genesis = CitizenSdkFlutterCodec.decode("getGenesisHash", listOf(1, "session", 7L))
        assertEquals("session", genesis.sessionId)
        assertEquals(7L, genesis.requestSequence)
        for (accounts in listOf(emptyList(), listOf(second, first, second), List(1990) { first })) {
            val request = CitizenSdkFlutterCodec.decode("getAccountBalances", listOf(1, "session", 8L, accounts))
                as CitizenSdkFlutterCodec.Request.Balances
            assertEquals(accounts, request.accountIds.map(CitizenSdkFlutterCodec::encodeHash32))
            assertEquals("session", request.sessionId)
            assertEquals(8L, request.requestSequence)
        }
        for (tuple in listOf(
            listOf(1, "session", 8L, List(1991) { first }),
            listOf(1, "session", 8L, listOf("0x" + "AA".repeat(32))),
            listOf(1, "session", 8L, first), listOf(1, "session", 8L, emptyList<String>(), "extra"),
        )) {
            val failure = assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
                CitizenSdkFlutterCodec.decode("getAccountBalances", tuple)
            }
            assertEquals("session", failure.sessionId)
            assertEquals(8L, failure.requestSequence)
        }
        assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
            CitizenSdkFlutterCodec.decode("getGenesisHash", listOf(1, "session", 7L, "extra"))
        }
    }

    @Test
    fun `open carries modules without replicating Core dependency rules`() {
        for (modules in listOf(1, 2, 4, 12, 20, 31, 32, 63)) {
            val request = CitizenSdkFlutterCodec.decode("open", listOf(1, modules)) as CitizenSdkFlutterCodec.Request.Open
            assertEquals(modules, request.modules)
        }
        for (tuple in listOf(listOf(1), listOf(1, true), listOf(1, 1.0), listOf(1, -1),
            listOf(1, 4294967296L), listOf(1, 31, 0))) {
            assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
                CitizenSdkFlutterCodec.decode("open", tuple)
            }
        }
    }

    @Test
    fun `verify has a fixed public signature and permits an empty message`() {
        val prefix = listOf(1, "0x" + "11".repeat(32))
        for (length in listOf(0, 63, 65)) {
            assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
                CitizenSdkFlutterCodec.decode("verifySignature", prefix + listOf(ByteArray(length), byteArrayOf()))
            }
        }
        val request = CitizenSdkFlutterCodec.decode("verifySignature",
            prefix + listOf(ByteArray(64), byteArrayOf())) as CitizenSdkFlutterCodec.Request.VerifySignature
        assertEquals(64, request.signature.size)
        assertEquals(0, request.payload.size)
        assertNull(request.sessionId)
        assertEquals(0L, request.requestSequence)
    }

    @Test
    fun `verify rejects session shape and invalid public values without session identity`() {
        val account = "0x" + "11".repeat(32)
        val signature = ByteArray(64)
        for (tuple in listOf(
            listOf(1, "session", 7L, account, signature, byteArrayOf()),
            listOf(true, account, signature, byteArrayOf()),
            listOf(1, "0X" + "11".repeat(32), signature, byteArrayOf()),
            listOf(1, account, List(64) { 0 }, byteArrayOf()),
            listOf(1, account, signature, listOf(1, 2)),
            listOf(1, account, signature, byteArrayOf(), "extra"),
        )) {
            val failure = assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
                CitizenSdkFlutterCodec.decode("verifySignature", tuple)
            }
            assertNull(failure.sessionId)
            assertNull(failure.requestSequence)
        }
    }

    @Test
    fun `history invalidation has no payload`() {
        assertEquals("historyChanged", CitizenSdkFlutterCodec.event("session", 7L, "historyChanged", emptyList())[3])
        assertThrows(IllegalArgumentException::class.java) {
            CitizenSdkFlutterCodec.event("session", 0L, "historyChanged", emptyList())
        }
        assertThrows(IllegalArgumentException::class.java) {
            CitizenSdkFlutterCodec.event("session", 7L, "historyChanged", listOf(1))
        }
    }
    @Test
    fun `wallet word count closure is exactly twelve eighteen twenty four`() {
        for (count in listOf(12, 18, 24)) {
            val request = CitizenSdkFlutterCodec.decode("createWallet", listOf(1, "session", 1L, count))
                as CitizenSdkFlutterCodec.Request.CreateWallet
            assertEquals(count, request.wordCount)
        }
        for (count in listOf(0, 15, 21, 30)) assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
            CitizenSdkFlutterCodec.decode("createWallet", listOf(1, "session", 1L, count))
        }
    }

    @Test
    fun `v1 method and channel closure is exact`() {
        assertEquals("citizen/sdk/core/v1", CitizenSdkFlutterCodec.METHOD_CHANNEL)
        assertEquals("citizen/sdk/events/v1", CitizenSdkFlutterCodec.EVENT_CHANNEL)
        assertEquals(1, CitizenSdkFlutterCodec.PROTOCOL_VERSION)
        assertEquals(
            linkedSetOf(
                "open", "start", "stop", "close", "getCapabilities",
                "getFinalizedHead", "getSyncStatus", "getBestHead", "getFinalizedBlockAt",
                "resolveFinalizedBlock", "getBlockHeader", "getBlockBody", "getRuntimeContext",
                "getStorage", "getStorageBatch", "getSystemEvents", "exportState", "importState",
                "getGenesisHash", "getAccountBalance", "getAccountBalances", "getAccountNonce",
                "getFeeSnapshot", "getWalletProfile", "getWalletState", "importColdAccountId",
                "importColdAccountSs58", "reorderWalletAccountsWithoutDefaultChange",
                "renameAccount", "deleteAccount", "viewAccountPrivateKey", "createWallet", "importWallet",
                "addWalletAccounts", "setActiveWalletAccount", "renameWalletAccount",
                "deleteWalletAccount", "deleteWallet", "reconcileWalletCleanup",
                "signWalletPayload", "beginSigning", "consumeExternalSignature", "cancelSigning",
                "beginDefaultAccountChange", "consumeDefaultAccountChange", "verifySignature",
                "prepareTransaction", "cancelPreparedTransaction", "executePreparedTransaction",
                "consumePreparedTransactionQrResponse", "cancelPreparedTransactionExecution",
                "getTransactionHistory", "syncTransactionHistory", "qrParse", "qrCreateSignRequest",
                "qrConsumeSignResponse", "qrCancelSignRequest",
                "qrEncodeAccountId", "qrEncodeUserTransfer", "qrDecodeLuminance", "qrEncode", "qrScan", "signQrRequest",
            ),
            CitizenSdkFlutterCodec.methods,
        )
    }

    @Test
    fun `requests reject extra secret and native ownership fields`() {
        // Fixed-position tuples have no field in which any of these values can
        // be represented. Every appended value is rejected by exact length.
        for (forbidden in listOf("mnemonic", "password", "privateKey", "nativeHandle")) {
            assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
                CitizenSdkFlutterCodec.decode(
                    "importWallet",
                    listOf(1, "session-1", 1L, forbidden),
                )
            }
        }
        assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
            CitizenSdkFlutterCodec.decode("open", mapOf("protocolVersion" to 1))
        }
    }

    @Test
    fun `every v1 method has one exact positional request shape`() {
        val account = "0x" + "11".repeat(32)
        val destination = "0x" + "22".repeat(32)
        val requests = linkedMapOf<String, List<Any?>>()
        requests["open"] = listOf(1, 63)
        for (method in listOf(
            "start", "stop", "close", "getCapabilities", "getFinalizedHead", "getSyncStatus",
            "getBestHead", "exportState", "getGenesisHash",
            "getFeeSnapshot", "getWalletProfile", "getWalletState", "importWallet", "deleteWallet",
            "reconcileWalletCleanup",
        )) requests[method] = listOf(1, "session-1", 1L)
        val finalizedBlock = listOf(account, "1", "finalized")
        requests["getFinalizedBlockAt"] = listOf(1, "session-1", 1L, "1")
        requests["resolveFinalizedBlock"] = listOf(1, "session-1", 1L, account, "1")
        for (method in listOf("getBlockHeader", "getBlockBody", "getRuntimeContext", "getSystemEvents")) {
            requests[method] = listOf(1, "session-1", 1L, finalizedBlock)
        }
        requests["getStorage"] = listOf(1, "session-1", 1L, finalizedBlock, byteArrayOf(1))
        requests["getStorageBatch"] = listOf(
            1, "session-1", 1L, finalizedBlock, listOf(byteArrayOf(1), byteArrayOf(2)),
        )
        requests["importState"] = listOf(1, "session-1", 1L, 1, finalizedBlock, byteArrayOf(1))
        for (method in listOf(
            "getAccountBalance", "getAccountNonce", "viewAccountPrivateKey", "setActiveWalletAccount",
            "deleteWalletAccount", "deleteAccount",
        )) requests[method] = listOf(1, "session-1", 1L, account)
        requests["getAccountBalances"] = listOf(1, "session-1", 1L, listOf(account, account))
        requests["createWallet"] = listOf(1, "session-1", 1L, 24)
        requests["addWalletAccounts"] = listOf(1, "session-1", 1L, listOf(1, 7))
        requests["renameWalletAccount"] = listOf(1, "session-1", 1L, account, "main")
        requests["renameAccount"] = listOf(1, "session-1", 1L, account, "main")
        requests["importColdAccountId"] = listOf(1, "session-1", 1L, account, "cold")
        requests["importColdAccountSs58"] = listOf(
            1, "session-1", 1L, "w5CZACAABUbK4jspzPB5be9trhtSgRCRZFafGe7kvFPvxq8M2", "cold",
        )
        requests["reorderWalletAccountsWithoutDefaultChange"] =
            listOf(1, "session-1", 1L, "7", listOf(account, destination))
        requests["signWalletPayload"] = listOf(1, "session-1", 1L, account, byteArrayOf(1))
        requests["beginSigning"] = listOf(
            1, "session-1", 1L, account, byteArrayOf(1), "raw", byteArrayOf(), "none", 0, 120L,
        )
        requests["consumeExternalSignature"] = listOf(1, "session-1", 1L, "signing-session", "{}")
        requests["cancelSigning"] = listOf(1, "session-1", 1L, "signing-session")
        requests["beginDefaultAccountChange"] =
            listOf(1, "session-1", 1L, "7", listOf(destination, account), 120L)
        requests["consumeDefaultAccountChange"] = listOf(1, "session-1", 1L, "signing-session", "{}")
        requests["verifySignature"] = listOf(1, account, ByteArray(64), byteArrayOf())
        requests["prepareTransaction"] = listOf(1, "session-1", 1L, account, byteArrayOf(1, 2))
        requests["cancelPreparedTransaction"] =
            listOf(1, "session-1", 1L, "0x00112233445566778899aabbccddeeff")
        requests["executePreparedTransaction"] =
            listOf(1, "session-1", 1L, "0x00112233445566778899aabbccddeeff")
        requests["consumePreparedTransactionQrResponse"] =
            listOf(1, "session-1", 1L, "0x112233445566778899aabbccddeeff00", "QR_V1")
        requests["cancelPreparedTransactionExecution"] =
            listOf(1, "session-1", 1L, "0x112233445566778899aabbccddeeff00")
        requests["getTransactionHistory"] = listOf(1, "session-1", 1L, null, 100L)
        requests["syncTransactionHistory"] = listOf(1, "session-1", 1L)
        requests["qrParse"] = listOf(1, "session-1", 1L, "{}")
        requests["qrCreateSignRequest"] = listOf(1, "session-1", 1L, 0x0400, account, byteArrayOf(4, 0), 120L)
        requests["qrScan"] = listOf(1, "session-1", 1L)
        requests["signQrRequest"] = listOf(1, "session-1", 1L, "{}")
        requests["qrConsumeSignResponse"] = listOf(1, "session-1", 1L, "{}")
        requests["qrCancelSignRequest"] = listOf(1, "session-1", 1L, "abcdefghijklmnop")
        requests["qrEncodeAccountId"] = listOf(1, "session-1", 1L, account)
        requests["qrEncodeUserTransfer"] = listOf(1, "session-1", 1L, "abcdefghijklmnop", 10L,
            account, "1", "CNY", "", "bank-1")
        requests["qrDecodeLuminance"] = listOf(1, "session-1", 1L, byteArrayOf(0), 1, 1, 1)
        requests["qrEncode"] = listOf(1, "session-1", 1L, "{}", 4)

        assertEquals(CitizenSdkFlutterCodec.methods, requests.keys)
        requests.forEach { (method, tuple) ->
            CitizenSdkFlutterCodec.decode(method, tuple)
            assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
                CitizenSdkFlutterCodec.decode(method, tuple + "forbidden-extra-position")
            }
        }
    }

    @Test
    fun `wallet state projection keeps global order cold mode and default first`() {
        val cold = CitizenWalletStateAccount(
            CitizenWalletSignMode.COLD,
            1,
            null,
            ByteArray(32) { 0x22.toByte() },
            "w5CZACAABUbK4jspzPB5be9trhtSgRCRZFafGe7kvFPvxq8M2",
            "cold",
            "2",
            true,
        )
        val tuple = CitizenSdkFlutterCodec.walletState(CitizenWalletState("7", null, listOf(cold)))
        assertEquals("7", tuple[0])
        assertNull(tuple[1])
        val account = (tuple[2] as List<*>).single() as List<*>
        assertEquals("cold", account[0])
        assertEquals(1L, account[1])
        assertNull(account[2])
        assertEquals(true, account[7])
    }

    @Test
    fun `transaction history cursor and limit are canonical`() {
        val cursor = "0x00112233445566778899aabbccddeeff"
        val request = CitizenSdkFlutterCodec.decode(
            "getTransactionHistory",
            listOf(1, "session-1", 7L, cursor, 25L),
        ) as CitizenSdkFlutterCodec.Request.TransactionHistory
        assertEquals(cursor, request.beforeExecutionId)
        assertEquals(25, request.limit)

        for (limit in listOf(0L, 101L)) {
            assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
                CitizenSdkFlutterCodec.decode(
                    "getTransactionHistory",
                    listOf(1, "session-1", 8L, null, limit),
                )
            }
        }
        assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
            CitizenSdkFlutterCodec.decode(
                "getTransactionHistory",
                listOf(1, "session-1", 9L, "0X00112233445566778899aabbccddeeff", 1L),
            )
        }
    }

    @Test
    fun `empty signing payload and normalized account name match the Dart encoder`() {
        val account = "0x" + "11".repeat(32)
        val signing = CitizenSdkFlutterCodec.decode(
            "signWalletPayload",
            listOf(1, "session-1", 10L, account, byteArrayOf()),
        ) as CitizenSdkFlutterCodec.Request.SignWalletPayload
        assertEquals(0, signing.payload.size)

        val rename = CitizenSdkFlutterCodec.decode(
            "renameWalletAccount",
            listOf(1, "session-1", 11L, account, "旅行钱包"),
        ) as CitizenSdkFlutterCodec.Request.RenameWalletAccount
        assertEquals("旅行钱包", rename.name)

        for (invalidName in listOf(" 旅行钱包", "旅行钱包 ", "钱包\u001c")) {
            assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
                CitizenSdkFlutterCodec.decode(
                    "renameWalletAccount",
                    listOf(1, "session-1", 12L, account, invalidName),
                )
            }
        }
        assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
            CitizenSdkFlutterCodec.decode(
                "addWalletAccounts",
                listOf(1, "session-1", 13L, listOf(0)),
            )
        }
    }

    @Test
    fun `request resource limits are enforced before projection copies`() {
        val account = "0x" + "11".repeat(32)
        assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
            CitizenSdkFlutterCodec.decode(
                "signWalletPayload",
                listOf(
                    1,
                    "session-1",
                    14L,
                    account,
                    ByteArray(CitizenSdkFlutterCodec.MAXIMUM_SIGNING_PAYLOAD_BYTES + 1),
                ),
            )
        }

        assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
            CitizenSdkFlutterCodec.decode(
                "getTransactionHistory",
                listOf(1, "session-1", 15L, null, 101L),
            )
        }

        val tooManyIndices = List(
            CitizenSdkFlutterCodec.MAXIMUM_ADDITIONAL_WALLET_ACCOUNTS + 1,
        ) { 1 }
        assertThrows(CitizenSdkFlutterCodec.ContractFailure::class.java) {
            CitizenSdkFlutterCodec.decode(
                "addWalletAccounts",
                listOf(1, "session-1", 16L, tooManyIndices),
            )
        }
    }

    @Test
    fun `response event and error envelopes expose only public v1 fields`() {
        val response = CitizenSdkFlutterCodec.response(
            "session-1",
            4,
            listOf(ByteArray(64)),
        )
        assertEquals(4, response.size)
        assertEquals(listOf(1, "session-1", 4L), response.take(3))

        val event = CitizenSdkFlutterCodec.event(
            "session-1",
            2,
            "lifecycleChanged",
            listOf("running"),
        )
        assertEquals(5, event.size)
        assertEquals(listOf(1, "session-1", 2L, "lifecycleChanged"), event.take(4))
        assertThrows(IllegalArgumentException::class.java) {
            CitizenSdkFlutterCodec.event("session-1", 3, "debug", emptyList())
        }

        val details = CitizenSdkFlutterCodec.errorDetails(
            CitizenSdkErrorCode.INVALID_ARGUMENT,
            "invalid",
            "session-1",
            4,
        )
        assertEquals(listOf(1, "session-1", 4L, 1, "invalid"), details)
    }
}
