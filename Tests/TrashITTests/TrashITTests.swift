import XCTest
@testable import TrashIT

final class TrashITTests: XCTestCase {
    func testVolumeCapacityMath() {
        let capacity = VolumeCapacity(total: 1_000, available: 250)
        XCTAssertEqual(capacity.used, 750)
        XCTAssertEqual(capacity.usedFraction, 0.75, accuracy: 0.001)
    }

    func testSnapshotTotalsAllocatedBytes() {
        let items = [
            makeItem(name: "A", bytes: 10),
            makeItem(name: "B", bytes: 25)
        ]
        let snapshot = ScanSnapshot(date: Date(), items: items, issues: [])
        XCTAssertEqual(snapshot.totalBytes, 35)
    }

    func testUnsafeCategoryCannotBeDeletedDirectly() {
        let item = CleanupItem(
            name: "Document",
            url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/example.txt"),
            category: .oldFiles,
            safety: .reviewRequired,
            action: .deleteRegeneratable,
            allocatedBytes: 1,
            reason: "Test",
            consequence: "Test",
            source: "test"
        )
        XCTAssertThrowsError(try SafetyPolicy.validate(item)) { error in
            XCTAssertEqual(error as? SafetyPolicyError, .unsafeDirectDeletion)
        }
    }

    func testReceiptRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrashITTests-\(UUID().uuidString)", isDirectory: true)
        let store = ReceiptStore(directory: directory)
        let receipt = CleanupReceipt(
            id: UUID(),
            startedAt: Date(),
            finishedAt: Date(),
            entries: [
                CleanupReceipt.Entry(
                    id: UUID(),
                    itemName: "Cache",
                    originalPath: "/tmp/cache",
                    bytes: 42,
                    action: .deleteRegeneratable,
                    succeeded: true,
                    message: "Deleted"
                )
            ]
        )

        try await store.save(receipt)
        let loaded = await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, receipt.id)
        XCTAssertEqual(loaded.first?.processedBytes, 42)
    }

    func testScannerPublishesResultsAsEachCheckCompletes() async {
        let scanner = StorageScanner(scanners: [
            StubScanner(id: "slow", delayNanoseconds: 80_000_000, itemName: "Slow"),
            StubScanner(id: "fast", delayNanoseconds: 5_000_000, itemName: "Fast")
        ])
        let stream = await scanner.progressStream(settings: .defaults)
        var progress: [ScanProgress] = []
        for await update in stream { progress.append(update) }

        XCTAssertEqual(progress.count, 2)
        XCTAssertEqual(progress.first?.scannerID, "fast")
        XCTAssertEqual(progress.first?.completedScanners, 1)
        XCTAssertEqual(progress.last?.completedScanners, 2)
        XCTAssertEqual(progress.last?.totalScanners, 2)
    }

    func testExternalProcessHasATimeout() {
        XCTAssertThrowsError(try ProcessRunner.run(
            URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            timeout: 0.05
        )) { error in
            XCTAssertTrue(error is ProcessRunnerError)
        }
    }

    func testOrdinaryFilesystemCleanupUsesBin() {
        XCTAssertTrue(CleanupAction.deleteRegeneratable.usesBin)
        XCTAssertTrue(CleanupAction.moveToTrash.usesBin)
        XCTAssertEqual(CleanupAction.deleteRegeneratable.title, "Move to Bin")
        XCTAssertFalse(CleanupAction.deletePermanently.usesBin)
    }

    func testRuntimeDeletionUsesDiskImageUUIDAndKeepsLatestPerPlatform() throws {
        let oldIOSUUID = "9238BCB6-DB01-436E-BE44-59B2F9090EE0"
        let newIOSUUID = "FED2B73D-751E-4FA6-8668-2B174D3BBF22"
        let watchUUID = "0971E4EF-2B5D-4E25-B0AB-CFCB62289BCA"
        let images = [
            runtimeImage(uuid: oldIOSUUID, platform: "com.apple.platform.iphonesimulator", version: "18.0", build: "22A3351", bytes: 8_361_951_702),
            runtimeImage(uuid: newIOSUUID, platform: "com.apple.platform.iphonesimulator", version: "18.3.1", build: "22D8075", bytes: 8_708_125_252),
            runtimeImage(uuid: watchUUID, platform: "com.apple.platform.watchsimulator", version: "26.5", build: "23T570", bytes: 3_935_033_546)
        ]

        let items = SimulatorScanner().runtimeItems(images, settings: .defaults, budget: ScanBudget())
        let oldIOS = try XCTUnwrap(items.first { $0.metadata["identifier"] == oldIOSUUID })
        let newIOS = try XCTUnwrap(items.first { $0.metadata["identifier"] == newIOSUUID })
        let watch = try XCTUnwrap(items.first { $0.metadata["identifier"] == watchUUID })

        XCTAssertEqual(oldIOS.action, .deleteSimulatorRuntime(identifier: oldIOSUUID))
        XCTAssertEqual(oldIOS.allocatedBytes, 8_361_951_702)
        XCTAssertTrue(oldIOS.defaultSelected)
        XCTAssertFalse(newIOS.defaultSelected)
        XCTAssertEqual(newIOS.metadata["keepRecommended"], "true")
        XCTAssertFalse(watch.defaultSelected, "watchOS must have its own keep-latest family")
    }

    func testRuntimeBundleIdentifierIsRejectedAsADeleteIdentifier() {
        let invalid = CleanupItem(
            name: "iOS 18.0",
            url: nil,
            category: .simulators,
            safety: .redownloadable,
            action: .deleteSimulatorRuntime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-0"),
            allocatedBytes: 1,
            reason: "Test",
            consequence: "Test",
            source: "test"
        )
        XCTAssertThrowsError(try SafetyPolicy.validate(invalid))
    }

    func testOverallScanTimeoutFinishesTheStream() async {
        let scanner = StorageScanner(
            scanners: [StubScanner(id: "stuck", delayNanoseconds: 2_000_000_000, itemName: "Late")],
            scanTimeoutNanoseconds: 40_000_000
        )
        let stream = await scanner.progressStream(settings: .defaults)
        var progress: [ScanProgress] = []
        for await update in stream { progress.append(update) }

        XCTAssertEqual(progress.count, 1)
        XCTAssertEqual(progress.first?.scannerID, "scan-timeout")
        XCTAssertEqual(progress.first?.result.issues.count, 1)
    }

    private func makeItem(name: String, bytes: Int64) -> CleanupItem {
        CleanupItem(
            name: name,
            url: nil,
            category: .xcode,
            safety: .regeneratable,
            action: .deleteRegeneratable,
            allocatedBytes: bytes,
            reason: "Test",
            consequence: "Test",
            source: "test"
        )
    }

    private func runtimeImage(
        uuid: String,
        platform: String,
        version: String,
        build: String,
        bytes: Int64
    ) -> SimulatorScanner.RuntimeImage {
        SimulatorScanner.RuntimeImage(
            build: build,
            deletable: true,
            identifier: uuid,
            kind: "Disk Image",
            lastUsedAt: "2025-01-01T00:00:00Z",
            platformIdentifier: platform,
            runtimeBundlePath: "/Library/Developer/CoreSimulator/Volumes/Test/Runtime.simruntime",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.Test",
            sizeBytes: bytes,
            state: "Ready",
            version: version
        )
    }
}

private struct StubScanner: CleanupScanning {
    let id: String
    let delayNanoseconds: UInt64
    let itemName: String

    func scan(settings: ScannerSettings) async -> ScanResult {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return ScanResult(items: [CleanupItem(
            name: itemName,
            url: nil,
            category: .xcode,
            safety: .regeneratable,
            action: .deleteRegeneratable,
            allocatedBytes: 1,
            reason: "Test",
            consequence: "Test",
            source: id
        )])
    }
}

extension SafetyPolicyError: Equatable {
    public static func == (lhs: SafetyPolicyError, rhs: SafetyPolicyError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}
