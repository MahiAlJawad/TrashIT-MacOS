import Foundation

struct DockerScanner: CleanupScanning {
    let id = "docker"

    private struct UsageLine: Decodable {
        let Reclaimable: String?
    }

    func scan(settings: ScannerSettings) async -> ScanResult {
        guard let docker = ToolLocator.docker else { return ScanResult() }
        do {
            let output = try ProcessRunner.run(
                docker,
                arguments: ["system", "df", "--format", "{{json .}}"]
            )
            guard output.status == 0 else { return ScanResult() }

            let reclaimable = output.stdout.split(separator: 0x0A).reduce(Int64(0)) { partial, line in
                guard let usage = try? JSONDecoder().decode(UsageLine.self, from: Data(line)),
                      let value = usage.Reclaimable else { return partial }
                return partial + parseBytes(value)
            }
            guard reclaimable >= settings.minimumCacheBytes else { return ScanResult() }

            return ScanResult(items: [CleanupItem(
                name: "Docker unused data",
                url: nil,
                category: .developerCaches,
                safety: .reviewRequired,
                action: .pruneDocker,
                allocatedBytes: reclaimable,
                reason: "Docker reports stopped containers, unused images, networks, or build cache as reclaimable.",
                consequence: "Docker will use its own system prune command. Volumes are explicitly retained, but old images may need downloading again.",
                source: id
            )])
        } catch {
            return ScanResult()
        }
    }

    private func parseBytes(_ value: String) -> Int64 {
        let amountText = value.split(separator: " ").first.map(String.init) ?? value
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*([KMGT]?B)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: amountText, range: NSRange(amountText.startIndex..., in: amountText)),
              let amountRange = Range(match.range(at: 1), in: amountText),
              let unitRange = Range(match.range(at: 2), in: amountText),
              let amount = Double(amountText[amountRange]) else { return 0 }

        let multiplier: Double = switch amountText[unitRange].uppercased() {
        case "KB": 1_000
        case "MB": 1_000_000
        case "GB": 1_000_000_000
        case "TB": 1_000_000_000_000
        default: 1
        }
        return Int64(amount * multiplier)
    }
}
// SPDX-License-Identifier: GPL-3.0-or-later
