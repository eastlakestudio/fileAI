import XCTest
@testable import AIFileAgent
@testable import AIFileCore

final class MultiStepJSONParsingTests: XCTestCase {
    
    func testDirectJSONExtractionHelper() {
        let rawJSON = """
        [
          {
            "tool": "zip_compress",
            "arguments": {
              "fileNames": ["test.xlsx"],
              "outputZip": "test.zip"
            }
          },
          {
            "tool": "lark_sync",
            "arguments": {
              "fileNames": ["test.zip"],
              "targetUser": "刘明华"
            }
          }
        ]
        """
        
        let data = rawJSON.data(using: .utf8)!
        let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.count, 2)
        XCTAssertEqual(list?.first?["tool"] as? String, "zip_compress")
        XCTAssertEqual(list?.last?["tool"] as? String, "lark_sync")
    }
}
