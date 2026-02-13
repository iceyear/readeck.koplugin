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

The plugin is functional and actively used, but it may not work perfectly in every scenario. The current implementation also lives in a single, rather “heroic” Lua file, which leaves room for future refactoring and improvement.

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
* 🗑️ **Smart Deletion / Archiving**: Optionally delete or archive finished/100%-read articles on the server, and clean up local files accordingly.
* 🧾 **History Cleanup**: Optionally remove finished/fully-read Readeck documents from KOReader history.
* 🌐 **Add to Readeck (with Queue)**: Add links from KOReader; if offline, links are stored in a queue and retried next time you’re online.
* 📝 **Review → Tags**: Write comma-separated tags in the **Review** field and send them back to Readeck as labels.
* ⭐ **Star / Like Sync**: Optionally mark entries as liked on Readeck based on your KOReader star rating threshold, and/or label entries with their star rating (e.g. `3-star`).
* 🖍️ **Highlight Export**: Export KOReader highlights to Readeck as annotations (with overlap detection to avoid duplicates).

## 📥 Installation

1. Clone or download this repository.
2. Locate your KOReader plugins directory (usually `koreader/plugins/`).
3. Copy the `readeck.koplugin` folder into the plugins directory.
4. Restart KOReader completely (use **Exit** from the menu, then relaunch).

## ⚙️ Configuration

To use this plugin, you need:

1. A running Readeck server (learn more at [readeck.org](https://www.readeck.org))
2. A dedicated download folder configured on your KOReader

### Initial Setup

1. Go to **Main Menu > Readeck > Settings > Configure Readeck server**
2. Enter the server URL (without `/api`)
3. Choose one authentication method:

   * **OAuth (Device Flow)** (recommended for convenience), or
   * **API Token**, or
   * **Username / Password** (legacy fallback; used to obtain an access token)
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

> Tip: If **Process deletions when downloading** is enabled, deletions/archiving can be handled automatically during sync.

### Marking Articles as Finished

When you finish reading an article:

1. Mark it as finished (e.g., set status to **complete**) and/or read it to **100%**
2. Go to **Main Menu > Readeck > Delete finished articles remotely**
3. The plugin will archive/delete entries according to your settings, and remove local files as needed

### Adding Articles

When browsing the web:

1. Open a link in KOReader's browser
2. Select **Add to Readeck** from the external link menu

If you are offline:

1. The link will be added to a **download queue**
2. It will be retried automatically the next time you’re online (during sync)

### Exporting Highlights

1. Open a downloaded Readeck article in KOReader
2. Go to **Main Menu > Readeck > Export highlights to server**
3. Highlights will be uploaded to Readeck as annotations (duplicates are skipped if they overlap)

## ⚠️ Notes

* The download directory should be exclusively used by the Readeck plugin; existing files in it may be deleted
* Using an API token is more secure and reliable than username/password authentication
* The **Send review as tags** option allows you to add tags while reading

## 🔧 Advanced Settings

### Article Deletion Options

* **Remotely delete finished articles**: Delete/archive entries marked as finished
* **Remotely delete 100% read articles**: Delete/archive entries that reached 100% progress
* **Mark as archived instead of deleting**: Archive entries instead of permanently deleting them
* **Process deletions when downloading**: Handle deletions automatically during sync
* **Synchronize remotely deleted files**: Remove local files that were deleted on the server

### Tag Settings

* **Only download articles with tag**: Only download entries with a specific label
* **Tags to ignore**: Skip entries containing any of the specified tags
* **Tags to add to new articles**: Auto-label newly added bookmarks (including links added from KOReader)

### Sorting & Sync Limits

* **Sort articles by**: Choose the server-side ordering (added/published/duration/site/title)
* **Number of articles to download per sync**: Limit how many entries are processed per sync run

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
* **Clear all cached tokens**: Remove cached OAuth/token data and credentials
* **Alternative credentials**: Configure API token / username / password (Legacy) fallback
* **Set timeout**: Tune network timeouts for slow connections or large downloads

## 🔍 Troubleshooting

* If downloads fail, double-check your server URL and authentication settings
* Ensure KOReader has active network access
* Verify that the download directory exists and is writable
* For advanced debugging, check `crash.log` or enable logcat on Android

## 🙏 Credits

* Based on [wallabag2.koplugin by clach04](https://github.com/clach04/wallabag2.koplugin)
* [KOReader](https://github.com/koreader/koreader) — The best FOSS e-ink book reader
* [Readeck](https://readeck.org) — Making web content readable again
