<div align="center">

# 📚 Readeck Plugin for KOReader

<a title="hits" target="_blank" href="https://github.com/iceyear/readeck.koplugin"><img src="https://hits.b3log.org/iceyear/readeck.koplugin.svg" ></a> ![GitHub contributors](https://img.shields.io/github/contributors/iceyear/readeck.koplugin) ![GitHub License](https://img.shields.io/github/license/iceyear/readeck.koplugin)

English &nbsp;&nbsp;|&nbsp;&nbsp; [简体中文](README_ZH.md)

</div>

## 📚 Overview

Readeck Plugin for KOReader is a plugin that allows you to synchronize articles from a Readeck server to your KOReader device. Readeck is a simple web application that lets you save the precious readable content of web pages you like and want to keep forever.

## 🌟 Features

- 📊 **Reading Progress**: Track reading progress and handle articles accordingly.
- 🏷️ **Tag Support**: Filter articles by tags and ignore articles with specific tags.
- 🔍 **Flexible Configuration**: Easily configure all settings through a user-friendly interface.
- 🗑️ **Smart Deletion**: Optionally delete or archive articles from the server when finished or read.
- 📝 **Annotation Sync**: Send review comments as tags back to the Readeck server.

## 📥 Installation

1. Clone the repo's source code.
2. Navigate to the KOReader plugins directory.
3. Copy the `readeck.koplugin` folder to the plugins directory.
4. Restart KOReader completely (use the 'Exit' option from the menu)

## ⚙️ Configuration

To use this plugin, you need:

1. A running Readeck server (learn more at [readeck.org](https://www.readeck.org))
2. An API token or username/password to access the server
3. A download folder configured on your KOReader

### Initial Setup

1. Go to Main Menu > New: Readeck > Settings > Configure Readeck server
2. Enter the server URL (without the `/api` path)
3. Enter an API token (recommended) or username and password(it would be used to create a token for KOReader on the server.)
4. Set a download folder (it's recommended to use a dedicated folder)

## 🛠️ Usage Instructions

### Downloading New Articles

1. Go to Main Menu > New: Readeck > Retrieve new articles from server
2. Articles matching your tag filter settings will be downloaded

### Marking Articles as Finished

When you finish reading an article:

1. Set the reading status to "complete" in the article or read to 100%
2. Go to Main Menu > New: Readeck > Delete finished articles remotely
3. The article will be archived according to your settings

### Adding Articles

When browsing the web:

1. Open a link in KOReader's browser
2. Select "Add to Readeck" from the external link menu

Or when offline:

1. The link will be added to the download queue
2. It will be processed automatically the next time you connect

## ⚠️ Notes

- The download directory should be exclusively used by the Readeck plugin, existing files in it may be deleted
- Using an API token is more secure and efficient than username/password
- The "Send review as tags" option allows you to add tags while reading

## 🔧 Advanced Settings

### Article Deletion Options

- **Delete finished articles remotely**: Delete articles marked as complete from the server
- **Delete 100% read articles remotely**: Delete articles that have been read to 100%
- **Mark as archived instead of deleting**: Archive articles instead of completely removing them from the server
- **Process deletions when downloading**: Automatically process articles for deletion when downloading new ones
- **Synchronize remotely deleted files**: Delete local files that have been removed from the server

### Tag Settings

- **Filter articles by tag**: Only download articles with specific tags
- **Ignore tags**: Don't download articles with specified tags
- **Automatic tags**: Add tags automatically to newly added articles

### History Management

- **Remove finished articles from history**: Remove completed articles from KOReader's reading history
- **Remove 100% read articles from history**: Remove fully read articles from history

## 🔍 Troubleshooting

- If downloads fail, check your server URL and authentication settings.
- For connection issues, verify that KOReader has network access.
- If articles aren't being processed correctly, ensure the download folder is properly set.
- Advanced logging with logcat can be enabled in the code for debugging purposes.

### Pikapod Hosting Compatibility

When using Readeck instances hosted on Pikapod:

- The plugin communicates directly with the Readeck API and should work normally
- If you experience issues with the web interface, these are typically related to the hosting environment's Content Security Policy (CSP)
- CSP violations in the web interface do not affect the KOReader plugin's functionality
- Ensure your Pikapod instance is properly configured and accessible via the API endpoints

## 🙏 Credits

- Based on [wallabag2.koplugin by clach04](https://github.com/clach04/wallabag2.koplugin)
- [KOReader](https://github.com/koreader/koreader), a FOSS e-book reader application.
- [Readeck](https://readeck.org), a simple web application that lets you save the precious readable content of web pages you like and want to keep forever.
