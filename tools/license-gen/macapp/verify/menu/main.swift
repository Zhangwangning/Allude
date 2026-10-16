import AppKit

// ============================================================================
// 主菜单行为验证 · 真实 .app 入口
//
// 🔴 为什么不能放在 verify/theme（命令行 harness）里
//
// AppKit 的响应链分发起点是 `keyWindow.firstResponder`。命令行进程（无 bundle）
// 无法把自己的窗口变成 key window —— 实测 `isKeyWindow` 恒为 false，
// 于是 `NSApp.target(forAction: paste:)` 找不到 NSTextView，
// 测出来是「红色」但根因在环境、不在代码（假警报）。
//
// 本程序由 verify/menu/run.sh 打包成一个**真实 .app**：
// 复制 build.sh 的产物（Info.plist + zh-Hans.lproj + 图标），只替换可执行文件。
// 因此它同时还验证了另一件必须真机才能测的事：
//   NSTextView 的**右键上下文菜单**是否已本地化成中文（原来一直显示 Cut / Copy / Paste）。
//
// 🔴 为什么行为测试要「分步走主 run loop」
//
// NSUndoManager 默认 `groupsByEvent`，undo 分组靠主 run loop 的**事件迭代**闭合。
// 在同步代码里连着做「粘贴 → 剪切 → 撤销」，三次编辑会挤进同一个 group，
// ⌘Z 一按就把整段历史全撤了（表现为「撤销无效」，其实是撤销粒度不对）。
// 实测在 run loop 回调内部再调 `RunLoop.current.run(until:)` **不能**让它闭合
// （那是嵌套跑，不产生新的迭代），必须用 `DispatchQueue.main.asyncAfter`
// 把每一步放到下一个迭代里 —— 这也正是真实按键的间隔形态。
//
// 结果落到 /tmp/cc-menuchk-result.txt，并打上 PASS / FAIL 供脚本判定。
// ============================================================================

final class MenuCheckApp: NSObject, NSApplicationDelegate {

    private var window: NSWindow!
    private var field: MultilineField!
    private var log: [String] = []
    private var failed = false

    private let uuid = "5F2A9C31-AAAA-BBBB-CCCC-DDDDEEEEFFFF"
    private var steps: [() -> Void] = []
    private var stepIndex = 0

    private func out(_ s: String) { log.append(s) }
    private func fail(_ s: String) { failed = true; log.append("  ✗ " + s) }
    private func pass(_ s: String) { log.append("  ✓ " + s) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        out("=== 主菜单行为验证（真实 .app）===")
        out("bundlePath        = \(Bundle.main.bundlePath)")
        out("localizations     = \(Bundle.main.localizations)")
        out("DevelopmentRegion = \(Bundle.main.object(forInfoDictionaryKey: "CFBundleDevelopmentRegion") ?? "nil")")
        out("系统首选语言      = \(Locale.preferredLanguages.prefix(1))")
        out("")

        // ⚠️ 这里**故意不装主菜单**：留给下面先跑「无菜单时 ⌘V 必须失效」的对照组，
        //    对照组过了再 install() —— 这样后面的 PASS 才有意义。
        //    此刻 NSApp.mainMenu 就是系统给的默认菜单（只有一个「应用名」顶级项），
        //    正是修复前「发码.app」的真实状态。

        // 真实窗口 + 真实多行输入框（和「批量签发」页同一个控件）
        window = NSWindow(contentRect: NSRect(x: 240, y: 240, width: 640, height: 300),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "主菜单验证"
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
        window.contentView = host
        field = MultilineField(placeholder: "每行一个设备码", height: 150)
        field.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -16),
            field.topAnchor.constraint(equalTo: host.topAnchor, constant: 16),
        ])

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field.textView)

        waitForKeyWindow(attempt: 0)
    }

    /// 等窗口真正拿到 key 状态再测 —— 否则 target 解析会落空（见文件头说明）
    private func waitForKeyWindow(attempt: Int) {
        if window.isKeyWindow || attempt >= 16 {
            runTests(keyWindowReady: window.isKeyWindow, attempts: attempt)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.waitForKeyWindow(attempt: attempt + 1)
        }
    }

    // MARK: - 主体

    private func runTests(keyWindowReady: Bool, attempts: Int) {
        out("=== 焦点状态 ===")
        out("  isKeyWindow = \(keyWindowReady)（等待 \(attempts) 次轮询）")
        if !keyWindowReady {
            fail("窗口始终没能成为 key window，本次结果不可信（环境问题，非代码问题）")
        }
        out("")

        // ── 对照组：不装主菜单时 ⌘V 必须无效 ────────────────────────────
        // 少了这一步，后面「⌘V 成功」可能只是环境碰巧，断言等于没写。
        out("=== 对照组：不装主菜单 ===")
        setClipboard(uuid)
        let controlHandled = pressCommand("v")
        out("  ⌘V handled=\(controlHandled)  输入框=\"\(field.text)\"")
        if field.text.isEmpty {
            pass("无主菜单时 ⌘V 确实无效 —— 对照组成立，后面的 PASS 才有意义")
        } else {
            fail("对照组异常：没有主菜单时 ⌘V 竟然生效了，本段断言不可信")
        }
        out("")

        // ── 装上真实主菜单 ──────────────────────────────────────────────
        MainMenu.install()
        out("=== 菜单结构 ===")
        for line in MainMenu.describe().split(separator: "\n") { out("  " + line) }
        let topTitles = NSApp.mainMenu?.items.map { $0.title } ?? []
        out("  [顶级菜单] \(topTitles)")
        if topTitles.contains("NSMenuItem") {
            fail("顶级菜单标题是 \"NSMenuItem\" —— 用了无参 NSMenuItem() 构造（title 会变成类名）")
        }
        for required in ["编辑", "窗口"] where !topTitles.contains(required) {
            fail("顶级菜单缺少「\(required)」")
        }
        out("")

        out("=== NSTextView 对候选 selector 的响应 ===")
        // 决定「编辑」菜单各项该挂哪个 action：挂错的话菜单项会一直是灰的。
        // `undo:` / `redo:` 定义在 NSUndoManager 上，NSTextView 本身不响应是正常的
        // —— AppKit 对这两个选择器有特殊处理（会去找响应链上的 undoManager）。
        for name in ["cut:", "copy:", "paste:", "selectAll:", "delete:",
                     "undo:", "redo:", "pasteAndMatchStyle:", "pasteAsPlainText:"] {
            out("  \(field.textView.responds(to: NSSelectorFromString(name)) ? "✓" : "·")  \(name)")
        }
        out("")

        // ── 行为测试：每一步都放到下一个 run loop 迭代 ───────────────────
        out("=== 快捷键行为 ===")
        steps = [stepPaste, stepSelectAll, stepCopy, stepCut, stepUndo, stepRedoAvailability]
        stepIndex = 0
        advance()
    }

    /// 推进到下一步。每步之间让出主 run loop：undo 分组靠事件迭代闭合，
    /// 同步连做会让所有编辑挤成一个 group（详见文件头）。
    private func advance() {
        guard stepIndex < steps.count else { finish(); return }
        let step = steps[stepIndex]
        stepIndex += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            step()
            self.advance()
        }
    }

    private func stepPaste() {
        setClipboard(uuid)
        _ = pressCommand("v")
        if field.text == uuid {
            pass("⌘V 从系统剪贴板粘贴成功 → \"\(field.text)\"")
        } else {
            fail("⌘V 没粘进来（得到 \"\(field.text)\"）")
        }
    }

    private func stepSelectAll() {
        _ = pressCommand("a")
        let selected = field.textView.selectedRange().length
        if selected == uuid.count {
            pass("⌘A 全选 \(selected) 字符")
        } else {
            fail("⌘A 没全选（选中 \(selected)，应 \(uuid.count)）")
        }
    }

    private func stepCopy() {
        setClipboard("")
        _ = pressCommand("c")
        if clipboard() == uuid {
            pass("⌘C 拷贝到系统剪贴板成功")
        } else {
            fail("⌘C 没写进剪贴板（得到 \"\(clipboard())\"）")
        }
    }

    private func stepCut() {
        // ⚠️ 先把「粘贴」的撤销记录清掉，让撤销栈里**只剩「剪切」这一步**。
        //
        // 为什么不靠 run loop 间隔来分界：`NSUndoManager` 的自动分组要等主 run loop
        // 进入 waiting 阶段才闭合，而 asyncAfter 的间隔并不保证会发生（实测同样的代码
        // 时通时不通）。清栈之后，无论分组成不成立，撤销的结果都唯一 —— 断言稳定。
        let manager = field.textView.undoManager
        manager?.removeAllActions()
        out("  [诊断] 清空撤销栈后 canUndo=\(manager?.canUndo ?? false)（应为 false）")

        _ = pressCommand("x")
        if field.text.isEmpty && clipboard() == uuid {
            pass("⌘X 剪切成功（输入框已清空，剪贴板保留内容）")
        } else {
            fail("⌘X 异常（输入框=\"\(field.text)\" 剪贴板=\"\(clipboard())\"）")
        }
    }

    private func stepUndo() {
        let manager = field.textView.undoManager
        out("  [诊断] 撤销前 canUndo=\(manager?.canUndo ?? false)  undoActionName=\"\(manager?.undoActionName ?? "nil")\"")
        out("  [诊断] target(forAction: undo:) = \(NSApp.target(forAction: NSSelectorFromString("undo:"), to: nil, from: nil).map { String(describing: type(of: $0)) } ?? "nil")")

        _ = pressCommand("z")
        let afterUndo = field.text
        out("  [诊断] 撤销后 canUndo=\(manager?.canUndo ?? false)  输入框=\"\(afterUndo)\"")

        if afterUndo == uuid {
            pass("⌘Z 撤销成功（只撤销了「剪切」那一步，uuid 已恢复）")
        } else {
            fail("⌘Z 撤销失败（输入框=\"\(afterUndo)\"）")
        }
    }

    /// ⇧⌘Z 重做：撤销之后应能把内容再删掉
    private func stepRedoAvailability() {
        let manager = field.textView.undoManager
        let before = field.text
        out("  [诊断] ⇧⌘Z 之前 canUndo=\(manager?.canUndo ?? false) canRedo=\(manager?.canRedo ?? false) redoActionName=\"\(manager?.redoActionName ?? "nil")\"")

        let handled = pressCommand("z", shift: true)
        let after = field.text
        out("  [诊断] ⇧⌘Z handled=\(handled) 之后 canRedo=\(manager?.canRedo ?? false) 输入框=\"\(after)\"")

        if before == uuid && after.isEmpty {
            pass("⇧⌘Z 重做成功（内容被重新剪切掉）")
        } else {
            fail("⇧⌘Z 重做没有效果（\"\(before)\" → \"\(after)\"）")
        }
    }

    private func finish() {
        out("")
        out("=== 右键上下文菜单（本地化）===")
        checkContextMenu()

        let result = log.joined(separator: "\n") + "\n\n判定：" + (failed ? "FAIL" : "PASS") + "\n"
        print(result)
        try? result.write(toFile: "/tmp/cc-menuchk-result.txt", atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// NSTextView 的右键菜单由 AppKit 提供，标题按 App 的本地化资源解析。
    /// 修复前 `Bundle.main.localizations == []`，菜单一直是 Cut / Copy / Paste。
    private func checkContextMenu() {
        guard let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
                                             modifierFlags: [], timestamp: 0,
                                             windowNumber: window.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: 1, pressure: 1),
              let menu = field.textView.menu(for: event) else {
            fail("取不到右键上下文菜单，无法判定")
            return
        }

        var titles: [String] = []
        for item in menu.items where !item.isSeparatorItem {
            let key = item.keyEquivalent.isEmpty ? "" : "  ⌘\(item.keyEquivalent)"
            out("  \(item.title)\(key) → \(item.action.map { NSStringFromSelector($0) } ?? "(子菜单)")")
            titles.append(item.title)
            if let sub = item.submenu {
                titles.append(contentsOf: sub.items.filter { !$0.isSeparatorItem }.map { $0.title })
            }
        }

        let english = ["Cut", "Copy", "Paste", "Paste and Match Style", "Select All",
                       "Undo", "Redo", "Delete", "Font", "Spelling and Grammar",
                       "Substitutions", "Transformations", "Speech", "Share"]
            .filter { titles.contains($0) }
        if english.isEmpty {
            pass("右键菜单已中文化（无英文残留）")
        } else {
            fail("右键菜单仍有英文项：\(english)")
        }

        for expected in ["剪切", "拷贝", "粘贴"] where !titles.contains(expected) {
            fail("右键菜单缺少「\(expected)」")
        }
    }

    // MARK: - 工具

    private func setClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func clipboard() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }

    /// 走真实快捷键分发路径：⌘<键> 的 keyDown 交给主菜单 performKeyEquivalent。
    /// 调用方负责在两步之间让出 run loop（见 `advance()`）。
    private func pressCommand(_ key: String, shift: Bool = false) -> Bool {
        let keyCodes: [String: UInt16] = ["a": 0, "z": 6, "x": 7, "c": 8, "v": 9]
        let modifiers: NSEvent.ModifierFlags = shift ? [.command, .shift] : [.command]
        // ⚠️ `charactersIgnoringModifiers` 是「忽略**除 Shift 外**的修饰键」后的字符 ——
        //    ⇧⌘Z 拿到的是 **"Z"**（大写），不是 "z"。传错会让「重做」项匹配不到。
        let characters = shift ? key.uppercased() : key
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                           modifierFlags: modifiers, timestamp: 1,
                                           windowNumber: window.windowNumber, context: nil,
                                           characters: characters,
                                           charactersIgnoringModifiers: characters,
                                           isARepeat: false, keyCode: keyCodes[key] ?? 0) else {
            return false
        }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }
}

let app = NSApplication.shared
let delegate = MenuCheckApp()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
