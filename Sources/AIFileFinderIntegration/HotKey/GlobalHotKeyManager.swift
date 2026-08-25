import Foundation
import AppKit
import Carbon

/// 全局快捷键管理器：支持用户自定义组合键并持久化 (UserDefaults)
@MainActor
public final class GlobalHotKeyManager: ObservableObject {
    public static let shared = GlobalHotKeyManager()
    
    private static let keyCodeKey = "aifiles.hotkey.keyCode"
    private static let modifiersKey = "aifiles.hotkey.modifiers"
    private static let symbolKey = "aifiles.hotkey.symbol"
    private static let readableKey = "aifiles.hotkey.readable"
    
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    public var onHotKeyTriggered: (() -> Void)?
    
    /// 形如 "⌥M" 的紧凑符号表示（用于菜单与徽章展示）
    @Published public private(set) var hotKeySymbol: String = "⌥M"
    /// 形如 "Option + M" 的可读表示
    @Published public private(set) var hotKeyReadable: String = "Option + M"
    
    private var registeredKeyCode: UInt32 = UInt32(kVK_ANSI_M)
    private var registeredModifiers: UInt32 = UInt32(optionKey)
    
    public init() {
        loadPersistedHotKey()
    }
    
    /// 读取持久化的自定义快捷键；首次使用回退到默认 Option + M
    private func loadPersistedHotKey() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.keyCodeKey) != nil else { return }
        let code = UInt32(defaults.integer(forKey: Self.keyCodeKey))
        let mods = UInt32(defaults.integer(forKey: Self.modifiersKey))
        guard code > 0, mods > 0 else { return }
        registeredKeyCode = code
        registeredModifiers = mods
        hotKeySymbol = defaults.string(forKey: Self.symbolKey) ?? hotKeySymbol
        hotKeyReadable = defaults.string(forKey: Self.readableKey) ?? hotKeyReadable
    }
    
    /// 注册当前生效的全局快捷键（应用启动时调用）
    public func registerSavedHotKey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x41494649), id: 1)
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            Task { @MainActor in
                GlobalHotKeyManager.shared.onHotKeyTriggered?()
            }
            return noErr
        }, 1, &eventType, nil, &eventHandlerRef)
        
        RegisterEventHotKey(registeredKeyCode, registeredModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
    
    /// 更新并持久化自定义快捷键（要求至少包含 ⌘/⌥/⌃ 中的一个修饰键）
    public func updateHotKey(keyCode: Int, modifiers: NSEvent.ModifierFlags, displayChar: String) {
        let carbonModifiers = Self.carbonFlags(from: modifiers)
        guard carbonModifiers & UInt32(cmdKey | optionKey | controlKey) != 0,
              !displayChar.isEmpty else { return }
        
        registeredKeyCode = UInt32(keyCode)
        registeredModifiers = carbonModifiers
        hotKeySymbol = Self.symbolString(modifiers: modifiers, displayChar: displayChar)
        hotKeyReadable = Self.readableString(modifiers: modifiers, displayChar: displayChar)
        
        let defaults = UserDefaults.standard
        defaults.set(keyCode, forKey: Self.keyCodeKey)
        defaults.set(UInt(carbonModifiers), forKey: Self.modifiersKey)
        defaults.set(hotKeySymbol, forKey: Self.symbolKey)
        defaults.set(hotKeyReadable, forKey: Self.readableKey)
        
        unregisterHotKey()
        registerSavedHotKey()
    }
    
    /// 注销快捷键
    public func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
    
    // MARK: - 显示文本构造
    
    private static func carbonFlags(from modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
    
    private static func symbolString(modifiers: NSEvent.ModifierFlags, displayChar: String) -> String {
        var symbol = ""
        if modifiers.contains(.control) { symbol += "⌃" }
        if modifiers.contains(.option) { symbol += "⌥" }
        if modifiers.contains(.shift) { symbol += "⇧" }
        if modifiers.contains(.command) { symbol += "⌘" }
        return symbol + displayChar
    }
    
    private static func readableString(modifiers: NSEvent.ModifierFlags, displayChar: String) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Command") }
        parts.append(displayChar)
        return parts.joined(separator: " + ")
    }
}
