import XCTest
@testable import TrashITCore

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

    @MainActor
    func testSmartSelectionUsesRecommendationTagsAndReplacesSelection() {
        let regeneratable = makeItem(name: "Cache", bytes: 10, recommendations: [.lowRisk])
        let redownloadable = CleanupItem(
            name: "Runtime",
            url: nil,
            category: .simulators,
            safety: .redownloadable,
            action: .deleteRegeneratable,
            allocatedBytes: 20,
            reason: "Test",
            consequence: "Test",
            source: "test",
            recommendations: [.lowRisk]
        )
        let newestRuntime = CleanupItem(
            name: "Latest runtime",
            url: nil,
            category: .simulators,
            safety: .redownloadable,
            action: .deleteRegeneratable,
            allocatedBytes: 30,
            reason: "Test",
            consequence: "Test",
            source: "test"
        )
        let reviewRequired = CleanupItem(
            name: "Document",
            url: nil,
            category: .oldFiles,
            safety: .reviewRequired,
            action: .moveToTrash,
            allocatedBytes: 40,
            reason: "Test",
            consequence: "Test",
            source: "test"
        )
        let model = AppModel()
        model.snapshot = ScanSnapshot(
            date: Date(),
            items: [regeneratable, redownloadable, newestRuntime, reviewRequired],
            issues: []
        )
        model.selectedIDs = [reviewRequired.id]

        model.applySmartSelection(.safeCleanup)

        XCTAssertEqual(model.selectedIDs, [regeneratable.id, redownloadable.id])
        XCTAssertEqual(model.activeSmartSelection, .safeCleanup)
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
        XCTAssertTrue(oldIOS.recommendations.contains(.outdatedSimulator))
        XCTAssertTrue(oldIOS.recommendations.contains(.lowRisk))
        XCTAssertFalse(newIOS.recommendations.contains(.outdatedSimulator))
        XCTAssertFalse(watch.recommendations.contains(.outdatedSimulator), "watchOS must have its own keep-latest family")
    }

    func testRuntimeRecommendationsSeparateMajorsUnknownVersionsAndActiveRuntimes() throws {
        let iOS17Old = runtimeImage(uuid: "11111111-1111-1111-1111-111111111111", platform: "com.apple.platform.iphonesimulator", version: "17.0", build: "A", bytes: 1)
        let iOS17New = runtimeImage(uuid: "22222222-2222-2222-2222-222222222222", platform: "com.apple.platform.iphonesimulator", version: "17.5", build: "B", bytes: 1)
        let iOS18 = runtimeImage(uuid: "33333333-3333-3333-3333-333333333333", platform: "com.apple.platform.iphonesimulator", version: "18.0", build: "A", bytes: 1)
        let unknown = runtimeImage(uuid: "44444444-4444-4444-4444-444444444444", platform: "com.apple.platform.iphonesimulator", version: "Preview", build: "A", bytes: 1)
        let activeIdentifier = "com.apple.CoreSimulator.SimRuntime.Active"
        let active = SimulatorScanner.RuntimeImage(
            build: "A", deletable: true, identifier: "55555555-5555-5555-5555-555555555555", kind: "Disk Image",
            lastUsedAt: nil, platformIdentifier: "com.apple.platform.iphonesimulator", runtimeBundlePath: nil,
            runtimeIdentifier: activeIdentifier, sizeBytes: 1, state: "Ready", version: "17.1"
        )

        let items = SimulatorScanner().runtimeItems(
            [iOS17Old, iOS17New, iOS18, unknown, active],
            inUseRuntimeIdentifiers: [activeIdentifier],
            budget: ScanBudget()
        )
        func item(_ uuid: String) throws -> CleanupItem {
            try XCTUnwrap(items.first { $0.metadata["identifier"] == uuid })
        }
        XCTAssertTrue(try item(iOS17Old.identifier).recommendations.contains(.outdatedSimulator))
        XCTAssertFalse(try item(iOS17New.identifier).recommendations.contains(.outdatedSimulator))
        XCTAssertFalse(try item(iOS18.identifier).recommendations.contains(.outdatedSimulator))
        XCTAssertTrue(try item(unknown.identifier).recommendations.isEmpty)
        XCTAssertTrue(try item(active.identifier).recommendations.isEmpty)
    }

    @MainActor
    func testCategorySelectionChoosesOnlyRecommendationsInThatCategory() {
        let recommended = CleanupItem(
            name: "Old runtime", url: nil, category: .simulators, safety: .redownloadable,
            action: .deleteSimulatorRuntime(identifier: "11111111-1111-1111-1111-111111111111"), allocatedBytes: 10,
            reason: "Test", consequence: "Test", source: "test", recommendations: [.outdatedSimulator]
        )
        let manual = CleanupItem(
            name: "Current runtime", url: nil, category: .simulators, safety: .reviewRequired,
            action: .deleteSimulatorRuntime(identifier: "22222222-2222-2222-2222-222222222222"), allocatedBytes: 20,
            reason: "Test", consequence: "Test", source: "test"
        )
        let other = makeItem(name: "Cache", bytes: 30, recommendations: [.lowRisk])
        let model = AppModel()
        model.snapshot = ScanSnapshot(date: Date(), items: [recommended, manual, other], issues: [])

        model.selectRecommended(in: .simulators)

        XCTAssertEqual(model.selectedIDs, [recommended.id])
    }

    func testFailedReceiptBytesAreNotCountedAsCleaned() {
        let receipt = CleanupReceipt(
            id: UUID(), startedAt: Date(), finishedAt: Date(), entries: [
                .init(id: UUID(), itemName: "Worked", originalPath: nil, bytes: 10, action: .moveToTrash, succeeded: true, message: "OK"),
                .init(id: UUID(), itemName: "Failed", originalPath: nil, bytes: 90, action: .moveToTrash, succeeded: false, message: "No")
            ]
        )
        XCTAssertEqual(receipt.processedBytes, 10)
    }

    func testVerifiedDuplicateRequiresMatchingHashAndKnownSuffix() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TrashIT-Duplicates-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("Report.txt")
        try Data("matching content".utf8).write(to: original)
        try Data("matching content".utf8).write(to: root.appendingPathComponent("Report (1).txt"))
        try Data("matching content".utf8).write(to: root.appendingPathComponent("Report copy 2.txt"))
        try Data("different data!!".utf8).write(to: root.appendingPathComponent("Report (2).txt"))

        var settings = ScannerSettings.defaults
        settings.scanRoots = [root]
        settings.minimumLargeFileBytes = .max
        let result = await OldFileScanner().scan(settings: settings)
        let duplicates = result.items.filter { $0.category == .duplicates }

        XCTAssertEqual(Set(duplicates.map(\.name)), ["Report (1).txt", "Report copy 2.txt"])
        XCTAssertTrue(duplicates.allSatisfy { $0.duplicateEvidence?.keeperURL == original.standardizedFileURL })
        XCTAssertTrue(duplicates.allSatisfy { $0.recommendations.contains(.verifiedDuplicate) })
    }

    func testExcludedFolderCoversDescendants() {
        let root = URL(fileURLWithPath: "/tmp/TrashIT-Excluded", isDirectory: true)
        var settings = ScannerSettings.defaults
        settings.excludedPaths = [root]
        XCTAssertFalse(settings.includes(root))
        XCTAssertFalse(settings.includes(root.appendingPathComponent("child/file")))
        XCTAssertTrue(settings.includes(URL(fileURLWithPath: "/tmp/TrashIT-Other")))
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

    @MainActor
    func testEveryScanClearsExistingSelection() async {
        let scanner = StorageScanner(scanners: [
            StubScanner(id: "one", delayNanoseconds: 0, itemName: "Found")
        ])
        let receiptDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrashIT-ScanSelection-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(scanner: scanner, receiptStore: ReceiptStore(directory: receiptDirectory))
        let previous = makeItem(name: "Previous", bytes: 1, recommendations: [.lowRisk])
        model.snapshot = ScanSnapshot(date: Date(), items: [previous], issues: [])
        model.selectedIDs = [previous.id]

        await model.scan()

        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertNil(model.activeSmartSelection)
    }

    @MainActor
    func testOverviewTotalsUseRecommendationsAndSuccessfulReceipts() {
        let safe = makeItem(name: "Safe", bytes: 25, recommendations: [.lowRisk])
        let manual = makeItem(name: "Manual", bytes: 100)
        let model = AppModel()
        model.snapshot = ScanSnapshot(date: Date(), items: [safe, manual], issues: [])
        model.receipts = [CleanupReceipt(
            id: UUID(), startedAt: Date(), finishedAt: Date(), entries: [
                .init(id: UUID(), itemName: "Success", originalPath: nil, bytes: 40, action: .moveToTrash, succeeded: true, message: "OK"),
                .init(id: UUID(), itemName: "Failure", originalPath: nil, bytes: 60, action: .moveToTrash, succeeded: false, message: "Failed")
            ]
        )]

        XCTAssertEqual(model.safeToCleanBytes, 25)
        XCTAssertEqual(model.cleanedSoFarBytes, 40)
    }

    func testOwnerToolCommandsAreFixedAllowlistedArguments() {
        XCTAssertEqual(ToolCleanupKind.pnpm.arguments, ["store", "prune"])
        XCTAssertEqual(ToolCleanupKind.uv.arguments, ["cache", "prune"])
        XCTAssertEqual(ToolCleanupKind.goBuild.executableName, "go")
        XCTAssertEqual(ToolCleanupKind.goBuild.arguments, ["clean", "-cache"])
        XCTAssertNil(ToolLocator.executable(named: "npm; rm"))
    }

    func testEqualRuntimeVersionsKeepNewestBuild() throws {
        let olderBuild = runtimeImage(uuid: "66666666-6666-6666-6666-666666666666", platform: "com.apple.platform.iphonesimulator", version: "18.6", build: "22G80", bytes: 1)
        let newerBuild = runtimeImage(uuid: "77777777-7777-7777-7777-777777777777", platform: "com.apple.platform.iphonesimulator", version: "18.6", build: "22G90", bytes: 1)
        let items = SimulatorScanner().runtimeItems([olderBuild, newerBuild], budget: ScanBudget())
        let oldItem = try XCTUnwrap(items.first { $0.metadata["identifier"] == olderBuild.identifier })
        let newItem = try XCTUnwrap(items.first { $0.metadata["identifier"] == newerBuild.identifier })
        XCTAssertTrue(oldItem.recommendations.contains(.outdatedSimulator))
        XCTAssertFalse(newItem.recommendations.contains(.outdatedSimulator))
    }

    private func makeItem(
        name: String,
        bytes: Int64,
        recommendations: Set<CleanupRecommendation> = []
    ) -> CleanupItem {
        CleanupItem(
            name: name,
            url: nil,
            category: .xcode,
            safety: .regeneratable,
            action: .deleteRegeneratable,
            allocatedBytes: bytes,
            reason: "Test",
            consequence: "Test",
            source: "test",
            recommendations: recommendations
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
// SPDX-License-Identifier: GPL-3.0-or-later
