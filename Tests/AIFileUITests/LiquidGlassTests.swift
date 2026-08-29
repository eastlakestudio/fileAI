import XCTest
import SwiftUI
import AppKit
@testable import AIFileCore
@testable import AIFileUI

final class LiquidGlassTests: XCTestCase {
    
    @MainActor
    func testVisualEffectBlurCreationAndProperties() {
        let blur = VisualEffectBlur(
            material: .hudWindow,
            blendingMode: .behindWindow,
            state: .active,
            cornerRadius: 16,
            alpha: 0.55
        )
        XCTAssertEqual(blur.cornerRadius, 16)
        XCTAssertEqual(blur.material, .hudWindow)
        XCTAssertEqual(blur.blendingMode, .behindWindow)
        XCTAssertEqual(blur.state, .active)
        XCTAssertEqual(blur.alpha, 0.55)
    }
    
    @MainActor
    func testLiquidGlassBackgroundViewRendering() {
        let glass = LiquidGlassBackground(cornerRadius: 16, isCapsule: false, isDraggingOver: false)
        XCTAssertNotNil(glass.body)
        
        let capsuleGlass = LiquidGlassBackground(cornerRadius: 22, isCapsule: true, isDraggingOver: true)
        XCTAssertNotNil(capsuleGlass.body)
        
        let largePanelGlass = LiquidGlassBackground(cornerRadius: 16, isCapsule: false, isDraggingOver: false, isStandardLargePanel: true)
        XCTAssertNotNil(largePanelGlass.body)
        XCTAssertTrue(largePanelGlass.isStandardLargePanel)
    }
}
