import XCTest
@testable import AIFileCore
@testable import AIFileAgent

final class SkillIntentClassifierTests: XCTestCase {
    
    func testNativeGenericIntentClassification() {
        let classifier = SkillIntentClassifier.shared
        let result = classifier.classify(userPrompt: "把这几个文件压缩成 zip")
        
        switch result.type {
        case .nativeGeneric:
            XCTAssertTrue(result.matchedSkills.isEmpty)
        default:
            XCTFail("纯 zip 压缩应当被识别为 nativeGeneric")
        }
    }
    
    func testSkillRequiredIntentClassification() {
        let classifier = SkillIntentClassifier.shared
        let result = classifier.classify(userPrompt: "拉取飞书今天的消息记录")
        
        switch result.type {
        case .skillRequired(let skills):
            XCTAssertFalse(skills.isEmpty)
            XCTAssertTrue(skills.contains(where: { $0.id.contains("lark") }))
        default:
            XCTFail("飞书拉取指令应当被识别为 skillRequired")
        }
    }
    
    func testHybridPipelineIntentClassification() {
        let classifier = SkillIntentClassifier.shared
        let result = classifier.classify(userPrompt: "这个文件压缩整zip，通过飞书发给刘明华")
        
        switch result.type {
        case .hybridPipeline(let nativeAction, let requiredSkills):
            XCTAssertFalse(nativeAction.isEmpty)
            XCTAssertFalse(requiredSkills.isEmpty)
            XCTAssertTrue(requiredSkills.contains(where: { $0.id.contains("lark") }))
        default:
            XCTFail("压缩+飞书发送应当被识别为 hybridPipeline")
        }
    }
    
    func testWeChatAndOCRIntentClassification() {
        let classifier = SkillIntentClassifier.shared
        let ocrResult = classifier.classify(userPrompt: "识别这几张发票图片中的 OCR 文字")
        
        switch ocrResult.type {
        case .skillRequired(let skills):
            XCTAssertTrue(skills.contains(where: { $0.id.contains("ocr") }))
        default:
            XCTFail("OCR 应当被识别为 skillRequired")
        }
    }
}
