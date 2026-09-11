package org.citizen.sdk.internal

import android.database.sqlite.SQLiteDatabase
import java.io.File
import java.util.Locale
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** Small no-backup SQLite owner with explicit transactional serialization. */
internal abstract class CitizenSdkSqlite(
    directory: File,
    fileName: String,
    private val schemaVersion: Int = 1,
    private val incrementalVacuum: Boolean = false,
) : AutoCloseable {
    protected val lock = ReentrantLock(true)
    protected val database: SQLiteDatabase

    init {
        check(directory.exists() || directory.mkdirs()) { "unable to create CitizenSDK storage directory" }
        val file = File(directory, fileName)
        database = SQLiteDatabase.openOrCreateDatabase(file, null)
        lock.withLock {
            val version = database.rawQuery("PRAGMA user_version", null).use { cursor ->
                check(cursor.moveToFirst()) { "CitizenSDK schema version is unavailable" }
                cursor.getInt(0)
            }
            val objectCount = database.rawQuery(
                "SELECT count(*) FROM sqlite_master WHERE name NOT GLOB 'sqlite_*'",
                null,
            ).use { cursor ->
                check(cursor.moveToFirst()) { "CitizenSDK schema inventory is unavailable" }
                cursor.getInt(0)
            }
            val initialize = version == 0 && objectCount == 0
            check(initialize || version == schemaVersion) {
                "CitizenSDK database schema is unsupported; clear the old development database"
            }
            if (initialize) {
                if (incrementalVacuum) database.execSQL("PRAGMA auto_vacuum=INCREMENTAL")
                database.beginTransaction()
                try {
                    createSchema(database)
                    database.execSQL("PRAGMA user_version=$schemaVersion")
                    database.setTransactionSuccessful()
                } finally {
                    database.endTransaction()
                }
            }
            verifySchema(database)
            val autoVacuum = database.rawQuery("PRAGMA auto_vacuum", null).use { cursor ->
                check(cursor.moveToFirst()) { "CitizenSDK auto-vacuum mode is unavailable" }
                cursor.getInt(0)
            }
            check(autoVacuum == if (incrementalVacuum) 2 else 0) {
                "CitizenSDK database auto-vacuum policy differs from its fixed schema"
            }
            database.execSQL("PRAGMA journal_mode=WAL")
            database.execSQL("PRAGMA synchronous=FULL")
            database.execSQL("PRAGMA foreign_keys=ON")
            database.execSQL("PRAGMA busy_timeout=5000")
        }
    }

    protected abstract fun createSchema(database: SQLiteDatabase)

    /** Each concrete store returns the exact SQL it executes, so an existing
     * same-version database cannot smuggle in missing, changed, or extra objects. */
    protected open fun schemaStatements(): List<String> = emptyList()

    private fun verifySchema(database: SQLiteDatabase) {
        val expected = schemaStatements()
        if (expected.isEmpty()) return
        val count = database.rawQuery(
            "SELECT count(*) FROM sqlite_master WHERE name NOT GLOB 'sqlite_*'",
            null,
        ).use { cursor -> check(cursor.moveToFirst()); cursor.getInt(0) }
        check(count == expected.size) { "CitizenSDK SQLite schema contains unexpected objects" }
        expected.forEach { sql ->
            val tablePrefix = "CREATE TABLE IF NOT EXISTS "
            val indexPrefix = "CREATE INDEX IF NOT EXISTS "
            val table = sql.startsWith(tablePrefix)
            val prefix = if (table) tablePrefix else indexPrefix
            check(table || sql.startsWith(indexPrefix)) { "invalid embedded CitizenSDK schema" }
            val tail = sql.substring(prefix.length)
            val name = tail.substringBefore(if (table) "(" else " ").trim()
            val actual = database.rawQuery(
                "SELECT sql FROM sqlite_master WHERE type = ? AND name = ?",
                arrayOf(if (table) "table" else "index", name),
            ).use { cursor ->
                check(cursor.moveToFirst()) { "CitizenSDK SQLite schema object is missing" }
                cursor.getString(0)
            }
            fun canonical(value: String) = value.lowercase(Locale.ROOT)
                .replace(Regex("\\s+"), "")
                .replace("ifnotexists", "")
            check(canonical(actual) == canonical(sql)) {
                "CitizenSDK SQLite schema differs from its fixed contract"
            }
        }
    }

    protected fun <T> transaction(block: (SQLiteDatabase) -> T): T = lock.withLock {
        database.beginTransaction()
        try {
            block(database).also { database.setTransactionSuccessful() }
        } finally {
            database.endTransaction()
        }
    }

    override fun close() = lock.withLock { database.close() }
}
