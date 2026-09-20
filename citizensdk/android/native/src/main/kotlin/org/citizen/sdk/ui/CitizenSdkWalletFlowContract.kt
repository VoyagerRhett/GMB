package org.citizen.sdk.ui

import org.citizen.sdk.CitizenSdkException
import org.citizen.sdk.CitizenSdkInputLimits
import org.citizen.sdk.CitizenWalletProfile

/** Public, secret-free contract for the SDK-owned Android wallet flow. */
object CitizenSdkWalletFlowContract {
    private fun validPresentationText(value: String): Boolean =
        value == value.trim() && value.codePointCount(0, value.length) in 1..256 &&
            value.none { character -> character.code <= 0x1f || character.code == 0x7f }

    data class InitializationContent(
        val walletAccountRoleText: String,
        val walletAuthorizationText: String,
        val walletCompletionText: String,
        val walletBackupText: String,
        val walletColdAccountText: String,
    ) {
        init {
            require(listOf(
                walletAccountRoleText,
                walletAuthorizationText,
                walletCompletionText,
                walletBackupText,
                walletColdAccountText,
            ).all(::validPresentationText)) { "wallet initialization presentation text is invalid" }
        }
    }

    sealed class Request {
        class Initialize(
            val wordCount: Int = 12,
            val content: InitializationContent,
        ) : Request() {
            init { require(wordCount in listOf(12, 18, 24)) { "wordCount must be 12, 18 or 24" } }
        }
        class ImportColdAccount(val walletColdAccountText: String) : Request() {
            init { require(validPresentationText(walletColdAccountText)) }
        }
        class Create(val wordCount: Int = 12) : Request() {
            init { require(wordCount in listOf(12, 18, 24)) { "wordCount must be 12, 18 or 24" } }
        }

        class Import : Request()

        class AddAccounts(indices: List<Int>) : Request() {
            val indices: List<Int>

            init {
                require(indices.size in 1..CitizenSdkInputLimits.MAX_ADD_ACCOUNT_INDICES) {
                    "indices must contain 1..${CitizenSdkInputLimits.MAX_ADD_ACCOUNT_INDICES} items"
                }
                this.indices = indices.toList()
                require(this.indices.size == this.indices.toSet().size) { "indices must be unique" }
                require(this.indices.all { it in 1..1989 }) { "account index must be in 1..1989" }
            }
        }
    }

    sealed class Result {
        class Completed(val profile: CitizenWalletProfile?) : Result()
        data object Cancelled : Result()
        class Failed(val error: CitizenSdkException) : Result()
    }

    fun interface Callback {
        fun onResult(result: Result)
    }
}
