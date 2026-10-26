// Kinetiq — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import KinetiqCore

final class DockMinimizeAnimationTests: XCTestCase {
    func testEnablingReplacesGenieAndRemembersIt() {
        XCTAssertEqual(DockMinimizeAnimation.plan(wantsDisabled: true, current: nil, backup: nil), .disable(backup: "genie"))
        XCTAssertEqual(DockMinimizeAnimation.plan(wantsDisabled: true, current: "suck", backup: nil), .disable(backup: "suck"))
    }

    func testEnablingKeepsTheFirstBackup() {
        XCTAssertEqual(DockMinimizeAnimation.plan(wantsDisabled: true, current: "genie", backup: "suck"), .disable(backup: nil))
    }

    func testNothingToDoWhenAlreadyReplaced() {
        XCTAssertEqual(DockMinimizeAnimation.plan(wantsDisabled: true, current: "scale", backup: nil), .none)
        XCTAssertEqual(DockMinimizeAnimation.plan(wantsDisabled: true, current: "scale", backup: "genie"), .none)
    }

    func testDisablingPutsTheOriginalBack() {
        XCTAssertEqual(DockMinimizeAnimation.plan(wantsDisabled: false, current: "scale", backup: "genie"), .restore(value: nil))
        XCTAssertEqual(DockMinimizeAnimation.plan(wantsDisabled: false, current: "scale", backup: "suck"), .restore(value: "suck"))
    }

    func testDisablingWithoutBackupDoesNothing() {
        XCTAssertEqual(DockMinimizeAnimation.plan(wantsDisabled: false, current: "scale", backup: nil), .none)
        XCTAssertEqual(DockMinimizeAnimation.plan(wantsDisabled: false, current: nil, backup: nil), .none)
    }

    func testAChangeMadeByTheUserMeanwhileIsRespected() {
        XCTAssertEqual(DockMinimizeAnimation.plan(wantsDisabled: false, current: "suck", backup: "genie"), .forgetBackup)
    }
}
