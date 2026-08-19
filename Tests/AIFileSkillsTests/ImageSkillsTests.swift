import XCTest
import AppKit
@testable import AIFileCore
@testable import AIFileSkills

final class ImageSkillsTests: XCTestCase {
    var tempDirectory: URL!
    
    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    func testImageResizeSkillPlanAndExecution() throws {
        // 创建一张临时测试位图 PNG (100x100)
        let imgURL = tempDirectory.appendingPathComponent("test.png")
        let img = NSImage(size: NSSize(width: 100, height: 100))
        img.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 100, height: 100))
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            XCTFail("无法创建测试 PNG")
            return
        }
        try pngData.write(to: imgURL)
        
        let fileItem = FileMetadataEngine.shared.createFileItem(url: imgURL, isDirectory: false)
        let skill = ImageResizeSkill()
        
        // 1. 生成计划
        let plan = try skill.generatePlan(from: [fileItem], parameters: ["targetWidth": 200, "targetHeight": 200])
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions.first?.operationType, .resizeImage)
        
        // 2. 执行计划
        let action = plan.actions.first!
        let generatedURL = try skill.execute(action: action)
        XCTAssertNotNil(generatedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: generatedURL!.path))
        
        // 验证生成的尺寸
        let generatedItem = FileMetadataEngine.shared.createFileItem(url: generatedURL!, isDirectory: false)
        XCTAssertEqual(generatedItem.imageWidth, 200)
        XCTAssertEqual(generatedItem.imageHeight, 200)
    }
    
    func testImageConvertSkillPlanAndExecution() throws {
        let pngURL = tempDirectory.appendingPathComponent("sample.png")
        let img = NSImage(size: NSSize(width: 50, height: 50))
        img.lockFocus()
        NSColor.blue.drawSwatch(in: NSRect(x: 0, y: 0, width: 50, height: 50))
        img.unlockFocus()
        let tiff = img.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        let pngData = rep.representation(using: .png, properties: [:])!
        try pngData.write(to: pngURL)
        
        let fileItem = FileMetadataEngine.shared.createFileItem(url: pngURL, isDirectory: false)
        let skill = ImageConvertSkill()
        
        // 1. 计划转换为 jpg
        let plan = try skill.generatePlan(from: [fileItem], parameters: ["targetFormat": "jpg"])
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions.first?.targetURL?.pathExtension.lowercased(), "jpg")
        
        // 2. 执行转换
        let outputURL = try skill.execute(action: plan.actions.first!)
        XCTAssertNotNil(outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL!.path))
    }
}
