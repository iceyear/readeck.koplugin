<div align="center">

# 📚 KOReader Readeck 插件

<a title="hits" target="_blank" href="https://github.com/iceyear/readeck.koplugin"><img src="https://hits.b3log.org/iceyear/readeck.koplugin.svg" ></a> ![GitHub contributors](https://img.shields.io/github/contributors/iceyear/readeck.koplugin) ![GitHub License](https://img.shields.io/github/license/iceyear/readeck.koplugin)

[English](README.md) &nbsp;&nbsp;|&nbsp;&nbsp; 简体中文

</div>

## 📚 概述

KOReader Readeck 插件允许你将 Readeck 服务器上的文章同步到 KOReader 设备上。Readeck 是一个简洁的网络应用，让你能够保存喜欢并希望永久保留的网页内容。

## 🌟 特点

- 📊 **阅读进度**：追踪阅读进度并相应处理文章。
- 🏷️ **标签支持**：按标签过滤文章，忽略带有特定标签的文章。
- 🔍 **灵活配置**：通过友好的用户界面轻松配置所有设置。
- 🗄️ **完成动作**：可选择将已完成或已阅读的文章在 Readeck 中归档或删除；只有远端动作成功后才移除本地文件。
- 📊 **阅读进度同步（Beta）**：将仍保留在本地、且低于 100% 的文章阅读进度同步回 Readeck，并把云端更新的未读完进度写回 KOReader sidecar。默认关闭。
- 📝 **高亮同步**：把 Readeck annotations 合并到 KOReader 高亮，并将 KOReader 本地高亮、笔记和映射后的高亮颜色导出回 Readeck。插件会读取 `/api/info`，按 Readeck 服务端版本适配较新的批注字段。
- 🕒 **元数据同步**：下载后根据 Readeck 时间设置本地文件时间戳，并把预计阅读时间写入 KOReader 关键词。
- 🔁 **周期同步（Beta）**：可使用 KOReader 内部定时器定期同步。
- ⚡ **协作式下载队列**：通过有上限的异步队列下载文章，并发数可在 1 到 3 之间配置，低性能设备可设为 1。
- 🌍 **插件 i18n 回退**：优先复用 KOReader gettext，再使用插件内置英文/中文文本。

## 📥 安装

1. 克隆仓库源代码。
2. 导航到 KOReader 插件目录。
3. 将 `readeck.koplugin` 文件夹复制到插件目录中。
4. 完全重启 KOReader（使用菜单中的"退出"选项）

> **兼容性警告：** 重构后的插件配置与很早期的实验版本不完全兼容。如果从旧版本升级后遇到异常的同步或认证行为，请先清除旧的 `readeck.lua` 插件配置并重新配置，再提交问题。

## ⚙️ 配置

要使用此插件，你需要：

1. 一个运行中的 Readeck 服务器（在 [readeck.org](https://readeck.org) 了解更多）
2. 访问服务器的 OAuth 授权或 API 令牌
3. 在 KOReader 上配置下载文件夹

### 初始设置

1. 进入主菜单 > 新：Readeck > 设置 > 配置 Readeck 服务器
2. 输入服务器 URL（不包含 `/api` 路径）
3. 使用 OAuth 设备授权（推荐）或输入 API 令牌
4. 设置下载文件夹（建议使用专用文件夹）

## 🛠️ 使用说明

### 下载新文章

1. 进入主菜单 > Readeck > 与服务器同步文章
2. 符合标签过滤设置的文章将被下载

### 标记文章为已完成

当你完成一篇文章的阅读后：

1. 在文章中将阅读状态设置为"完成"或阅读至 100%
2. 进入主菜单 > Readeck > 处理已完成/已读文章
3. 插件会先同步高亮，再执行你配置的完成动作，远端成功后再移除本地文件

### 添加文章

浏览网页时：

1. 在 KOReader 的浏览器中打开链接
2. 从外部链接菜单中选择"添加到 Readeck"

或者在离线状态下：

1. 链接将被添加到下载队列
2. 下次连接网络时自动处理

### 同步阅读进度

同步时，插件可以把 KOReader 本地低于 100% 的阅读进度同步回 Readeck，而不归档文章。下载文章或因本地已存在而跳过下载时，插件也会把 Readeck 中更新的未读完 `read_progress` 写回 KOReader sidecar。正在被完成动作处理的文章仍由归档/删除流程负责。

### 同步高亮

同步高亮时，插件会先把 Readeck annotations 导入为 KOReader 高亮，再把本地新增的 KOReader 高亮导出回 Readeck。导出时会根据 Readeck 服务端能力决定是否发送笔记字段和透明高亮颜色；旧版本服务端会收到更保守的 payload，避免因为不支持的新字段失败。

默认策略会保留本地高亮：如果远端 Readeck 删除了某条高亮，但 KOReader 本地仍然存在，下一次同步可能会把它恢复到 Readeck。若希望尊重远端删除，可把 **高亮同步冲突策略** 设置为 **尊重远端删除**；这样关联过远端 ID 的本地高亮会保留在 KOReader，但不会重新上传。

## ⚠️ 注意事项

- 下载目录应专门用于 Readeck 插件，其中的现有文件可能会被删除
- 当前 Readeck 已不再支持用户名/密码登录；请使用 OAuth 或 API 令牌
- "将评论作为标签发送"选项允许你在阅读时添加标签

## 🔧 高级设置

### 完成动作选项

- **处理 Readeck 中已完成文章**：处理标记为完成的文章
- **处理 Readeck 中已读 100% 的文章**：处理阅读进度达到 100% 的文章
- **完成动作使用归档而不是删除**：将文章归档而不是永久删除
- **同步时处理完成动作**：同步时自动处理符合条件的文章
- **同步阅读进度到 Readeck（Beta）**：更新仍保留在设备上、且低于 100% 的本地文章阅读进度，并接收云端更新的未读完进度
- **移除 Readeck 中不存在的本地文件**：清理服务器上已不存在的本地文件

### 高亮与周期同步

- **文章同步前同步高亮**：每次文章同步前自动同步本地 Readeck 文章高亮
- **关闭文档时同步高亮**：关闭 Readeck 文档时自动同步当前文章的高亮和笔记
- **高亮同步冲突策略**：选择 Readeck 上已删除的 annotation 是否由 KOReader 恢复，或只保留在本地
- **周期同步（Beta）**：启用 KOReader 内部定时器，并设置同步间隔
- **并发下载**：配置同时下载的文章数量。极慢设备建议使用 `1`；设备和服务器足够时可使用 `2-3`。
- **语言**：跟随 KOReader 语言，或强制插件界面使用英文/简体中文

### 标签设置

- **按标签过滤文章**：只下载包含特定标签的文章
- **忽略标签**：不下载包含指定标签的文章
- **自动标签**：为新添加的文章自动添加标签

### 历史记录管理

- **从历史记录中移除已完成文章**：将已完成的文章从 KOReader 历史记录中移除
- **从历史记录中移除已读 100% 的文章**：将已读完的文章从历史记录中移除

## 开发

- `make deps`
- `make format-check`
- `make test`
- `make lint`
- `make koreader-smoke`
- `make koreader-network-smoke`
- `make koreader-build`
- `make koreader-runtime-smoke`

`make deps` 会通过 LuaRocks 和 `readeck-koplugin-dev-0.1-1.rockspec` 安装开发工具。插件运行时不依赖 LuaRocks，仍然使用 KOReader 自带的 Lua 模块和原生库，以便尽量保持 Linux、Android 和电子书设备构建通用。

`make koreader-smoke` 总会运行快速的 KOReader 形状 stub smoke 测试。如果 `references/koreader/koreader-emulator-x86_64-pc-linux-gnu-debug/koreader` 下已有构建好的 KOReader emulator runtime，它还会使用 KOReader 自己的 `luajit`、`setupkoenv.lua` 和单元测试 bootstrap 运行真实 runtime probe。可以先执行 `make koreader-build`，或者在 KOReader checkout 位于其他路径时设置 `KOREADER_DIR` / `KOREADER_BUILD_DIR`。

`make koreader-network-smoke` 会启动本地 mock Readeck HTTP server，并用 KOReader runtime 通过真实 `socket.http` 访问它。它覆盖 API token、OAuth 表单端点、文章列表、EPUB 下载，以及高亮同步/冲突策略行为，不需要公开 Readeck 实例。

CI 会在 GitHub Actions 中运行 Stylua、Luacheck、Busted、模拟 Readeck API 测试、stub smoke 测试，以及独立的 KOReader runtime/network smoke job。

## 🔍 故障排除

- 如果下载失败，请检查服务器 URL 和认证设置。
- 遇到连接问题时，确认 KOReader 有网络访问权限。
- 如果文章处理不正确，确保下载文件夹设置正确。
- 可以在代码中启用使用 logcat 的高级日志记录进行调试。

## 🙏 致谢

- 基于 [clach04 的 wallabag2.koplugin](https://github.com/clach04/wallabag2.koplugin) 开发
- [KOReader](https://github.com/koreader/koreader)，一个开源电子书阅读应用。
- [Readeck](https://readeck.org)，一个简洁的网络应用，让你能够保存喜欢并希望永久保留的网页内容。
