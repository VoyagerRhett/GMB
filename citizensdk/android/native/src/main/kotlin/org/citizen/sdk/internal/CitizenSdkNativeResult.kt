@file:kotlin.jvm.JvmSynthetic

package org.citizen.sdk.internal

import org.citizen.sdk.CitizenAccountBalance
import org.citizen.sdk.CitizenAccountNonce
import org.citizen.sdk.CitizenBlockRef
import org.citizen.sdk.CitizenFeeSnapshot
import org.citizen.sdk.CitizenSignature
import org.citizen.sdk.CitizenTransactionHistory
import org.citizen.sdk.CitizenWalletAccount
import org.citizen.sdk.CitizenWalletProfile
import org.citizen.sdk.CitizenWalletTransfer

internal sealed class CitizenSdkNativeResult {
    data object Empty : CitizenSdkNativeResult()
    class Block(val value: CitizenBlockRef) : CitizenSdkNativeResult()
    class Balance(val value: CitizenAccountBalance) : CitizenSdkNativeResult()
    class Balances(val value: List<CitizenAccountBalance>) : CitizenSdkNativeResult()
    class Nonce(val value: CitizenAccountNonce) : CitizenSdkNativeResult()
    class Fee(val value: CitizenFeeSnapshot) : CitizenSdkNativeResult()
    class Profile(val value: CitizenWalletProfile?) : CitizenSdkNativeResult()
    class Accounts(val value: List<CitizenWalletAccount>) : CitizenSdkNativeResult()
    class Signature(val value: CitizenSignature) : CitizenSdkNativeResult()
    class Prepared(@get:JvmSynthetic val token: Long) : CitizenSdkNativeResult()
    class Transfer(val value: CitizenWalletTransfer) : CitizenSdkNativeResult()
    class History(val value: CitizenTransactionHistory) : CitizenSdkNativeResult()
    class QrReview(val token: Long, val json: String) : CitizenSdkNativeResult()
    class QrSigned(val value: org.citizen.sdk.CitizenQrDocument) : CitizenSdkNativeResult()
}
