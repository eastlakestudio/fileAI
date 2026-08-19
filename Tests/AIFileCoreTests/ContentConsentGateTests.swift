import XCTest
@testable import AIFileCore

private final class MockConsentDelegate: ConsentGateDelegate, @unchecked Sendable {
    var mockedDecision: ConsentDecision = .allowedOnce
    var didCallModal = false
    
    func presentConsentModal(for request: ConsentRequest) async -> ConsentDecision {
        didCallModal = true
        return mockedDecision
    }
}

final class ContentConsentGateTests: XCTestCase {
    func testLocalModelBypassesConsentModal() async {
        let gate = ContentConsentGate()
        let delegate = MockConsentDelegate()
        gate.delegate = delegate
        
        let request = ConsentRequest(
            targetFiles: [URL(fileURLWithPath: "/path/to/test.txt")],
            contentPreviewSnippet: "sample snippet",
            destinationEndpoint: "local_mlx",
            isLocalOfflineModel: true,
            reasonDescription: "离线提取"
        )
        
        let decision = await gate.evaluateConsent(for: request)
        XCTAssertEqual(decision, .allowedOnce)
        XCTAssertFalse(delegate.didCallModal)
    }
    
    func testCloudModelTriggersConsentModal() async {
        let gate = ContentConsentGate()
        let delegate = MockConsentDelegate()
        delegate.mockedDecision = .deniedFallbackToMetadata
        gate.delegate = delegate
        
        let request = ConsentRequest(
            targetFiles: [URL(fileURLWithPath: "/path/to/test.txt")],
            contentPreviewSnippet: "cloud preview",
            destinationEndpoint: "api.deepseek.com",
            isLocalOfflineModel: false,
            reasonDescription: "云端翻译"
        )
        
        let decision = await gate.evaluateConsent(for: request)
        XCTAssertEqual(decision, .deniedFallbackToMetadata)
        XCTAssertTrue(delegate.didCallModal)
    }
}
