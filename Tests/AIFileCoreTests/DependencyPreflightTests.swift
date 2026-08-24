import XCTest
@testable import AIFileCore

final class DependencyPreflightTests: XCTestCase {
    
    func testExtractPythonDependenciesFiltersStandardLibraries() {
        let script = """
        import sys
        import os
        import json
        import re
        from pathlib import Path
        import math
        
        print("Standard libs only")
        """
        
        let deps = DependencyPreflightChecker.shared.extractPythonDependencies(script: script)
        XCTAssertTrue(deps.isEmpty, "Standard libraries should be completely filtered out")
    }
    
    func testExtractPythonDependenciesMapsAliases() {
        let script = """
        import sys
        from PIL import Image, ImageDraw
        import cv2
        import pandas as pd
        from docx import Document
        from bs4 import BeautifulSoup
        """
        
        let deps = DependencyPreflightChecker.shared.extractPythonDependencies(script: script)
        XCTAssertTrue(deps.contains("pillow"), "PIL should map to pillow")
        XCTAssertTrue(deps.contains("opencv-python"), "cv2 should map to opencv-python")
        XCTAssertTrue(deps.contains("pandas"), "pandas should be identified")
        XCTAssertTrue(deps.contains("python-docx"), "docx should map to python-docx")
        XCTAssertTrue(deps.contains("beautifulsoup4"), "bs4 should map to beautifulsoup4")
        XCTAssertFalse(deps.contains("sys"), "sys should not be present")
    }
    
    func testInstalledModuleCheck() {
        let pythonPath = PythonSkillRunner.shared.resolvePythonPath()
        
        // 验证系统标准库 json / sys 必然存在
        XCTAssertTrue(DependencyPreflightChecker.shared.isPythonModuleAvailable(moduleOrPackage: "json", pythonPath: pythonPath))
        XCTAssertTrue(DependencyPreflightChecker.shared.isPythonModuleAvailable(moduleOrPackage: "sys", pythonPath: pythonPath))
    }
    
    func testMissingModuleTriggersClearGuidance() async {
        let pythonPath = PythonSkillRunner.shared.resolvePythonPath()
        let script = """
        import non_existent_mock_package_xyz_12345
        print("test")
        """
        
        let result = await DependencyPreflightChecker.shared.ensureDependencies(
            script: script,
            engine: .python3,
            pythonPath: pythonPath
        )
        
        XCTAssertFalse(result.isReady)
        XCTAssertTrue(result.missingPackages.contains("non_existent_mock_package_xyz_12345"))
        XCTAssertNotNil(result.errorMessage)
        XCTAssertTrue(result.errorMessage?.contains("pip3 install non_existent_mock_package_xyz_12345") == true)
    }
}
