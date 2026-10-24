import AppKit
import ApplicationServices

// 第三层测试的辅助程序：用辅助功能 API 在 Finder 最前面的窗口（列表视图）里打开菜单，并点击指定菜单项。
// 用法：MenuClicker [选项...] <菜单项标题>
//   选中方式（可选，默认保持当前选中）：
//     --select-first     只选中第一项
//     --select-all       全选
//     --select-none      取消选中
//   打开哪个菜单（默认右键当前选中项；配合 --select-none 时右键窗口空白处）：
//     --toolbar          点工具栏上的「拷贝路径」按钮
//     --sidebar          右键侧边栏里当前用户的个人文件夹
//   其他：
//     --expect-absent    检查菜单里没有这个菜单项（不点击）
//     --check-trust      只检查是否有辅助功能权限（没有时退出码为 2）

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

// MARK: - 辅助功能 API 的简单封装

func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
}

func string(_ element: AXUIElement, _ attribute: String) -> String? {
    value(element, attribute) as? String
}

func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
    (value(element, attribute) as? [AXUIElement]) ?? []
}

func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let result = value(element, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
    return (result as! AXUIElement)
}

func role(_ element: AXUIElement) -> String {
    string(element, kAXRoleAttribute) ?? ""
}

func actions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    AXUIElementCopyActionNames(element, &names)
    return (names as? [String]) ?? []
}

func frame(_ element: AXUIElement) -> CGRect? {
    guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute) else { return nil }
    var point = CGPoint.zero, extent = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &point)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    return CGRect(origin: point, size: extent)
}

// 深度优先找第一个符合条件的元素；跳过菜单栏，它很大且和右键菜单无关
func find(in root: AXUIElement, depth: Int = 20, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
    if match(root) { return root }
    guard depth > 0, role(root) != kAXMenuBarRole else { return nil }
    for child in elements(root, kAXChildrenAttribute) {
        if let found = find(in: child, depth: depth - 1, match) { return found }
    }
    return nil
}

func findAll(in root: AXUIElement, depth: Int = 20, _ match: (AXUIElement) -> Bool) -> [AXUIElement] {
    var found = match(root) ? [root] : []
    guard depth > 0, role(root) != kAXMenuBarRole else { return found }
    for child in elements(root, kAXChildrenAttribute) {
        found += findAll(in: child, depth: depth - 1, match)
    }
    return found
}

func dump(_ element: AXUIElement, indent: String = "", depth: Int = 6) {
    print(indent + role(element), string(element, kAXTitleAttribute) ?? "", actions(element).joined(separator: ","))
    guard depth > 0 else { return }
    for child in elements(element, kAXChildrenAttribute) { dump(child, indent: indent + "  ", depth: depth - 1) }
}

// MARK: - 模拟输入

func post(_ events: [CGEvent?]) {
    for event in events {
        event?.post(tap: .cghidEventTap)
        usleep(50_000)
    }
}

func rightClick(at point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    post([CGEventType.mouseMoved, .rightMouseDown, .rightMouseUp].map {
        CGEvent(mouseEventSource: source, mouseType: $0, mouseCursorPosition: point, mouseButton: .right)
    })
}

func leftClick(at point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    post([CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp].map {
        CGEvent(mouseEventSource: source, mouseType: $0, mouseCursorPosition: point, mouseButton: .left)
    })
}

func pressEscape() {
    post([true, false].map { CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: $0) })
}

// MARK: - 主流程

// CI 上标准输出不是终端，默认整块缓冲；改成按行输出，日志顺序才和错误信息对得上
setvbuf(stdout, nil, _IOLBF, 0)

var args = Array(CommandLine.arguments.dropFirst())
var flags = Set<String>()
while let first = args.first, first.hasPrefix("--") {
    flags.insert(args.removeFirst())
}

let trusted = AXIsProcessTrusted()
if flags.contains("--check-trust") {
    print("AXIsProcessTrusted = \(trusted)")
    exit(trusted ? 0 : 2)
}
guard trusted else { fail("没有辅助功能权限") }
guard let title = args.first else { fail("用法：MenuClicker [选项...] <菜单项标题>，详见源码开头的说明") }

guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
    fail("Finder 没有运行")
}
let app = AXUIElementCreateApplication(finder.processIdentifier)
AXUIElementSetMessagingTimeout(app, 3)

guard let window = element(app, kAXFocusedWindowAttribute) ?? elements(app, kAXWindowsAttribute).first else {
    fail("找不到 Finder 窗口")
}

// 侧边栏和文件列表都是 AXOutline：侧边栏只有一列，文件列表有名称、日期、大小等多列
let outlines = findAll(in: window) { role($0) == kAXOutlineRole }
let fileList = outlines.first { elements($0, kAXColumnsAttribute).count > 1 }
let sidebar = outlines.first { elements($0, kAXColumnsAttribute).count == 1 }

func requireFileList() -> AXUIElement {
    guard let fileList else {
        dump(window)
        fail("窗口里找不到列表视图（AXOutline）")
    }
    return fileList
}

func select(_ rows: [AXUIElement]) {
    AXUIElementSetAttributeValue(requireFileList(), kAXSelectedRowsAttribute as CFString, rows as CFArray)
    usleep(300_000)
}

if flags.contains("--select-first") {
    // 窗口刚弹过菜单时，用辅助功能接口设置单个选中项不一定生效，所以像真人一样点一下第一行
    guard let first = elements(requireFileList(), kAXRowsAttribute).first, let rowFrame = frame(first) else {
        fail("列表里没有可选的项目")
    }
    leftClick(at: CGPoint(x: rowFrame.minX + 60, y: rowFrame.midY))
    usleep(300_000)
} else if flags.contains("--select-all") {
    select(elements(requireFileList(), kAXRowsAttribute))
} else if flags.contains("--select-none") {
    select([])
}
if let fileList {
    print("选中 \(elements(fileList, kAXSelectedRowsAttribute).count) 项")
}

// 菜单打开期间“显示菜单/按下”这类动作可能阻塞到菜单关闭，所以放到后台执行
func performInBackground(_ action: String, on element: AXUIElement) {
    DispatchQueue.global().async { AXUIElementPerformAction(element, action as CFString) }
}

func toolbarButton() -> AXUIElement? {
    guard let toolbar = find(in: window, { role($0) == kAXToolbarRole }) else { return nil }
    return find(in: toolbar) { candidate in
        let texts = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].compactMap { string(candidate, $0) }
        let names = actions(candidate)
        return texts.contains { $0.contains("拷贝") }
            && (names.contains(kAXShowMenuAction) || names.contains(kAXPressAction))
    }
}

func showMenu() {
    if flags.contains("--toolbar") {
        guard let button = toolbarButton() else {
            find(in: window, { role($0) == kAXToolbarRole }).map { dump($0) }
            fail("工具栏上找不到「拷贝路径」按钮")
        }
        performInBackground(actions(button).contains(kAXShowMenuAction) ? kAXShowMenuAction : kAXPressAction, on: button)
    } else if flags.contains("--sidebar") {
        // 个人文件夹在侧边栏里显示为用户名，不受系统语言影响
        let name = NSUserName()
        guard let sidebar,
              let item = find(in: sidebar, { candidate in
                  [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute].contains { string(candidate, $0) == name }
              }),
              let itemFrame = frame(item) else {
            sidebar.map { dump($0) }
            fail("侧边栏里找不到「\(name)」")
        }
        rightClick(at: CGPoint(x: itemFrame.midX, y: itemFrame.midY))
    } else if flags.contains("--select-none") {
        // 右键列表可见区域底部的空白处
        let list = requireFileList()
        guard let visible = element(list, kAXParentAttribute).flatMap(frame) ?? frame(list) else { fail("拿不到列表的位置") }
        rightClick(at: CGPoint(x: visible.midX, y: visible.maxY - 20))
    } else {
        guard let row = elements(requireFileList(), kAXSelectedRowsAttribute).first else { fail("没有选中项") }
        // 优先用辅助功能的“显示菜单”动作，不支持时退回模拟右键
        if let target = find(in: row, depth: 3, { actions($0).contains(kAXShowMenuAction) }) {
            performInBackground(kAXShowMenuAction, on: target)
        } else if let rowFrame = frame(row) {
            rightClick(at: CGPoint(x: rowFrame.minX + 60, y: rowFrame.midY))
        } else {
            fail("选中项既不支持显示菜单，也拿不到位置")
        }
    }
}

func menuItem(titled title: String) -> AXUIElement? {
    find(in: app) { role($0) == kAXMenuItemRole && string($0, kAXTitleAttribute) == title }
}

func openMenuTitles() -> [String] {
    var titles: [String] = []
    func collect(_ element: AXUIElement, depth: Int) {
        if role(element) == kAXMenuItemRole, let title = string(element, kAXTitleAttribute), !title.isEmpty {
            titles.append(title)
        }
        guard depth > 0, role(element) != kAXMenuBarRole else { return }
        elements(element, kAXChildrenAttribute).forEach { collect($0, depth: depth - 1) }
    }
    collect(app, depth: 20)
    return titles
}

if flags.contains("--expect-absent") {
    // 等菜单完整出现后确认没有这个菜单项，再关掉菜单
    showMenu()
    sleep(3)
    let titles = openMenuTitles()
    pressEscape()
    guard !titles.isEmpty else { fail("菜单没有打开") }
    guard !titles.contains(title) else { fail("菜单里不应该有「\(title)」，当前菜单项：\(titles)") }
    print("菜单里没有「\(title)」，符合预期")
    exit(0)
}

// 扩展可能还没准备好，菜单里暂时没有我们的项目；关掉菜单重试几次
for attempt in 1...5 {
    showMenu()
    for _ in 0..<30 {
        if let item = menuItem(titled: title) {
            AXUIElementPerformAction(item, kAXPressAction as CFString)
            print("已点击「\(title)」")
            exit(0)
        }
        usleep(100_000)
    }
    print("第 \(attempt) 次没找到「\(title)」，当前菜单项：\(openMenuTitles())")
    pressEscape()
    sleep(2)
}
fail("多次尝试后仍没找到菜单项「\(title)」")
