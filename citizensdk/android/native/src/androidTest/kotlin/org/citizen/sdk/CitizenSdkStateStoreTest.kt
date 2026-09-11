package org.citizen.sdk

import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import org.citizen.sdk.internal.CitizenSdkPublicStore
import org.citizen.sdk.internal.CitizenSdkSecureStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class CitizenSdkStateStoreTest {
    @Test
    fun `chain state CAS returns exact durable revision`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val directory = File(context.noBackupFilesDir, "citizensdk-test/public-${System.nanoTime()}")
        CitizenSdkPublicStore(directory).use { store ->
            assertFalse(store.chainDatabaseLoad().present)
            val first = store.chainDatabaseCompareAndSwap(0, byteArrayOf(1, 2, 3))
            assertTrue(first.present)
            assertEquals(1L, first.revision)
            assertEquals(8, store.chainDatabaseCompareAndSwap(0, byteArrayOf(4)).errorCode)
        }
    }

    @Test
    fun `runtime cache atomically retains latest sixty four writes`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val directory = File(context.noBackupFilesDir, "citizensdk-test/runtime-${System.nanoTime()}")
        CitizenSdkPublicStore(directory).use { store ->
            for (index in 0 until 80) {
                store.runtimeCacheStore(blockHash(index), byteArrayOf(index.toByte()))
            }
            for (index in 0 until 80) {
                assertEquals(index >= 16, store.runtimeCacheLoad(blockHash(index)).present)
            }

            // REPLACE 必须把已有 key 提升为最新，而不是增加第 65 条。
            store.runtimeCacheStore(blockHash(16), byteArrayOf(99))
            store.runtimeCacheStore(blockHash(80), byteArrayOf(80))
            assertTrue(store.runtimeCacheLoad(blockHash(16)).present)
            assertFalse(store.runtimeCacheLoad(blockHash(17)).present)
            assertTrue(store.runtimeCacheLoad(blockHash(80)).present)

            val databaseFile = File(directory, "public-state-v1.sqlite3")
            SQLiteDatabase.openDatabase(databaseFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE).use { database ->
                database.execSQL(
                    "CREATE TRIGGER runtime_cache_prune_failure BEFORE DELETE ON runtime_cache " +
                        "BEGIN SELECT RAISE(ABORT, 'test prune failure'); END",
                )
            }
            var pruneFailed = false
            try {
                store.runtimeCacheStore(blockHash(81), byteArrayOf(81))
            } catch (_: Throwable) {
                pruneFailed = true
            }
            assertTrue(pruneFailed)
            assertFalse(store.runtimeCacheLoad(blockHash(81)).present)
            assertTrue(store.runtimeCacheLoad(blockHash(18)).present)
            SQLiteDatabase.openDatabase(databaseFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE).use { database ->
                database.execSQL("DROP TRIGGER runtime_cache_prune_failure")
            }
        }
    }

    @Test
    fun `retired generation cannot be resurrected or rebound`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val directory = File(context.noBackupFilesDir, "citizensdk-test/secure-${System.nanoTime()}")
        val generation = ByteArray(16) { 1 }
        val provisioning = ByteArray(16) { 2 }
        CitizenSdkSecureStore(directory).use { store ->
            assertTrue(store.ensureGeneration(0, generation, provisioning))
            assertFalse(store.ensureGeneration(0, generation, ByteArray(16) { 3 }))
            store.retireGeneration(0, generation, ByteArray(16) { 4 })
            assertFalse(store.ensureGeneration(0, generation, provisioning))
        }
    }


    private fun blockHash(index: Int): ByteArray =
        ByteArray(32).also { bytes -> bytes[31] = index.toByte() }
}
