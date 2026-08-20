import XCTest
@testable import AIFileCore

final class TaskHumanTimeTests: XCTestCase {
    
    func testHumanFriendlyTimeFormatting() {
        let calendar = Calendar.current
        
        // 构造一个基准时间：2026-08-20 15:30:00 (周四)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 8
        comps.day = 20
        comps.hour = 15
        comps.minute = 30
        comps.second = 0
        let baseNow = calendar.date(from: comps)!
        
        // 1. < 60 秒 (刚刚)
        let justNow = baseNow.addingTimeInterval(-20)
        XCTAssertEqual(TaskExecutionRecord.formatHumanFriendlyTime(date: justNow, relativeTo: baseNow), "刚刚")
        
        // 2. 5 分钟前
        let fiveMinsAgo = baseNow.addingTimeInterval(-5 * 60)
        XCTAssertEqual(TaskExecutionRecord.formatHumanFriendlyTime(date: fiveMinsAgo, relativeTo: baseNow), "5分钟前")
        
        // 3. 45 分钟前
        let fortyFiveMinsAgo = baseNow.addingTimeInterval(-45 * 60)
        XCTAssertEqual(TaskExecutionRecord.formatHumanFriendlyTime(date: fortyFiveMinsAgo, relativeTo: baseNow), "45分钟前")
        
        // 4. 今天（>= 1小时）：今天 10:15
        var todayComps = comps
        todayComps.hour = 10
        todayComps.minute = 15
        let earlierToday = calendar.date(from: todayComps)!
        XCTAssertEqual(TaskExecutionRecord.formatHumanFriendlyTime(date: earlierToday, relativeTo: baseNow), "今天 10:15")
        
        // 5. 昨天：昨天 09:40
        var yesterdayComps = comps
        yesterdayComps.day = 19
        yesterdayComps.hour = 9
        yesterdayComps.minute = 40
        let yesterday = calendar.date(from: yesterdayComps)!
        XCTAssertEqual(TaskExecutionRecord.formatHumanFriendlyTime(date: yesterday, relativeTo: baseNow), "昨天 09:40")
        
        // 6. 同一周其他天 (如周一 2026-08-17 14:20)
        var mondayComps = comps
        mondayComps.day = 17
        mondayComps.hour = 14
        mondayComps.minute = 20
        let monday = calendar.date(from: mondayComps)!
        let mondayResult = TaskExecutionRecord.formatHumanFriendlyTime(date: monday, relativeTo: baseNow)
        XCTAssertTrue(mondayResult.contains("周一") && mondayResult.contains("14:20"))
        
        // 7. 今年非本周 (如 2026-07-15 08:30)
        var earlierThisYearComps = comps
        earlierThisYearComps.month = 7
        earlierThisYearComps.day = 15
        earlierThisYearComps.hour = 8
        earlierThisYearComps.minute = 30
        let earlierThisYear = calendar.date(from: earlierThisYearComps)!
        XCTAssertEqual(TaskExecutionRecord.formatHumanFriendlyTime(date: earlierThisYear, relativeTo: baseNow), "07-15 08:30")
        
        // 8. 往年跨年 (如 2025-12-30 16:45)
        var lastYearComps = comps
        lastYearComps.year = 2025
        lastYearComps.month = 12
        lastYearComps.day = 30
        lastYearComps.hour = 16
        lastYearComps.minute = 45
        let lastYear = calendar.date(from: lastYearComps)!
        XCTAssertEqual(TaskExecutionRecord.formatHumanFriendlyTime(date: lastYear, relativeTo: baseNow), "2025-12-30 16:45")
    }
}
