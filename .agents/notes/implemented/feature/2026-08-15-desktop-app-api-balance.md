# Agent Note: Standalone desktop app and API balance surface

Status: implemented

English | [中文](2026-08-15-desktop-app-api-balance.zh.md)

## Problem

DeepSeek Harness was distributed as a command-line-launched web application. Desktop users needed a self-contained application that preserves the web interface, starts without an external runtime or terminal, and makes the DeepSeek API balance visible without exposing the API key to browser code.

## Decision

The repository ships a macOS desktop wrapper in `desktop/`. It embeds a compressed Node.js runtime, expands that runtime into the application's private support directory on first launch, starts the production Harness server on a random loopback-only port, and displays the existing web client in `WKWebView`. An original high-resolution icon is stored as a PNG master and a macOS ICNS asset. `desktop/build-app.sh` copies the icon, builds, prunes, signs, and rejects an application larger than 200 MiB.

The wrapper supplies the standard macOS Edit menu, so WebKit text and secure fields receive copy-and-paste shortcuts. While no Workspace exists, a document-end bridge intercepts the otherwise inert add/select/new-session controls and opens `NSOpenPanel`; the selected directory is adopted through the loopback-only `workspace.create` API, after which the unchanged web client reloads into its normal Workspace flow. The bridge handles only this empty-state bootstrap and does not replace established Workspace navigation.

The session-log-export plugin owns a header balance control beside the existing export control and a separate settings update action. A browser-side controller refreshes immediately and every 30 seconds. Its same-origin `/api/desktop.balance` request reaches a host route that resolves `DEEPSEEK_API_KEY` through the credentials service and calls DeepSeek's balance API. The route returns balance data or a normalized error; it never returns the credential.

The desktop wrapper also exposes its bundled version and software-update message channel to the web client. A desktop-only General settings row asks the native wrapper to check the official GitHub Releases API. A newer release offers the matching macOS Apple Silicon ZIP or DMG for download into the user's Downloads directory and reveals it in Finder; a release without a matching asset opens its official release page. The ordinary browser build does not register this row.

## Alternatives considered

- **Reimplement the interface as native views** — would duplicate the existing web product and make visual and behavior parity expensive to maintain.
- **Call the DeepSeek API directly from browser code** — would require sending the secret into the renderer and widen the credential exposure boundary.
- **Depend on a system Node.js installation** — would reduce bundle size but violate direct launch on machines without developer tooling.
- **Bundle an uncompressed runtime** — starts faster on first launch but pushes the deliverable closer to the 200 MiB limit and leaves less room for product growth.
- **Install updates over the running application automatically** — would need a privileged or separately signed helper for applications in protected locations; downloading and revealing the official installer keeps replacement explicit.

## Consequences

The desktop application follows the web UI automatically, users can launch it by opening the app bundle, and the credential remains in the host process. The first launch performs a one-time private runtime expansion. Updates require an official release asset and explicit application replacement after download. The current bundle targets macOS Apple Silicon; other operating systems require platform-specific wrappers and runtime artifacts. Build verification covers the web/library build, application size gate, code-signature verification, direct launch, loopback server startup, balance-route missing-key behavior, update-row registration and native update-check feedback, native Workspace selection, secure-field paste without saving, a completed DeepSeek turn, and creation of a subsequent blank conversation.
