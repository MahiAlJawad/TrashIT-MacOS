// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum DistributionProfile {
    #if TRASHIT_APP_STORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif
}
