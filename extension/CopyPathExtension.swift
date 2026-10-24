import Cocoa
import FinderSync

// 官方 Finder Sync 扩展：在工具栏按钮菜单和右键菜单里提供“拷贝路径”。
// 和 Finder 打交道的部分放在 FinderSync 类里，由端到端测试覆盖；
// 不依赖 Finder 的判断逻辑放在 CopyPath 里，界面上触发不到的边界情况由单元测试覆盖。
class FinderSync: FIFinderSync {

    override init() {
        super.init()
        // 监听整个磁盘，这样任何文件夹里都能拿到 targetedURL
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        flushCoverage()
    }

    // macOS 中文版里“复制”是制作副本，放到剪贴板叫“拷贝”，这里跟系统用词保持一致
    override var toolbarItemName: String { "拷贝路径" }

    override var toolbarItemToolTip: String { "拷贝选中项或当前文件夹的完整路径" }

    // doc.on.doc 是系统菜单里“拷贝”用的图标
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "拷贝路径")!
    }

    // 菜单里直接放 SF Symbol 会被 Finder 画成实心块，所以先按系统菜单图标的尺寸画成位图，
    // 颜色跟随当前深浅色模式；同时标记为模板图，Finder 若支持会自行着色
    private func menuIcon() -> NSImage {
        // 10pt 与 Finder 右键菜单里系统图标的实际尺寸一致（按截图像素量过）
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        let symbol = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)!
            .withSymbolConfiguration(config)!

        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        var color = NSColor.black
        NSAppearance(named: isDark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.usingColorSpace(.sRGB)!
        }

        let size = NSSize(width: 16, height: 16)
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(x: (size.width - symbol.size.width) / 2, y: (size.height - symbol.size.height) / 2,
                          width: symbol.size.width, height: symbol.size.height)
        symbol.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        defer { flushCoverage() }
        let selected = FIFinderSyncController.default().selectedItemURLs()
        guard let title = CopyPath.menuTitle(for: menuKind, selected: selected) else { return nil }
        let menu = NSMenu(title: "")
        let item = menu.addItem(withTitle: title, action: #selector(copyPath(_:)), keyEquivalent: "")
        item.image = menuIcon()
        return menu
    }

    @objc func copyPath(_ sender: AnyObject?) {
        defer { flushCoverage() }
        let controller = FIFinderSyncController.default()
        let paths = CopyPath.paths(selected: controller.selectedItemURLs(), target: controller.targetedURL())
        CopyPath.copy(paths, to: .general)
    }
}

enum CopyPath {

    // 工具栏按钮、右键选中项、右键窗口空白处，三处用同一个菜单项；侧边栏等其他菜单不提供
    static func menuTitle(for kind: FIMenuKind, selected: [URL]?) -> String? {
        let count = selected?.count ?? 0
        switch kind {
        case .toolbarItemMenu:
            return count > 0 ? "拷贝 \(count) 个选中项的路径" : "拷贝当前路径"
        case .contextualMenuForItems:
            return count > 1 ? "拷贝 \(count) 个项目的路径" : "拷贝路径"
        case .contextualMenuForContainer:
            return "拷贝当前路径"
        default:
            return nil
        }
    }

    // 有选中项就拷贝选中项，否则拷贝窗口所在文件夹。
    // 右键空白处时 Finder 会把当前文件夹当成选中项传进来；点工具栏按钮且没有选中项时才会用到 target
    static func paths(selected: [URL]?, target: URL?) -> [String] {
        if let selected, !selected.isEmpty {
            return selected.map(\.path)
        }
        return target.map { [$0.path] } ?? []
    }

    // 多个路径每行一个；没有可拷贝的路径时不改动剪贴板，只响提示音
    static func copy(_ paths: [String], to pasteboard: NSPasteboard) {
        guard !paths.isEmpty else {
            NSSound.beep()
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
        NSSound(named: "Pop")?.play()
    }
}

#if COVERAGE
// 覆盖率统计，仅在 COVERAGE=1 ./build.sh 编译时启用。
// 扩展进程通常被直接结束，来不及在退出时写数据，所以每次被 Finder 调用后都主动写一次；
// 沙盒只允许写这个目录（见 Extension.coverage.entitlements）
@_silgen_name("__llvm_profile_set_filename") private func llvmProfileSetFilename(_ name: UnsafePointer<CChar>)
@_silgen_name("__llvm_profile_write_file") private func llvmProfileWriteFile() -> Int32

private let coverageFileConfigured: Void = llvmProfileSetFilename("/private/tmp/finderplus-coverage/extension-%p.profraw")

func flushCoverage() {
    _ = coverageFileConfigured
    _ = llvmProfileWriteFile()
}
#else
@inline(__always) func flushCoverage() {}
#endif
