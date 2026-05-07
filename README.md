<div align="center">

# 📚 Readeck Plugin for KOReader

![](https://img.shields.io/badge/Maintained%20with-GitHub%20Copilot-blue?logo=githubcopilot)  <a title="hits" target="_blank" href="https://github.com/iceyear/readeck.koplugin"><img src="https://hits.b3log.org/iceyear/readeck.koplugin.svg" ></a> ![GitHub contributors](https://img.shields.io/github/contributors/iceyear/readeck.koplugin) ![GitHub License](https://img.shields.io/github/license/iceyear/readeck.koplugin)

English   |   [简体中文](README_ZH.md)

</div>

## 📚 Overview

Readeck Plugin for KOReader is a plugin that allows you to synchronize articles from a Readeck server directly to your KOReader-powered e-reader. Readeck is a simple yet powerful web application that lets you save web content you want to keep forever. This plugin brings that content to your E-ink screen for a focused, distraction-free reading experience.

## 🚧 Project Status

> **Functional but “Cozy” 🏠**

This project started as a **personal, self‑use plugin**, rapidly prototyped with AI assistance (GitHub Copilot). Thanks to valuable feedback and contributions from the community, it has gradually grown into something useful for more people.

The plugin is functional and actively used, but it may not work perfectly in every scenario. The implementation is being moved toward smaller Lua modules with tests and formatting/lint checks.

Due to limited personal time, my focus going forward will mainly be on **maintenance, stability, and critical bug fixes**.

That said, community involvement is very welcome:

* PRs are appreciated, whether for refactoring, bug fixes, or small improvements
* Feel free to **open Feature Requests** in the Issues — discussion and collaborative implementation are encouraged
* You are welcome to **fork this project or reuse its ideas** as a starting point (“reinventing the wheel” is totally fine here)

This is a cozy project, and I hope it can remain one — with the community’s help 💖

## 🌟 Features

* 🔄 **Sync & Download**: Download articles from your Readeck server to a dedicated folder on your KOReader device.
* 🏷️ **Tag Filtering**: Only download articles with a specific tag, ignore articles with certain tags, and auto-add tags to newly created bookmarks.
* ↕️ **Sorting**: Sort server articles by added/published date, duration, site name, or title.
* 🗄️ **Completion Actions**: Optionally archive or delete finished/100%-read articles in Readeck, and remove local files only after the server action succeeds.
* 🧾 **History Cleanup**: Optionally remove finished/fully-read Readeck documents from KOReader history.
* 🌐 **Add to Readeck (with Queue)**: Add links from KOReader; if offline, links are stored in a queue and retried next time you’re online.
* 📝 **Review → Tags**: Write comma-separated tags in the **Review** field and send them back to Readeck as labels.
* ⭐ **Star / Like Sync**: Optionally mark entries as liked on Readeck based on your KOReader star rating threshold, and/or label entries with their star rating (e.g. `3-star`).
* 📊 **Reading Progress Sync (beta)**: Sync KOReader reading progress below 100% back to Readeck, and apply newer incomplete Readeck progress to local sidecars. Disabled by default.
* 🖍️ **Highlight Sync**: Merge Readeck annotations into KOReader highlights and export local KOReader highlights, notes, and mapped colors back to Readeck. The plugin reads `/api/info` and adapts newer annotation fields to the Readeck server version.
* 🕒 **Metadata Sync**: Set downloaded file timestamps from Readeck metadata and add estimated reading time as a KOReader keyword.
* 🔁 **Periodic Sync (beta)**: Optionally let KOReader schedule recurring Readeck syncs while the app is running.
* ⚡ **Cooperative Downloads**: Download articles through a bounded async queue. Concurrency is configurable from 1 to 3 so slower devices can stay responsive.
* 🌍 **Plugin i18n Fallbacks**: Reuse KOReader gettext when available, then fall back to plugin-provided English/Chinese strings.

## 📥 Installation

1. Clone or download this repository.
2. Locate your KOReader plugins directory (usually `koreader/plugins/`).
3. Copy the `readeck.koplugin` folder into the plugins directory.
4. Restart KOReader completely (use **Exit** from the menu, then relaunch).

> **Compatibility warning:** The refactored plugin settings are not fully compatible with very old experimental builds. If you upgrade from an early version and see odd sync or authentication behavior, clear the old `readeck.lua` plugin settings and configure the plugin again before filing a bug.

## ⚙️ Configuration

To use this plugin, you need:

1. A running Readeck server (learn more at [readeck.org](https://readeck.org))
2. A dedicated download folder configured on your KOReader

### Initial Setup

1. Go to **Main Menu > Readeck > Settings > Configure Readeck server**
2. Enter the server URL (without `/api`)
3. Choose one authentication method:

   * **OAuth (Device Flow)** (recommended for convenience; used when the server advertises OAuth support), or
   * **API Token**
4. Set a dedicated **Download folder**
5. (Optional) Configure:

   * **Only download articles with tag**
   * **Sort articles by**
   * **Tags to ignore**
   * **Tags to add to new articles**

## 🛠️ Usage Instructions

### Downloading New Articles

1. Go to **Main Menu > Readeck > Synchronize articles with server**
2. Articles will be downloaded according to your tag filter / ignore settings

> Tip: If **Process completion actions when syncing** is enabled, archiving/deleting in Readeck can be handled automatically during sync.

### Marking Articles as Finished

When you finish reading an article:

1. Mark it as finished (e.g., set status to **complete**) and/or read it to **100%**
2. Go to **Main Menu > Readeck > Process finished/read articles**
3. The plugin will apply your configured completion action, sync highlights first, and remove local files only after Readeck confirms the action

### Adding Articles

When browsing the web:

1. Open a link in KOReader's browser
2. Select **Add to Readeck** from the external link menu

If you are offline:

1. The link will be added to a **download queue**
2. It will be retried automatically the next time you’re online (during sync)

### Syncing Highlights

1. Open a downloaded Readeck article in KOReader
2. Go to **Main Menu > Readeck > Sync current article highlights**
3. Readeck annotations are imported into KOReader highlights, and local KOReader highlights with supported notes/colors are uploaded to Readeck as annotations. Duplicates are skipped if they overlap.

### Syncing Reading Progress

During sync, the plugin can send KOReader's local reading progress below 100% back to Readeck without archiving the article. It also applies newer incomplete Readeck `read_progress` values to KOReader sidecars when articles are downloaded or skipped because they already exist locally. Articles that are being processed by completion actions are handled by the archive/delete flow instead.

## ⚠️ Notes

* The download directory should be exclusively used by the Readeck plugin; existing files in it may be deleted
* Username/password login is no longer supported; use OAuth or an API token
* The **Send review as tags** option allows you to add tags while reading

## 🔧 Advanced Settings

### Completion Action Options

* **Process finished articles in Readeck**: Process entries marked as finished
* **Process 100% read articles in Readeck**: Process entries that reached 100% progress
* **Archive completion actions instead of deleting**: Archive entries instead of permanently deleting them
* **Process completion actions when syncing**: Run completion actions automatically during sync
* **Sync reading progress to Readeck (beta)**: Update Readeck's reading progress below 100% for local articles that remain on the device, and accept newer incomplete Readeck progress locally
* **Remove local files missing from Readeck**: Remove local files that no longer exist on the server

### Tag Settings

* **Only download articles with tag**: Only download entries with a specific label
* **Tags to ignore**: Skip entries containing any of the specified tags
* **Tags to add to new articles**: Auto-label newly added bookmarks (including links added from KOReader)

### Sorting & Sync Limits

* **Sort articles by**: Choose the server-side ordering (added/published/duration/site/title)
* **Number of articles to download per sync**: Limit how many entries are processed per sync run
* **Concurrent downloads**: Choose how many article downloads run at once. Use `1` for the safest behavior on very slow devices, or `2-3` when the device and server can handle it.
* **Periodic sync (beta)**: Enable a KOReader timer and choose the interval in minutes
* **Language**: Follow KOReader's language, or force the plugin UI to English / Simplified Chinese

### Star / Like Sync

* **“Like” entries in Readeck**: Mark entries as liked based on your KOReader star rating threshold
* **Label entries in Readeck with their star rating**: Add labels like `1-star` … `5-star`

### Review → Tags

* **Send review as tags**: Treat comma-separated content in the KOReader **Review** field as tags and send them to Readeck

### History Management

* **Remove finished articles from history**: Clean up KOReader history for completed entries
* **Remove 100% read articles from history**: Clean up history for fully read entries

### Authentication & Networking

* **Authorize with OAuth**: Use device-flow OAuth login (with optional QR code)
* **Reset access token**: Clear token so the plugin re-authenticates
* **Clear all cached tokens**: Remove cached OAuth/token data
* **API token**: Configure a Readeck API token
* **Set timeout**: Tune network timeouts for slow connections or large downloads

## Development

* `make deps`
* `make format-check`
* `make test`
* `make lint`
* `make koreader-smoke`
* `make koreader-build`
* `make koreader-runtime-smoke`

`make deps` uses LuaRocks to install development tools from `readeck-koplugin-dev-0.1-1.rockspec`. The plugin itself does not depend on LuaRocks at runtime; it should keep using KOReader's bundled Lua modules and native libraries so it remains portable across Linux, Android, and e-reader builds.

`make koreader-smoke` always runs the fast KOReader-shaped stub smoke test. If a built KOReader emulator runtime exists at `references/koreader/koreader-emulator-x86_64-pc-linux-gnu-debug/koreader`, it also runs the real runtime probe with KOReader's own `luajit`, `setupkoenv.lua`, and unit-test bootstrap. Use `make koreader-build` first, or set `KOREADER_DIR` / `KOREADER_BUILD_DIR` when your KOReader checkout lives elsewhere.

CI runs Stylua, Luacheck, Busted, mock Readeck API tests, the stub smoke test, and a separate KOReader runtime smoke job on GitHub Actions.

## 🔍 Troubleshooting

* If downloads fail, double-check your server URL and authentication settings
* Ensure KOReader has active network access
* Verify that the download directory exists and is writable
* For advanced debugging, check `crash.log` or enable logcat on Android

## 🙏 Credits

* Based on [wallabag2.koplugin by clach04](https://github.com/clach04/wallabag2.koplugin)
* [KOReader](https://github.com/koreader/koreader) — The best FOSS e-ink book reader
* [Readeck](https://readeck.org) — Making web content readable again
