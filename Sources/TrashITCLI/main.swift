import Foundation
import TrashITCore

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--version"] || arguments == ["version"] {
    print("trashit \(TrashITCoreInfo.version)")
} else {
    print("""
    trashit \(TrashITCoreInfo.version)

    The free command-line frontend is being introduced incrementally.
    Available commands:
      trashit --version
      trashit help

    Cleanup commands will use TrashITCore's safety policy and will require an
    explicit selection; the CLI will never delete scan results automatically.
    """)
}
// SPDX-License-Identifier: GPL-3.0-or-later
