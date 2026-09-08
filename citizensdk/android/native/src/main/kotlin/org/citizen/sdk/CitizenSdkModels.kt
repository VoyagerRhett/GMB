package org.citizen.sdk

import java.math.BigInteger

enum class CitizenSdkLifecycle { CREATED, IMPORTING_STATE, STARTING, RUNNING, START_FAILED, STOPPED, DISPOSED }
enum class CitizenFinality { BEST, FINALIZED }
enum class CitizenWalletOrigin { CREATED, IMPORTED }
enum class CitizenTransferResolution { FINALIZED_SUCCESS, FINALIZED_FAILED, POOL_REJECTED }
enum class CitizenHistoryStatus { PENDING, IN_BLOCK, POOL_REJECTED, FINALIZED_SUCCESS, FINALIZED_FAILED }
enum class CitizenTransferDirection { OUTGOING, INCOMING }
enum class CitizenExecutionStatus { SUCCESS, FAILED, UNVERIFIED }

enum class CitizenCapabilityName {
    CHAIN_READ,
    TRANSACTION_BUILD,
    TRANSACTION_SUBMIT,
    TRANSACTION_VERIFY,
    WALLET_PROFILE,
    LOCAL_SIGNING,
    HARDWARE_VAULT,
    USER_AUTHENTICATION,
    HISTORY,
    BACKGROUND_SYNC,
}

enum class CitizenCapabilityReason {
    NONE,
    BUILD_UNSUPPORTED,
    DEVICE_UNAVAILABLE,
    HOST_DISABLED,
    ENGINE_NOT_RUNNING,
    DEPENDENCY_NOT_READY,
    USER_AUTHENTICATION_REQUIRED,
    VAULT_LOCKED,
    CHAIN_STARTING,
    CHAIN_UNSYNCED,
    STORAGE_UNAVAILABLE,
}

/** Exact unsigned 128-bit value with a Java-safe decimal representation. */
class CitizenU128(decimal: String) {
    val decimal: String
    @get:JvmSynthetic
    internal val low: Long
    @get:JvmSynthetic
    internal val high: Long

    init {
        // A canonical u128 has at most 39 decimal digits. Reject by O(1)
        // String length before regex or BigInteger performs proportional work.
        require(decimal.length in 1..MAX_DECIMAL_DIGITS) { "u128 is out of range" }
        require(decimal.matches(Regex("0|[1-9][0-9]*"))) { "u128 must be canonical unsigned decimal" }
        val value = BigInteger(decimal)
        require(value.bitLength() <= 128) { "u128 is out of range" }
        this.decimal = value.toString()
        low = value.and(MASK_64).toLong()
        high = value.shiftRight(64).toLong()
    }

    internal constructor(low: Long, high: Long) : this(
        unsignedLong(high).shiftLeft(64).or(unsignedLong(low)).toString(),
    )

    override fun equals(other: Any?): Boolean = other is CitizenU128 && decimal == other.decimal
    override fun hashCode(): Int = decimal.hashCode()
    override fun toString(): String = decimal

    companion object {
        private const val MAX_DECIMAL_DIGITS = 39
        private val MASK_64 = BigInteger.ONE.shiftLeft(64).subtract(BigInteger.ONE)
        private fun unsignedLong(value: Long): BigInteger =
            BigInteger.valueOf(value and Long.MAX_VALUE).let {
                if (value < 0) it.setBit(63) else it
            }
    }
}

class CitizenBlockRef(
    hash: ByteArray,
    val number: String,
    val finality: CitizenFinality,
) {
    private val hashValue = hash.requireSize(32, "block hash")
    fun hash(): ByteArray = hashValue.clone()
}

class CitizenCapabilityStatus(
    val name: CitizenCapabilityName,
    val reason: CitizenCapabilityReason,
    val supported: Boolean,
    val available: Boolean,
    val enabled: Boolean,
    val ready: Boolean,
)

class CitizenSdkCapabilities(
    val revision: String,
    statuses: List<CitizenCapabilityStatus>,
) {
    val statuses: List<CitizenCapabilityStatus> = statuses.toList()
}

class CitizenAccountBalance(
    val block: CitizenBlockRef,
    accountId: ByteArray,
    val freeFen: CitizenU128,
    val reservedFen: CitizenU128,
    val totalFen: CitizenU128,
) {
    private val accountIdValue = accountId.requireSize(32, "accountId")
    fun accountId(): ByteArray = accountIdValue.clone()
}

class CitizenAccountNonce(
    val bestBlock: CitizenBlockRef,
    accountId: ByteArray,
    val nonce: String,
) {
    private val accountIdValue = accountId.requireSize(32, "accountId")
    fun accountId(): ByteArray = accountIdValue.clone()
}

class CitizenFeeSnapshot(
    val bestBlock: CitizenBlockRef,
    val feeRateParts: Long,
    val minimumFeeFen: CitizenU128,
    val existentialDepositFen: CitizenU128,
)

class CitizenWalletAccount(
    val index: Long,
    accountId: ByteArray,
    val ss58Address: String,
    val name: String?,
    val createdAtMillis: String,
    val active: Boolean,
) {
    private val accountIdValue = accountId.requireSize(32, "accountId")
    fun accountId(): ByteArray = accountIdValue.clone()
}

class CitizenWalletProfile(
    val origin: CitizenWalletOrigin,
    val walletIndex: Long,
    val createdAtMillis: String,
    masterAccountId: ByteArray,
    activeAccountId: ByteArray,
    accounts: List<CitizenWalletAccount>,
) {
    private val masterValue = masterAccountId.requireSize(32, "masterAccountId")
    private val activeValue = activeAccountId.requireSize(32, "activeAccountId")
    val accounts: List<CitizenWalletAccount> = accounts.toList()
    fun masterAccountId(): ByteArray = masterValue.clone()
    fun activeAccountId(): ByteArray = activeValue.clone()
}

class CitizenSignature(signature: ByteArray) {
    private val value = signature.requireSize(64, "sr25519 signature")
    fun bytes(): ByteArray = value.clone()
}

class CitizenExecution(
    val status: CitizenExecutionStatus,
    val reasonOrDispatchVariant: Long,
    val block: CitizenBlockRef?,
    val extrinsicIndex: Long?,
    val palletIndex: Long?,
    val errorIndex: Long?,
)

class CitizenWalletTransfer(
    transactionHash: ByteArray,
    val resolution: CitizenTransferResolution,
    val execution: CitizenExecution?,
    val poolRejectionReason: String?,
) {
    private val hashValue = transactionHash.requireSize(32, "transactionHash")
    fun transactionHash(): ByteArray = hashValue.clone()
}

class CitizenHistoryCursor(
    accountId: ByteArray,
    val trackingStartBlock: CitizenBlockRef,
    val lastSyncedBlock: CitizenBlockRef,
) {
    private val accountValue = accountId.requireSize(32, "accountId")
    fun accountId(): ByteArray = accountValue.clone()
}

class CitizenHistoryRecord(
    accountId: ByteArray,
    transactionHash: ByteArray,
    val nonce: String,
    destinationAccountId: ByteArray,
    val amountFen: CitizenU128,
    val status: CitizenHistoryStatus,
    val block: CitizenBlockRef?,
    val execution: CitizenExecution?,
    val createdAtMillis: String,
    val updatedAtMillis: String,
    remark: ByteArray,
    val poolRejectionReason: String?,
) {
    private val accountValue = accountId.requireSize(32, "accountId")
    private val transactionValue = transactionHash.requireSize(32, "transactionHash")
    private val destinationValue = destinationAccountId.requireSize(32, "destinationAccountId")
    private val remarkValue = remark.clone()
    fun accountId(): ByteArray = accountValue.clone()
    fun transactionHash(): ByteArray = transactionValue.clone()
    fun destinationAccountId(): ByteArray = destinationValue.clone()
    fun remark(): ByteArray = remarkValue.clone()
}

class CitizenFinalizedTransfer(
    trackedAccountId: ByteArray,
    fromAccountId: ByteArray,
    toAccountId: ByteArray,
    val amountFen: CitizenU128,
    val block: CitizenBlockRef,
    val eventRecordIndex: Long,
    val extrinsicIndex: Long?,
    val direction: CitizenTransferDirection,
    val sourcePallet: String,
    val remarkDisplay: String,
    remarkBytes: ByteArray,
) {
    private val trackedValue = trackedAccountId.requireSize(32, "trackedAccountId")
    private val fromValue = fromAccountId.requireSize(32, "fromAccountId")
    private val toValue = toAccountId.requireSize(32, "toAccountId")
    private val remarkValue = remarkBytes.clone()
    fun trackedAccountId(): ByteArray = trackedValue.clone()
    fun fromAccountId(): ByteArray = fromValue.clone()
    fun toAccountId(): ByteArray = toValue.clone()
    fun remarkBytes(): ByteArray = remarkValue.clone()
}

class CitizenTransactionHistory(
    val revision: String,
    cursors: List<CitizenHistoryCursor>,
    records: List<CitizenHistoryRecord>,
    transfers: List<CitizenFinalizedTransfer>,
) {
    val cursors: List<CitizenHistoryCursor> = cursors.toList()
    val records: List<CitizenHistoryRecord> = records.toList()
    val transfers: List<CitizenFinalizedTransfer> = transfers.toList()
}

internal fun ByteArray.requireSize(expected: Int, label: String): ByteArray {
    require(size == expected) { "$label must contain exactly $expected bytes" }
    return clone()
}

/** 仅投影 Rust 模块位集合；依赖与非法组合由核心统一判定。 */
object CitizenSdkModules {
    const val WALLET = 1
    const val SIGNING = 2
    const val CHAIN = 4
    const val TRANSACTIONS = 8
    const val HISTORY = 16
    const val QR = 32
    const val FULL = 63
}
