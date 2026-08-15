import Cocoa
import WebKit

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    let tagName: String
    let htmlUrl: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case assets
    }
}

final class DeepSeekHarnessApp: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var harness: Process?
    private var outputBuffer = ""
    private var loadedURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        startHarness()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        if let harness, harness.isRunning {
            harness.terminate()
        }
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 DeepSeek Harness", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func buildWindow() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(self, name: "desktopHarness")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        configuration.userContentController.addUserScript(WKUserScript(
            source: "Object.defineProperty(window, '__DEEPSEEK_HARNESS_DESKTOP__', { value: { version: '\(version)' } });",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            document.addEventListener('click', event => {
              const button = event.target instanceof Element ? event.target.closest('button') : null;
              if (!button) return;
              const label = (button.getAttribute('aria-label') || button.textContent || '').trim();
              const needsWorkspace = document.querySelector('textarea[placeholder="选择一个工作区开始"]') !== null;
              if (label === '添加工作区' || label === '选择工作区' || (needsWorkspace && (label === '新建会话' || label === '新会话'))) {
                event.preventDefault();
                event.stopImmediatePropagation();
                window.webkit.messageHandlers.desktopHarness.postMessage('pick-workspace');
              }
            }, true);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek Harness"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 980, height: 640)
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        showStatus(title: "DeepSeek Harness", detail: "正在启动本地服务…")
    }

    private func showStatus(title: String, detail: String) {
        let safeTitle = title.replacingOccurrences(of: "'", with: "&#39;")
        let safeDetail = detail.replacingOccurrences(of: "'", with: "&#39;")
        let html = """
        <!doctype html><meta charset="utf-8"><style>
        :root{color-scheme:light dark}body{margin:0;display:grid;place-items:center;height:100vh;font:14px -apple-system,BlinkMacSystemFont,sans-serif;background:#f7f8fa;color:#202124}
        @media(prefers-color-scheme:dark){body{background:#17181a;color:#f2f3f5}}
        main{text-align:center}.mark{width:38px;height:38px;margin:0 auto 18px;border-radius:12px;background:#4d6bfe;box-shadow:0 10px 28px #4d6bfe44}
        h1{font-size:19px;margin:0 0 8px}p{margin:0;color:#7b7f87}
        </style><main><div class="mark"></div><h1>\(safeTitle)</h1><p>\(safeDetail)</p></main>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func startHarness() {
        guard let resources = Bundle.main.resourceURL else {
            showStatus(title: "无法启动", detail: "应用资源目录不存在。")
            return
        }
        let entry = resources.appendingPathComponent("runtime/node_modules/@deepseek-ai/dsh/lib/bin.js")
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeepSeek Harness", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        prepareNode(resources: resources, support: support) { [weak self] result in
            switch result {
            case .success(let node): self?.launchHarness(node: node, entry: entry, resources: resources, support: support)
            case .failure(let error): self?.showStatus(title: "Harness 启动失败", detail: error.localizedDescription)
            }
        }
    }

    private func prepareNode(resources: URL, support: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let node = support.appendingPathComponent("node-v24.19.0")
        if FileManager.default.isExecutableFile(atPath: node.path) {
            completion(.success(node))
            return
        }
        showStatus(title: "DeepSeek Harness", detail: "正在准备内置运行时…")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let compressed = resources.appendingPathComponent("node.gz")
                let temporary = support.appendingPathComponent("node-v24.19.0.tmp")
                FileManager.default.createFile(atPath: temporary.path, contents: nil)
                let output = try FileHandle(forWritingTo: temporary)
                defer { try? output.close() }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
                process.arguments = ["-c", compressed.path]
                process.standardOutput = output
                process.standardError = Pipe()
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw NSError(domain: "DeepSeekHarness", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "内置运行时解压失败。"])
                }
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
                if FileManager.default.fileExists(atPath: node.path) { try FileManager.default.removeItem(at: node) }
                try FileManager.default.moveItem(at: temporary, to: node)
                DispatchQueue.main.async { completion(.success(node)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func launchHarness(node: URL, entry: URL, resources: URL, support: URL) {

        let process = Process()
        let pipe = Pipe()
        process.executableURL = node
        process.arguments = [entry.path, "web", "--host", "127.0.0.1", "--port", "0"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var environment = ProcessInfo.processInfo.environment
        environment["DSH_HOME"] = support.path
        environment["PATH"] = "\(resources.path):/usr/bin:/bin:/usr/sbin:/sbin"
        environment["NODE_ENV"] = "production"
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.consumeOutput(text) }
        }
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self, self.loadedURL == nil else { return }
                self.showStatus(title: "Harness 启动失败", detail: "本地服务已退出（代码 \(process.terminationStatus)）。")
            }
        }
        do {
            try process.run()
            harness = process
        } catch {
            showStatus(title: "Harness 启动失败", detail: error.localizedDescription)
        }
    }

    private func consumeOutput(_ text: String) {
        outputBuffer += text
        if outputBuffer.count > 32_768 { outputBuffer.removeFirst(outputBuffer.count - 32_768) }
        guard loadedURL == nil else { return }
        let pattern = #"dsh web: (http://127\.0\.0\.1:\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: outputBuffer, range: NSRange(outputBuffer.startIndex..., in: outputBuffer)),
              let range = Range(match.range(at: 1), in: outputBuffer),
              let url = URL(string: String(outputBuffer[range])) else { return }
        loadedURL = url
        webView.load(URLRequest(url: url))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "desktopHarness" else { return }
        if let action = message.body as? String, action == "pick-workspace" {
            pickWorkspace()
            return
        }
        if let body = message.body as? [String: Any], body["action"] as? String == "check-update" {
            checkForUpdates()
        }
    }

    private func pickWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "选择工作区"
        panel.prompt = "选择"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let directory = panel.url else { return }
            self?.adoptWorkspace(directory)
        }
    }

    private func checkForUpdates() {
        emitUpdateState(status: "checking", message: "正在检查更新…")
        guard let url = URL(string: "https://api.github.com/repos/deepseek-ai/deepseek-harness/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DeepSeek-Harness-Desktop", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.finishUpdateCheck(message: "检查更新失败：\(error.localizedDescription)") }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { self.finishUpdateCheck(message: "检查更新失败：服务器没有返回有效响应。") }
                return
            }
            if http.statusCode == 404 {
                DispatchQueue.main.async { self.finishUpdateCheck(message: "当前版本已是最新版本，暂时没有发布可安装更新。") }
                return
            }
            guard http.statusCode == 200, let data, let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                DispatchQueue.main.async { self.finishUpdateCheck(message: "检查更新失败（HTTP \(http.statusCode)）。") }
                return
            }
            DispatchQueue.main.async { self.present(release: release) }
        }.resume()
    }

    private func present(release: GitHubRelease) {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard latest.compare(current, options: .numeric) == .orderedDescending else {
            finishUpdateCheck(message: "当前版本 \(current) 已是最新版本。")
            return
        }

        let asset = release.assets.first { candidate in
            let name = candidate.name.lowercased()
            let architectureMatches = name.contains("arm64") || name.contains("aarch64") || name.contains("apple-silicon")
            return name.contains("mac") && architectureMatches && (name.hasSuffix(".zip") || name.hasSuffix(".dmg"))
        }
        let alert = NSAlert()
        alert.messageText = "发现新版本 \(release.tagName)"
        alert.informativeText = asset == nil
            ? "当前发布没有 Apple Silicon 安装包，可以打开官方发布页查看。"
            : "可以立即下载安装包。下载完成后会在 Finder 中显示。"
        alert.addButton(withTitle: asset == nil ? "打开发布页" : "下载更新")
        alert.addButton(withTitle: "稍后")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            emitUpdateState(status: "idle", message: "当前版本 \(current)")
            return
        }
        if let asset {
            downloadUpdate(asset)
        } else {
            NSWorkspace.shared.open(release.htmlUrl)
            emitUpdateState(status: "available", message: "可更新至 \(release.tagName)")
        }
    }

    private func downloadUpdate(_ asset: GitHubRelease.Asset) {
        guard asset.browserDownloadUrl.scheme == "https", asset.browserDownloadUrl.host == "github.com" else {
            finishUpdateCheck(message: "更新下载地址未通过安全检查。")
            return
        }
        emitUpdateState(status: "downloading", message: "正在下载 \(asset.name)…")
        URLSession.shared.downloadTask(with: asset.browserDownloadUrl) { [weak self] temporary, _, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.finishUpdateCheck(message: "下载更新失败：\(error.localizedDescription)") }
                return
            }
            guard let temporary else {
                DispatchQueue.main.async { self.finishUpdateCheck(message: "下载更新失败：没有收到安装包。") }
                return
            }
            do {
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                let destination = self.availableDownloadURL(in: downloads, named: asset.name)
                try FileManager.default.moveItem(at: temporary, to: destination)
                DispatchQueue.main.async {
                    self.emitUpdateState(status: "downloaded", message: "更新已下载：\(destination.lastPathComponent)")
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                }
            } catch {
                DispatchQueue.main.async { self.finishUpdateCheck(message: "保存更新失败：\(error.localizedDescription)") }
            }
        }.resume()
    }

    private func availableDownloadURL(in directory: URL, named name: String) -> URL {
        let candidate = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let extensionName = candidate.pathExtension
        let stem = candidate.deletingPathExtension().lastPathComponent
        for index in 2...999 {
            let filename = extensionName.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(extensionName)"
            let alternative = directory.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: alternative.path) { return alternative }
        }
        return directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
    }

    private func finishUpdateCheck(message: String) {
        emitUpdateState(status: "idle", message: message)
        let alert = NSAlert()
        alert.messageText = "软件更新"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func emitUpdateState(status: String, message: String) {
        let detail: [String: String] = ["status": status, "message": message]
        guard let data = try? JSONSerialization.data(withJSONObject: detail),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('deepseek-harness-update-state', { detail: \(json) }))")
    }

    private func adoptWorkspace(_ directory: URL) {
        guard let loadedURL, let endpoint = URL(string: "/api/workspace.create", relativeTo: loadedURL) else { return }
        let envelope: [String: Any] = [
            "type": "client-request",
            "rpcId": UUID().uuidString,
            "method": "workspace.create",
            "payload": ["path": directory.path],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data,
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = value["result"] as? [String: Any],
                  result["ok"] as? Bool == true else {
                DispatchQueue.main.async { self?.showStatus(title: "无法添加工作区", detail: "所选文件夹无法注册，请重新选择。") }
                return
            }
            DispatchQueue.main.async { self?.webView.reload() }
        }.resume()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              let loadedURL,
              let host = url.host,
              host != loadedURL.host else {
            decisionHandler(.allow)
            return
        }
        if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

@main
enum DeepSeekHarnessMain {
    private static let delegate = DeepSeekHarnessApp()

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
    }
}
