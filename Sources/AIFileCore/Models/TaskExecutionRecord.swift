import Foundation

/// 任务状态枚举
public enum TaskStatus: String, Sendable, Codable {
    case inProgress = "进行中"
    case completed = "已完成"
    case failed = "执行失败"
    case reverted = "已撤销"
    case cancelled = "用户取消"
}

/// 任务执行记录（包含完整的 Plan 方案、Walkthrough 结果与全链路执行计时）
public struct TaskExecutionRecord: Identifiable, Sendable, Codable {
    public let id: UUID
    public let prompt: String
    public var status: TaskStatus
    public let createdAt: Date
    public var completedAt: Date?
    
    // 执行前 Plan 方案
    public var plan: ExecutionPlan
    
    // 执行后 Walkthrough 结果报告（Markdown 格式）
    public var walkthroughReport: String?
    
    // 关联的底层可撤销事务 ID
    public var transactionId: UUID?
    
    // 任务绑定的目标文件/文件夹路径集合
    public var targetFilePaths: [String]
    
    public var errorMessage: String?
    public var executionLogs: [String]
    
    public init(
        id: UUID = UUID(),
        prompt: String,
        status: TaskStatus = .inProgress,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        plan: ExecutionPlan,
        walkthroughReport: String? = nil,
        transactionId: UUID? = nil,
        targetFilePaths: [String] = [],
        errorMessage: String? = nil,
        executionLogs: [String] = []
    ) {
        self.id = id
        self.prompt = prompt
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.plan = plan
        self.walkthroughReport = walkthroughReport
        self.transactionId = transactionId
        self.targetFilePaths = targetFilePaths
        self.errorMessage = errorMessage
        self.executionLogs = executionLogs.isEmpty ? plan.executionLogs : executionLogs
    }
    
    /// 任务总耗时（秒）
    public var durationSeconds: Double {
        let end = completedAt ?? Date()
        return max(0.01, end.timeIntervalSince(createdAt))
    }
    
    /// 格式化耗时展示（例如 "1.2s", "350ms"）
    public var formattedDuration: String {
        let dur = durationSeconds
        if dur < 1.0 {
            return String(format: "%.0fms", dur * 1000)
        } else {
            return String(format: "%.1fs", dur)
        }
    }
    
    /// 人性化相对/绝对时间展示
    public var humanFriendlyTime: String {
        return TaskExecutionRecord.formatHumanFriendlyTime(date: createdAt)
    }
    
    /// 静态格式化方法（支持注入当前基准时间，方便单元测试）
    public static func formatHumanFriendlyTime(date: Date, relativeTo now: Date = Date()) -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeStr = timeFormatter.string(from: date)
        
        let interval = now.timeIntervalSince(date)
        
        // 1. 未来时间或极短时间（< 60秒）
        if interval < 60 && interval >= -5 {
            return "刚刚"
        }
        
        // 2. 1小时内（< 3600秒）：X分钟前
        if interval < 3600 && interval >= 60 {
            let minutes = max(1, Int(interval / 60))
            return "\(minutes)分钟前"
        }
        
        // 3. 今天（同一自然天，>= 1小时）：今天 HH:mm
        if calendar.isDate(date, inSameDayAs: now) {
            return "今天 \(timeStr)"
        }
        
        // 4. 昨天：昨天 HH:mm
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(timeStr)"
        }
        
        // 5. 本周内（同自然周）：周X HH:mm
        let currentWeek = calendar.component(.weekOfYear, from: now)
        let currentYear = calendar.component(.yearForWeekOfYear, from: now)
        let targetWeek = calendar.component(.weekOfYear, from: date)
        let targetYear = calendar.component(.yearForWeekOfYear, from: date)
        
        if currentYear == targetYear && currentWeek == targetWeek {
            let weekday = calendar.component(.weekday, from: date)
            let weekdayNames = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            let name = (weekday >= 1 && weekday <= 7) ? weekdayNames[weekday] : "本周"
            return "\(name) \(timeStr)"
        }
        
        // 6. 本年内（非本周非昨天）：MM-dd HH:mm（短格式，不显示年份）
        let nowYear = calendar.component(.year, from: now)
        let dateYear = calendar.component(.year, from: date)
        
        if nowYear == dateYear {
            let df = DateFormatter()
            df.dateFormat = "MM-dd HH:mm"
            return df.string(from: date)
        }
        
        // 7. 往年（跨年）：yyyy-MM-dd HH:mm
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df.string(from: date)
    }
}
