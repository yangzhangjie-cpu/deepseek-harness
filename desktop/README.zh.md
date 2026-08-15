# DeepSeek Harness 桌面版

[English](README.md) | 中文

运行 `./desktop/build-app.sh` 可构建独立的 macOS 应用。产物位于 `dist/desktop/DeepSeek Harness.app`；它内置 Node 和生产版 Harness 运行时，使用系统 WebKit 框架，最终用户无需安装任何命令行依赖。

应用图标由 `desktop/Assets/AppIcon.png` 中的原创 1024 像素源图生成；`desktop/Assets/AppIcon.icns` 提供会被复制到应用包中的标准 macOS 多分辨率图标。

应用会将 Harness 数据、凭据以及自动解压的私有 Node 运行时保存在 `~/Library/Application Support/DeepSeek Harness`。内置服务仅绑定到 `127.0.0.1` 上由操作系统分配的端口，并在应用退出时停止。

通用设置中提供仅桌面版显示的软件更新操作。它会检查 `deepseek-ai/deepseek-harness` 官方 GitHub Releases、比较最新发布版本与内置版本，并将匹配 macOS Apple Silicon 的 ZIP 或 DMG 下载至用户的“下载”目录。下载完成后 Finder 会定位安装包，用户可据此替换应用；如果发布版本没有匹配的桌面安装包，该操作会改为打开官方发布页。
