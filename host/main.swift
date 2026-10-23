import Foundation

// 宿主 App 只负责携带扩展，本身不做任何事。
// 首次打开它会让系统发现并注册里面的 Finder 扩展。
print("CopyPathSync: Finder 扩展已随本 App 安装，请在系统设置中启用。")
