import Cocoa
import FinderSync

// 单元测试：覆盖界面上触发不到的边界情况，比如 Finder 返回 nil、没有任何可拷贝的路径。
// 和扩展代码一起编译成命令行程序运行，见 tests/unit-tests.sh
@main
struct UnitTests {

    static var failures = 0

    static func expect<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
        if actual == expected {
            print("✓ \(name)")
        } else {
            failures += 1
            print("✗ \(name)：期望 \(expected)，实际 \(actual)")
        }
    }

    static func main() {
        let dir = URL(fileURLWithPath: "/tmp/带 空格 的目录")
        let a = dir.appendingPathComponent("a.txt")
        let b = dir.appendingPathComponent("b c.txt")

        print("菜单标题")
        expect(CopyPath.menuTitle(for: .toolbarItemMenu, selected: [a, b]), "拷贝 2 个选中项的路径", "工具栏，有选中项")
        expect(CopyPath.menuTitle(for: .toolbarItemMenu, selected: nil), "拷贝当前路径", "工具栏，Finder 返回 nil 时按没有选中项处理")
        expect(CopyPath.menuTitle(for: .contextualMenuForItems, selected: [a]), "拷贝路径", "右键单个文件")
        expect(CopyPath.menuTitle(for: .contextualMenuForItems, selected: [a, b]), "拷贝 2 个项目的路径", "右键多个文件")
        expect(CopyPath.menuTitle(for: .contextualMenuForContainer, selected: [dir]), "拷贝当前路径", "右键空白处")
        expect(CopyPath.menuTitle(for: .contextualMenuForSidebar, selected: [dir]), nil, "侧边栏不提供菜单项")

        print("要拷贝的路径")
        expect(CopyPath.paths(selected: [a, b], target: dir), [a.path, b.path], "有选中项时拷贝选中项")
        expect(CopyPath.paths(selected: [], target: dir), [dir.path], "没有选中项时拷贝当前文件夹")
        expect(CopyPath.paths(selected: nil, target: dir), [dir.path], "Finder 返回 nil 时拷贝当前文件夹")
        expect(CopyPath.paths(selected: nil, target: nil), [], "没有选中项也没有当前文件夹")

        print("菜单图标")
        for dark in [false, true] {
            let mode = dark ? "深色模式" : "浅色模式"
            let icon = CopyPath.menuIcon(dark: dark)
            expect(icon.size, NSSize(width: 16, height: 16), "\(mode)：尺寸 16×16pt，与 Finder 菜单里的系统图标对齐")
            expect(icon.isTemplate, true, "\(mode)：标记为模板图")
            guard let rep = icon.representations.first as? NSBitmapImageRep else {
                expect(false, true, "\(mode)：图标是位图")
                continue
            }
            expect(rep.colorAt(x: 0, y: 0)?.alphaComponent, 0, "\(mode)：背景透明，不是实心块")
            let pixels = (0..<rep.pixelsWide).flatMap { x in (0..<rep.pixelsHigh).compactMap { rep.colorAt(x: x, y: $0) } }
            let stroke = pixels.first { $0.alphaComponent > 0.5 }?.usingColorSpace(.sRGB)
            expect(stroke.map { $0.brightnessComponent > 0.5 }, dark, "\(mode)：线条颜色与背景形成对比")
        }

        print("写入剪贴板（使用独立的剪贴板，不影响系统剪贴板）")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.ludafa.finderplus.unit-tests"))
        pasteboard.clearContents()
        pasteboard.setString("原有内容", forType: .string)
        CopyPath.copy([], to: pasteboard)
        expect(pasteboard.string(forType: .string), "原有内容", "没有路径时不改动剪贴板")
        CopyPath.copy([a.path, b.path], to: pasteboard)
        expect(pasteboard.string(forType: .string), "\(a.path)\n\(b.path)", "多个路径每行一个")
        pasteboard.releaseGlobally()

        guard failures == 0 else {
            print("\(failures) 个单元测试失败")
            exit(1)
        }
        print("单元测试全部通过")
    }
}
