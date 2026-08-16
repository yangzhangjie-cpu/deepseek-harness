# DeepSeek Harness Desktop

English | [中文](README.zh.md)

Build the standalone macOS application with `./desktop/build-app.sh`. The result is `dist/desktop/DeepSeek Harness.app`; it bundles Node and the production Harness runtime, uses the system WebKit framework, and needs no end-user command-line installation.

The application icon is built from the original 1024 px master at `desktop/Assets/AppIcon.png`; `desktop/Assets/AppIcon.icns` supplies the standard macOS icon representations copied into the application bundle.

The middle of the top 32 px titlebar is a native window-drag region. The left navigation controls and right-side settings controls stay outside that region and remain clickable; double-clicking the drag region uses the standard macOS window zoom action.

The application keeps Harness data, credentials, and its automatically unpacked private Node runtime in `~/Library/Application Support/DeepSeek Harness`. The embedded server binds only to `127.0.0.1` on an operating-system-selected port and stops when the application quits.

General settings includes a desktop-only software update action. It checks the official `deepseek-ai/deepseek-harness` GitHub Releases feed, compares the latest release with the bundled version, and downloads a matching macOS Apple Silicon ZIP or DMG into the user's Downloads directory. Finder reveals the completed download so the user can replace the application; when a release has no matching desktop asset, the action opens the official release page instead.
