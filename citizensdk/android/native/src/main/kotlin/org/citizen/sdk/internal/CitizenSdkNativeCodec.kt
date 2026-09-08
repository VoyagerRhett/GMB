@file:kotlin.jvm.JvmSynthetic

package org.citizen.sdk.internal

import org.citizen.sdk.*
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

/** Decoder for the private JNI wire; the wire is not a public SDK protocol. */
internal object CitizenSdkNativeCodec {
    data class Decoded(val result: CitizenSdkNativeResult?, val error: CitizenSdkException?)

    fun decode(bytes: ByteArray): Decoded = decodeIntegrity("result") {
        val reader = Reader(bytes)
        check(reader.u32Long() == VERSION.toLong()) { "unsupported JNI result version" }
        val errorCode = reader.i32()
        val kind = reader.u32Long()
        val message = reader.text()
        if (errorCode != 0) {
            reader.finish()
            val stableCode = CitizenSdkErrorCode.fromValue(errorCode)
            check(stableCode.value == errorCode) {
                "JNI returned unknown error code $errorCode"
            }
            return@decodeIntegrity Decoded(
                null,
                CitizenSdkException(
                    stableCode,
                    message.ifEmpty { "CitizenSDK operation failed" },
                ),
            )
        }
        val result = when (kind) {
            0L -> CitizenSdkNativeResult.Empty
            1L -> CitizenSdkNativeResult.Block(reader.block())
            9L -> CitizenSdkNativeResult.Balance(reader.balance())
            10L -> CitizenSdkNativeResult.Nonce(
                CitizenAccountNonce(reader.block(), reader.fixed(32), reader.u64Text()),
            )
            11L -> CitizenSdkNativeResult.Fee(
                CitizenFeeSnapshot(reader.block(), reader.u32Long(), reader.u128(), reader.u128()),
            )
            12L -> CitizenSdkNativeResult.Profile(reader.walletProfile())
            13L -> CitizenSdkNativeResult.Accounts(reader.walletAccounts())
            14L -> CitizenSdkNativeResult.Signature(CitizenSignature(reader.fixed(64)))
            15L -> CitizenSdkNativeResult.Prepared(reader.positiveI64("prepared wallet token"))
            16L -> CitizenSdkNativeResult.Transfer(reader.walletTransfer())
            17L -> CitizenSdkNativeResult.History(reader.history())
            18L -> CitizenSdkNativeResult.Balances(
                List(reader.boundedCount(1990, "balance result count")) { reader.balance() },
            )
            19L -> CitizenSdkNativeResult.QrReview(reader.positiveI64("QR review token"), reader.text().also {
                check(it.toByteArray(Charsets.UTF_8).size in 1..65536)
            })
            20L -> CitizenSdkNativeResult.QrSigned(CitizenQrDocument.parse(reader.text()).also {
                check(it.kind == 2 && (it.signRequest?.toByteArray(Charsets.UTF_8)?.size ?: 0) in 1..2331)
            })
            else -> throw CitizenSdkException(
                CitizenSdkErrorCode.INTEGRITY,
                "JNI returned unsupported result kind $kind",
            )
        }
        reader.finish()
        Decoded(result, null)
    }

    /** 只检查传输完整性，不能在 Kotlin 重算余额或建立第二套链读取规则。 */
    fun validateBalances(values: List<CitizenAccountBalance>, accountIds: Array<ByteArray>): List<CitizenAccountBalance> {
        val block = values.firstOrNull()?.block
        if (values.size != accountIds.size || values.size > 1990 || values.indices.any { index ->
                val value = values[index]
                !value.accountId().contentEquals(accountIds[index]) ||
                    value.block.finality != CitizenFinality.FINALIZED || block == null ||
                    value.block.number != block.number || !value.block.hash().contentEquals(block.hash())
            }) throw CitizenSdkException(CitizenSdkErrorCode.INTEGRITY,
                "Core balance results do not match one finalized request")
        return values.toList()
    }

    fun decodeCapabilities(bytes: ByteArray): CitizenSdkCapabilities = decodeIntegrity("capability") {
        val reader = Reader(bytes)
        check(reader.u32Long() == VERSION.toLong()) { "unsupported capability wire version" }
        val revision = reader.u64Text()
        val count = reader.boundedCount(10, "capability count")
        check(count == 10) { "capability snapshot must contain ten entries" }
        val statuses = ArrayList<CitizenCapabilityStatus>(count)
        repeat(count) {
            statuses += CitizenCapabilityStatus(
                reader.oneBasedEnum(CitizenCapabilityName.entries, "capability name"),
                reader.zeroBasedEnum(CitizenCapabilityReason.entries, "capability reason"),
                reader.bool(),
                reader.bool(),
                reader.bool(),
                reader.bool(),
            )
        }
        reader.finish()
        CitizenSdkCapabilities(revision, statuses)
    }

    fun decodeWatch(bytes: ByteArray): Watch = decodeIntegrity("watch") {
        val reader = Reader(bytes)
        check(reader.u32Long() == VERSION.toLong()) { "unsupported watch wire version" }
        val status = reader.oneBasedEnum(CitizenSdkEvents.TransferStatus.entries, "watch status")
        val peers = reader.u32Long()
        val block = if (reader.bool()) reader.block() else null
        val replacement = if (reader.bool()) reader.fixed(32) else null
        reader.finish()
        Watch(status, peers, block, replacement)
    }

    data class Watch(
        val status: CitizenSdkEvents.TransferStatus,
        val peerCount: Long,
        val block: CitizenBlockRef?,
        val replacementHash: ByteArray?,
    )

    private inline fun <T> decodeIntegrity(label: String, block: () -> T): T = try {
        block()
    } catch (error: CitizenSdkException) {
        throw error
    } catch (error: Throwable) {
        throw CitizenSdkException(
            CitizenSdkErrorCode.INTEGRITY,
            "CitizenSDK returned a malformed $label envelope",
            error,
        )
    }

    private class Reader(bytes: ByteArray) {
        private val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        fun i32(): Int = buffer.int
        fun u32Long(): Long = Integer.toUnsignedLong(buffer.int)
        fun i64(): Long = buffer.long
        fun positiveI64(label: String): Long = i64().also { check(it > 0) { "$label is invalid" } }
        fun u64Text(): String = java.lang.Long.toUnsignedString(buffer.long)
        fun bool(): Boolean = when (val value = buffer.get().toInt()) {
            0 -> false
            1 -> true
            else -> error("JNI boolean is invalid: $value")
        }
        fun fixed(size: Int): ByteArray {
            check(size >= 0 && size <= buffer.remaining()) { "JNI byte field exceeds its envelope" }
            return ByteArray(size).also(buffer::get)
        }
        fun bytes(): ByteArray {
            val size = u32Long()
            check(size <= buffer.remaining().toLong()) { "JNI byte field exceeds its envelope" }
            return fixed(size.toInt())
        }
        fun text(): String {
            val value = bytes()
            return StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(value))
                .toString()
        }
        fun u128(): CitizenU128 = CitizenU128(buffer.long, buffer.long)
        fun block(): CitizenBlockRef = CitizenBlockRef(
            fixed(32),
            u64Text(),
            oneBasedEnum(CitizenFinality.entries, "finality"),
        )

        fun balance(): CitizenAccountBalance = CitizenAccountBalance(block(), fixed(32), u128(), u128(), u128())

        fun walletProfile(): CitizenWalletProfile? {
            if (!bool()) return null
            val origin = oneBasedEnum(CitizenWalletOrigin.entries, "wallet origin")
            val walletIndex = u32Long()
            val created = u64Text()
            val master = fixed(32)
            val active = fixed(32)
            val count = boundedCount(1990, "wallet account count")
            val accounts = walletAccounts(count)
            return CitizenWalletProfile(origin, walletIndex, created, master, active, accounts)
        }

        fun walletAccounts(): List<CitizenWalletAccount> =
            walletAccounts(boundedCount(1990, "wallet account result count"))

        private fun walletAccounts(count: Int): List<CitizenWalletAccount> =
            ArrayList<CitizenWalletAccount>(count).also { accounts ->
                repeat(count) {
                    accounts += CitizenWalletAccount(
                        index = boundedU32Long(1989, "wallet account index"),
                        accountId = fixed(32),
                        ss58Address = text(),
                        name = if (bool()) text() else null,
                        createdAtMillis = u64Text(),
                        active = bool(),
                    )
                }
            }

        fun execution(): CitizenExecution {
            val status = oneBasedEnum(CitizenExecutionStatus.entries, "execution status")
            val reason = u32Long()
            val block = if (bool()) block() else null
            val index = if (bool()) u32Long() else null
            val hasModule = bool()
            val pallet = if (hasModule) u32Long() else null
            val error = if (hasModule) u32Long() else null
            return CitizenExecution(status, reason, block, index, pallet, error)
        }

        fun walletTransfer(): CitizenWalletTransfer = CitizenWalletTransfer(
            fixed(32),
            oneBasedEnum(CitizenTransferResolution.entries, "transfer resolution"),
            if (bool()) execution() else null,
            if (bool()) text() else null,
        )

        fun history(): CitizenTransactionHistory {
            val revision = u64Text()
            val cursorCount = boundedCount(1990, "history cursor count")
            val cursors = ArrayList<CitizenHistoryCursor>(cursorCount)
            repeat(cursorCount) {
                cursors += CitizenHistoryCursor(fixed(32), block(), block())
            }
            val recordCount = boundedCount(100_000, "history record count")
            val records = ArrayList<CitizenHistoryRecord>(recordCount)
            repeat(recordCount) {
                records += CitizenHistoryRecord(
                    fixed(32), fixed(32), u64Text(), fixed(32), u128(),
                    oneBasedEnum(CitizenHistoryStatus.entries, "history status"),
                    if (bool()) block() else null,
                    if (bool()) execution() else null,
                    u64Text(), u64Text(), bytes(), if (bool()) text() else null,
                )
            }
            val transferCount = boundedCount(100_000, "finalized transfer count")
            val transfers = ArrayList<CitizenFinalizedTransfer>(transferCount)
            repeat(transferCount) {
                transfers += CitizenFinalizedTransfer(
                    fixed(32), fixed(32), fixed(32), u128(), block(), u32Long(),
                    if (bool()) u32Long() else null,
                    oneBasedEnum(CitizenTransferDirection.entries, "transfer direction"),
                    text(), text(), bytes(),
                )
            }
            return CitizenTransactionHistory(revision, cursors, records, transfers)
        }

        fun boundedCount(maximum: Int, label: String): Int {
            val value = u32Long()
            check(value <= maximum.toLong()) { "$label exceeds $maximum" }
            return value.toInt()
        }

        fun boundedU32Long(maximum: Long, label: String): Long {
            val value = u32Long()
            check(value <= maximum) { "$label exceeds $maximum" }
            return value
        }

        fun <T> oneBasedEnum(values: List<T>, label: String): T {
            val value = u32Long()
            check(value in 1..values.size.toLong()) { "$label is invalid: $value" }
            return values[(value - 1).toInt()]
        }

        fun <T> zeroBasedEnum(values: List<T>, label: String): T {
            val value = u32Long()
            check(value < values.size.toLong()) { "$label is invalid: $value" }
            return values[value.toInt()]
        }

        fun finish() = check(!buffer.hasRemaining()) { "JNI result has trailing bytes" }
    }

    private const val VERSION = 1
}
