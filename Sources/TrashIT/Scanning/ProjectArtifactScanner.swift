import Foundation

struct ProjectArtifactScanner: CleanupScanning {
    let id = "project-artifacts"

    private struct Rule: Sendable {
        let name: String
        let consequence: String
    }

    private let rules: [String: Rule] = [
        "node_modules": Rule(name: "JavaScript dependencies", consequence: "Run the project’s package-manager install command before the next build."),
        ".build": Rule(name: "Swift build output", consequence: "Swift Package Manager will rebuild packages and products."),
        ".next": Rule(name: "Next.js build cache", consequence: "Next.js will rebuild the application and cache."),
        ".dart_tool": Rule(name: "Dart generated data", consequence: "Dart or Flutter will regenerate package metadata and build state."),
        "Pods": Rule(name: "CocoaPods dependencies", consequence: "Run pod install before building the project again."),
        "DerivedData": Rule(name: "Project Derived Data", consequence: "Xcode will rebuild products and indexes."),
        "coverage": Rule(name: "Test coverage output", consequence: "Run the test suite to generate coverage reports again."),
        "Carthage": Rule(name: "Carthage build products", consequence: "Carthage may need to rebuild or download project dependencies.")
    ]

    func scan(settings: ScannerSettings) async -> ScanResult {
        var result = ScanResult()
        var reported = Set<URL>()
        let budget = ScanBudget(seconds: 15)
        for root in settings.scanRoots {
            guard !budget.isExpired else { break }
            scan(root: root, settings: settings, budget: budget, reported: &reported, result: &result)
        }
        if budget.isExpired {
            result.issues.append(ScanIssue(scanner: id, message: "Project-artifact scan reached its 15-second limit. Add individual project folders for more complete results."))
        }
        return result
    }

    private func scan(
        root: URL,
        settings: ScannerSettings,
        budget: ScanBudget,
        reported: inout Set<URL>,
        result: inout ScanResult
    ) {
        var queue: [(URL, Int)] = [(root, 0)]
        var inspected = 0
        let skipNames: Set<String> = [".git", ".svn", ".Trash", "Library", "Applications"]

        while !queue.isEmpty && inspected < 20_000 && !budget.isExpired {
            let (directory, depth) = queue.removeFirst()
            guard depth < 7 else { continue }
            let children = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
                options: []
            )) ?? []

            for child in children {
                inspected += 1
                guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
                      values.isDirectory == true,
                      values.isSymbolicLink != true else { continue }

                let childName = child.lastPathComponent
                if let rule = rules[childName], reported.insert(child.standardizedFileURL).inserted {
                    let bytes = FileInspection.allocatedSize(of: child)
                    guard bytes >= settings.minimumCacheBytes else { continue }
                    result.items.append(CleanupItem(
                        name: "\(rule.name) — \(directory.lastPathComponent)",
                        url: child,
                        category: .developerCaches,
                        safety: .redownloadable,
                        action: .deleteRegeneratable,
                        allocatedBytes: bytes,
                        lastUsed: FileInspection.lastUsedDate(for: child),
                        reason: "A recognized generated dependency or build directory inside a selected scan folder.",
                        consequence: rule.consequence,
                        source: id,
                        defaultSelected: false,
                        metadata: ["project": directory.path]
                    ))
                    continue
                }

                guard values.isPackage != true, !skipNames.contains(childName) else { continue }
                queue.append((child, depth + 1))
            }
        }

        if inspected >= 20_000 {
            result.issues.append(ScanIssue(scanner: id, message: "Project scan stopped after 20,000 folders under \(root.path). Add a narrower project folder for complete results."))
        }
    }
}
