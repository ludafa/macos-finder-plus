import Foundation
import ServiceManagement

// 宿主 App：苹果规定扩展必须装在一个 App 里。
// 系统更新等情况偶尔会让系统丢掉扩展的注册，Finder 右键菜单里就没有「拷贝路径」了，
// 光打开 App 也不一定能让系统重新发现扩展。所以这个 App 把自己设成登录项，
// 每次登录时检查一遍：扩展不在系统的扩展列表里，就用 pluginkit 把它加回去。
// 只补注册，不改用户在系统设置里对扩展的启用/停用选择。

let extensionID = "com.ludafa.finderplus.extension"

@discardableResult
func pluginkit(_ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return ""
    }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: output, as: UTF8.self)
}

// 扩展已注册时 pluginkit -m 会输出一行，未注册时什么都不输出。
// 已注册时不要再执行 pluginkit -a，它会让正在运行的扩展进程重启
if pluginkit(["-m", "-i", extensionID]).isEmpty,
   let plugIns = Bundle.main.builtInPlugInsURL {
    let appex = plugIns.appendingPathComponent("CopyPathExtension.appex")
    pluginkit(["-a", appex.path])
    print("CopyPathSync: 已重新注册 Finder 扩展")
}

// 用户在「系统设置 → 通用 → 登录项与扩展」里移除后不会再自动加回，除非再次手动打开本 App
if SMAppService.mainApp.status != .enabled {
    do {
        try SMAppService.mainApp.register()
    } catch {
        print("CopyPathSync: 无法设为登录项：\(error.localizedDescription)")
    }
}
