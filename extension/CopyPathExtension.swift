import Cocoa
import FinderSync

// 官方 Finder Sync 扩展：在工具栏按钮菜单和右键菜单里提供“拷贝路径”。
class FinderSync: FIFinderSync {

    override init() {
        super.init()
        // 监听整个磁盘，这样任何文件夹里都能拿到 targetedURL
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
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

    // 工具栏按钮、右键选中项、右键窗口空白处，三处用同一个菜单项
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let selectedCount = FIFinderSyncController.default().selectedItemURLs()?.count ?? 0
        let title: String
        switch menuKind {
        case .toolbarItemMenu:
            title = selectedCount > 0 ? "拷贝 \(selectedCount) 个选中项的路径" : "拷贝当前路径"
        case .contextualMenuForItems:
            title = selectedCount > 1 ? "拷贝 \(selectedCount) 个项目的路径" : "拷贝路径"
        case .contextualMenuForContainer:
            title = "拷贝当前路径"
        default:
            return nil
        }
        let menu = NSMenu(title: "")
        let item = menu.addItem(withTitle: title, action: #selector(copyPath(_:)), keyEquivalent: "")
        item.image = menuIcon()
        return menu
    }

    // 有选中项就复制选中项（每行一个），否则复制窗口所在文件夹
    @objc func copyPath(_ sender: AnyObject?) {
        let controller = FIFinderSyncController.default()
        var urls = controller.selectedItemURLs() ?? []
        if urls.isEmpty, let target = controller.targetedURL() {
            urls = [target]
        }
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        NSSound(named: "Pop")?.play()
    }
}
