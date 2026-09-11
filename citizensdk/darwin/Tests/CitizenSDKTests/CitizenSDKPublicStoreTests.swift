import Foundation
import SQLite3
import XCTest
@testable import CitizenSDK

final class CitizenSDKPublicStoreTests: XCTestCase {
    func testMalformedPersistentRevisionFailsWithoutTrappingOrWriting() throws {
        // A numeric-looking TEXT literal is converted by this column's SQLite
        // INTEGER affinity, so use non-numeric TEXT to preserve the malformed
        // storage class that the decoder must reject.
        for literal in ["-1", "0", "1.5", "'broken'"] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try CitizenSDKPublicStore(directory: directory)
            store.close()
            try corruptRevision(directory.appendingPathComponent("public-state-v1.sqlite3"),
                                "INSERT INTO singleton_records(domain, revision, record) VALUES(1, \(literal), X'01')")
            let reopened = try CitizenSDKPublicStore(directory: directory)
            XCTAssertThrowsError(try reopened.chainDatabaseLoad(), literal)
            XCTAssertThrowsError(try reopened.chainDatabaseCAS(expected: 0, candidate: Data([2])), literal)
            reopened.close()
        }
    }
    func testHostNamespacesDoNotShareChainOrHistoryState() throws {
        let support = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let firstRoot = try CitizenSDKHostBridge.storageRoot(applicationSupport: support, applicationID: "org.example.first")
        let secondRoot = try CitizenSDKHostBridge.storageRoot(applicationSupport: support, applicationID: "org.example.second")
        let first = try CitizenSDKPublicStore(directory: firstRoot.appendingPathComponent("public"))
        let second = try CitizenSDKPublicStore(directory: secondRoot.appendingPathComponent("public"))
        defer { first.close(); second.close() }
        _ = try first.chainDatabaseCAS(expected: 0, candidate: Data([1]))
        _ = try first.transactionHistoryMutate(expected: 0,
                                               bytes: historyMutation(identity: 2, record: Data([2])))
        XCTAssertFalse(try second.chainDatabaseLoad().present)
        XCTAssertEqual(try second.transactionHistoryQuery(historyIndexQuery()).revision, 0)
        XCTAssertEqual(try first.transactionHistoryQuery(historyIndexQuery()).revision, 1)
        _ = try second.chainDatabaseCAS(expected: 0, candidate: Data([3]))
        XCTAssertEqual(try first.chainDatabaseLoad().record, Data([1]))
        XCTAssertEqual(try second.chainDatabaseLoad().record, Data([3]))
    }

    func testSingletonCASAndRuntimeCacheRoundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CitizenSDKPublicStore(directory: directory)
        defer { store.close() }

        XCTAssertFalse(try store.chainDatabaseLoad().present)
        let first = try store.chainDatabaseCAS(expected: 0, candidate: Data([1, 2]))
        XCTAssertEqual(first.revision, 1)
        XCTAssertEqual(first.record, Data([1, 2]))
        XCTAssertEqual(try store.chainDatabaseCAS(expected: 0, candidate: Data([3])).errorCode, .conflict)

        let hash = Data(repeating: 4, count: 32)
        try store.runtimeCacheStore(hash: hash, candidate: Data([5]))
        XCTAssertEqual(try store.runtimeCacheLoad(hash: hash).record, Data([5]))
        try store.runtimeCacheDelete(hash: hash)
        XCTAssertFalse(try store.runtimeCacheLoad(hash: hash).present)
    }

    func testRuntimeCacheAtomicallyRetainsLatestSixtyFourWrites() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CitizenSDKPublicStore(directory: directory)
        defer { store.close() }

        for index in 0..<80 {
            try store.runtimeCacheStore(hash: blockHash(index), candidate: Data([UInt8(index)]))
        }
        for index in 0..<80 {
            XCTAssertEqual(try store.runtimeCacheLoad(hash: blockHash(index)).present, index >= 16)
        }

        // REPLACE promotes the existing key to newest without creating a 65th row.
        try store.runtimeCacheStore(hash: blockHash(16), candidate: Data([99]))
        try store.runtimeCacheStore(hash: blockHash(80), candidate: Data([80]))
        XCTAssertTrue(try store.runtimeCacheLoad(hash: blockHash(16)).present)
        XCTAssertFalse(try store.runtimeCacheLoad(hash: blockHash(17)).present)
        XCTAssertTrue(try store.runtimeCacheLoad(hash: blockHash(80)).present)

        let database = directory.appendingPathComponent("public-state-v1.sqlite3")
        try executeSQL(
            database,
            "CREATE TRIGGER runtime_cache_prune_failure BEFORE DELETE ON runtime_cache " +
                "BEGIN SELECT RAISE(ABORT, 'test prune failure'); END"
        )
        XCTAssertThrowsError(
            try store.runtimeCacheStore(hash: blockHash(81), candidate: Data([81]))
        )
        XCTAssertFalse(try store.runtimeCacheLoad(hash: blockHash(81)).present)
        XCTAssertTrue(try store.runtimeCacheLoad(hash: blockHash(18)).present)
        try executeSQL(database, "DROP TRIGGER runtime_cache_prune_failure")
    }

    func testSQLiteFailureCodesNeverMeanAbsent() throws {
        for code in [SQLITE_BUSY, SQLITE_ERROR, SQLITE_CORRUPT] {
            XCTAssertThrowsError(try CitizenSDKSQLite.classifyStepCode(code)) { error in
                XCTAssertEqual((error as? CitizenSDKError)?.code, .storage)
            }
        }
        XCTAssertTrue(try CitizenSDKSQLite.classifyStepCode(SQLITE_ROW))
        XCTAssertFalse(try CitizenSDKSQLite.classifyStepCode(SQLITE_DONE))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func blockHash(_ index: Int) -> Data {
        var bytes = Data(repeating: 0, count: 32)
        bytes[31] = UInt8(index)
        return bytes
    }

    private func historyIndexQuery() -> Data {
        var bytes = Data("THQ1".utf8); bytes.append(1)
        append(UInt64.max, to: &bytes); append(UInt32(0), to: &bytes)
        bytes.append(Data(repeating: 0, count: 16)); bytes.append(0)
        append(UInt64(0), to: &bytes); bytes.append(Data(repeating: 0, count: 16))
        return bytes
    }

    private func historyMutation(identity: UInt8, record: Data) -> Data {
        let weight = UInt64(max(1, record.count))
        var bytes = Data("THM1".utf8)
        append(UInt64(1), to: &bytes); append(UInt32(1), to: &bytes); append(weight, to: &bytes)
        append(UInt32(1), to: &bytes); append(weight, to: &bytes)
        append(UInt32(0), to: &bytes); append(UInt32(1), to: &bytes)
        bytes.append(identity); bytes.append(Data(repeating: 0, count: 15))
        append(UInt64(1), to: &bytes); append(UInt64(1), to: &bytes); append(weight, to: &bytes)
        bytes.append(0); bytes.append(0); append(UInt32(record.count), to: &bytes); bytes.append(record)
        return bytes
    }

    private func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private func corruptRevision(_ file: URL, _ sql: String) throws {
        try executeSQL(file, sql)
    }

    private func executeSQL(_ file: URL, _ sql: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        guard let database else { return XCTFail("SQLite fixture did not open") }
        defer { sqlite3_close_v2(database) }
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
    }
}
