# macOS Finder Plus

给 Finder 加一个「拷贝路径」：在右键菜单或工具栏里点一下，就把文件或文件夹的完整路径放进剪贴板，方便粘贴到终端、Claude Code 等地方。

## 功能

| 在哪里点 | 菜单项 | 拷贝的内容 |
| --- | --- | --- |
| 右键选中的文件 / 文件夹 | 拷贝路径（多选时为「拷贝 N 个项目的路径」） | 选中项的路径，多个时每行一个 |
| 右键窗口空白处 | 拷贝当前路径 | 当前文件夹的路径 |
| 工具栏按钮（需手动添加） | 有选中项时拷贝选中项，否则拷贝当前路径 | 同上 |

拷贝成功会有一声轻响；当前位置没有真实路径（如「最近使用」）时会响提示音。

> 小知识：系统自带 ⌥⌘C 也能拷贝选中项的路径，但没选中时无法拷贝当前文件夹。

## 系统要求

- macOS 14 或更新版本
- Xcode 命令行工具（从源码编译时需要）：`xcode-select --install`

## 安装

### 方式一：从源码编译（推荐）

```bash
git clone https://github.com/ludafa/macos-finder-plus.git
cd macos-finder-plus
./build.sh install
```

脚本会编译、安装到 `~/Applications/CopyPathSync.app`，并自动注册、启用 Finder 扩展。本机编译的 App 不会被 Gatekeeper 拦截，不需要额外操作。

### 方式二：把编译好的 App 拷到另一台电脑

适合对方电脑没装命令行工具的情况。注意两台电脑芯片要一致（都是 Apple Silicon 或都是 Intel）。

在已编译的电脑上打包：

```bash
./build.sh
ditto -c -k --keepParent build/CopyPathSync.app CopyPathSync.zip
```

在另一台电脑上：

1. 解压，把 `CopyPathSync.app` 放进 `~/Applications` 或 `/Applications`。
2. App 没有经过苹果公证，通过 AirDrop、网盘、浏览器传过去的会被系统拦截，先解除隔离：
   ```bash
   xattr -dr com.apple.quarantine ~/Applications/CopyPathSync.app
   ```
3. 双击打开一次 `CopyPathSync.app`（它不会显示窗口，打开后会自动退出），让系统注册扩展。
4. 启用扩展（见下方「启用扩展」）。

## 启用扩展

`./build.sh install` 会自动启用。如果右键菜单里没有「拷贝路径」：

- 打开「系统设置 → 通用 → 登录项与扩展」，在扩展里找到 CopyPathSync，把开关打开；或者在终端执行：
  ```bash
  pluginkit -e use -i com.ludafa.finderplus.extension
  ```
- 仍然没有时，按住 Option 右键点 Dock 上的 Finder，选「重新开启」。

## 添加工具栏按钮（可选）

在 Finder 窗口中选择菜单栏「显示 → 自定工具栏…」，把「拷贝路径」图标拖到工具栏上。

## 卸载

```bash
pluginkit -e ignore -i com.ludafa.finderplus.extension
rm -rf ~/Applications/CopyPathSync.app
```

## 项目结构

```
build.sh          编译、签名、安装脚本
make-icon.swift   生成 App 图标
extension/        Finder 扩展：右键菜单、工具栏按钮的全部逻辑
host/             宿主 App：苹果规定扩展必须装在一个 App 里，它本身不做任何事
```

修改代码后执行 `./build.sh install` 即可重新安装，脚本会自动重启扩展进程。

App 使用本地临时签名（ad-hoc），没有苹果开发者证书也能编译使用。如果要公开分发给其他人，需要加入 Apple Developer Program，用 Developer ID 签名并公证，对方才能直接打开。

## 许可证

[MIT](LICENSE)
