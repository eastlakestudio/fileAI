import Foundation
import AppKit
import Carbon

/// 全局快捷键管理器
@MainActor
public final class GlobalHotKeyManager: ObservableObject {
    public static let shared = GlobalHotKeyManager()
    
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    public var onHotKeyTriggered: (() -> Void)?
    
    public init() {}
    
    /// 注册全局快捷键（默认 Option + M，对应文件魔法棒 Magic Wand）
    public func registerDefaultHotKey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x41494649), id: 1) // "AIFI"
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            Task { @MainActor in
                GlobalHotKeyManager.shared.onHotKeyTriggered?()
            }
            return noErr
        }, 1, &eventType, nil, &eventHandlerRef)
        
        // kVK_ANSI_M 为字母 M 键码 (0x29)，optionKey 为 Option 键修饰符
        RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(optionKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
    
    /// 注销快捷键
    public func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
