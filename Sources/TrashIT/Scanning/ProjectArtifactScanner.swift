import Foundation

struct ProjectArtifactScanner: CleanupScanning {
    let id = "project-artifacts"

    private struct Rule: Sendable {
        let directoryName: String
        let displayName: String
        let markerNames: Set<String>
        let markerPrefixes: [String]
        let consequence: String
    }

    private let rules: [Rule] = [
        Rule(directoryName: "node_modules", displayName: "JavaScript dependencies", markerNames: ["package.json"], markerPrefixes: [], consequence: "Run the project's package-manager install command before the next build."),
        Rule(directoryName: ".build", displayName: "Swift build output", markerNames: ["Package.swift"], markerPrefixes: [], consequence: "Swift Package Manager will rebuild packages and products."),
        Rule(directoryName: "target", displayName: "Rust build output", markerNames: ["Cargo.toml"], markerPrefixes: [], consequence: "Cargo will rebuild the project."),
        Rule(directoryName: "target", displayName: "Maven build output", markerNames: ["pom.xml"], markerPrefixes: [], consequence: "Maven will rebuild compiled classes and reports."),
        Rule(directoryName: ".venv", displayName: "Python virtual environment", markerNames: ["pyproject.toml", "requirements.txt", "Pipfile", "setup.py"], markerPrefixes: [], consequence: "Recreate the environment and reinstall the project's dependencies."),
        Rule(directoryName: ".next", displayName: "Next.js build data", markerNames: ["package.json"], markerPrefixes: ["next.config."], consequence: "Next.js will rebuild the application and its cache."),
        Rule(directoryName: ".nuxt", displayName: "Nuxt build data", markerNames: ["package.json"], markerPrefixes: ["nuxt.config."], consequence: "Nuxt will regenerate its build data."),
        Rule(directoryName: ".turbo", displayName: "Turborepo cache", markerNames: ["turbo.json", "package.json"], markerPrefixes: [], consequence: "Turborepo will recompute cached tasks."),
        Rule(directoryName: ".parcel-cache", displayName: "Parcel cache", markerNames: ["package.json"], markerPrefixes: [], consequence: "Parcel will rebuild its transform cache."),
        Rule(directoryName: ".zig-cache", displayName: "Zig build cache", markerNames: ["build.zig"], markerPrefixes: [], consequence: "Zig will rebuild cached compilation outputs."),
        Rule(directoryName: "zig-out", displayName: "Zig build products", markerNames: ["build.zig"], markerPrefixes: [], consequence: "Zig will regenerate installed build products."),
        Rule(directoryName: ".angular", displayName: "Angular build cache", markerNames: ["angular.json", "package.json"], markerPrefixes: [], consequence: "Angular will rebuild cached project data."),
        Rule(directoryName: ".svelte-kit", displayName: "SvelteKit generated data", markerNames: ["package.json"], markerPrefixes: ["svelte.config."], consequence: "SvelteKit will regenerate framework and build data."),
        Rule(directoryName: ".astro", displayName: "Astro generated data", markerNames: ["package.json"], markerPrefixes: ["astro.config."], consequence: "Astro will regenerate framework data."),
        Rule(directoryName: ".expo", displayName: "Expo local project state", markerNames: ["app.json", "package.json"], markerPrefixes: ["app.config."], consequence: "Expo will recreate local development state; you may need to reconnect devices."),
        Rule(directoryName: ".dart_tool", displayName: "Dart generated data", markerNames: ["pubspec.yaml"], markerPrefixes: [], consequence: "Dart or Flutter will regenerate package metadata and build state."),
        Rule(directoryName: "Pods", displayName: "CocoaPods dependencies", markerNames: ["Podfile"], markerPrefixes: [], consequence: "Run pod install before building the project again."),
        Rule(directoryName: "DerivedData", displayName: "Project Derived Data", markerNames: ["project.pbxproj"], markerPrefixes: [], consequence: "Xcode will rebuild products and indexes."),
        Rule(directoryName: "Carthage", displayName: "Carthage dependencies", markerNames: ["Cartfile", "Cartfile.resolved"], markerPrefixes: [], consequence: "Carthage may need to rebuild or download dependencies.")
    ]

    func scan(settings: ScannerSettings) async -> ScanResult {
        var result = ScanResult()
        var reported = Set<URL>()
        let budget = ScanBudget(seconds: 15)
        for root in settings.scanRoots where settings.includes(root) {
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
            guard depth < 7, settings.includes(directory) else { continue }
            let children = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
                options: []
            )) ?? []

            for child in children {
                inspected += 1
                guard settings.includes(child),
                      let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
                      values.isDirectory == true,
                      values.isSymbolicLink != true else { continue }

                let childName = child.lastPathComponent
                if let match = matchingRule(for: childName, startingAt: directory, stopAt: root),
                   reported.insert(child.standardizedFileURL).inserted {
                    let bytes = FileInspection.allocatedSize(of: child)
                    guard bytes >= settings.minimumCacheBytes else { continue }
                    result.items.append(CleanupItem(
                        name: "\(match.rule.displayName) — \(match.projectRoot.lastPathComponent)",
                        url: child,
                        category: .developerCaches,
                        safety: .regeneratable,
                        action: .deleteRegeneratable,
                        allocatedBytes: bytes,
                        lastUsed: FileInspection.lastUsedDate(for: child),
                        reason: "A generated project directory validated by \(match.marker) in the owning project.",
                        consequence: match.rule.consequence,
                        source: id,
                        recommendations: [.lowRisk],
                        metadata: ["project": match.projectRoot.path, "validatedBy": match.marker]
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

    private func matchingRule(
        for directoryName: String,
        startingAt parent: URL,
        stopAt root: URL
    ) -> (rule: Rule, projectRoot: URL, marker: String)? {
        let candidates = rules.filter { $0.directoryName == directoryName }
        guard !candidates.isEmpty else { return nil }
        var cursor = parent.standardizedFileURL
        let boundary = root.standardizedFileURL

        for _ in 0..<4 {
            let names = Set(((try? FileManager.default.contentsOfDirectory(
                at: cursor,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []).map(\.lastPathComponent))

            for rule in candidates {
                if let marker = rule.markerNames.first(where: names.contains) {
                    return (rule, cursor, marker)
                }
                if let marker = names.first(where: { name in rule.markerPrefixes.contains(where: name.hasPrefix) }) {
                    return (rule, cursor, marker)
                }
            }

            guard cursor.path != boundary.path,
                  cursor.path.hasPrefix(boundary.path + "/") else { break }
            cursor.deleteLastPathComponent()
        }
        return nil
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
