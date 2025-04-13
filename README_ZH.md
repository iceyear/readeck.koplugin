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
- 🗑️ **智能删除**：可选择将已完成或已阅读的文章从服务器删除或归档。
- 📝 **批注同步**：将评论作为标签同步回 Readeck 服务器。

## 📥 安装

1. 克隆仓库源代码。
2. 导航到 KOReader 插件目录。
3. 将 `readeck.koplugin` 文件夹复制到插件目录中。
4. 完全重启 KOReader（使用菜单中的"退出"选项）

## ⚙️ 配置

要使用此插件，你需要：

1. 一个运行中的 Readeck 服务器（在 [readeck.org](https://www.readeck.org) 了解更多）
2. 访问服务器的 API 令牌或用户名/密码
3. 在 KOReader 上配置下载文件夹

### 初始设置

1. 进入主菜单 > 新：Readeck > 设置 > 配置 Readeck 服务器
2. 输入服务器 URL（不包含 `/api` 路径）
3. 输入 API 令牌（推荐）或用户名和密码（将用于在服务器上为 KOReader 创建令牌）
4. 设置下载文件夹（建议使用专用文件夹）

## 🛠️ 使用说明

### 下载新文章

1. 进入主菜单 > 新：Readeck > 从服务器获取新文章
2. 符合标签过滤设置的文章将被下载

### 标记文章为已完成

当你完成一篇文章的阅读后：

1. 在文章中将阅读状态设置为"完成"或阅读至 100%
2. 进入主菜单 > 新：Readeck > 远程删除已完成文章
3. 文章将根据你的设置被归档

### 添加文章

浏览网页时：

1. 在 KOReader 的浏览器中打开链接
2. 从外部链接菜单中选择"添加到 Readeck"

或者在离线状态下：

1. 链接将被添加到下载队列
2. 下次连接网络时自动处理

## ⚠️ 注意事项

- 下载目录应专门用于 Readeck 插件，其中的现有文件可能会被删除
- 使用 API 令牌比用户名/密码更安全和高效
- "将评论作为标签发送"选项允许你在阅读时添加标签

## 🔧 高级设置

### 文章删除选项

- **远程删除已完成文章**：将标记为完成的文章从服务器上删除
- **远程删除已读 100% 的文章**：将阅读进度达到 100% 的文章从服务器上删除
- **标记为归档而非删除**：将文章标记为归档而不是从服务器上完全删除
- **下载时处理删除**：在下载新文章时自动处理需要删除的文章
- **同步远程删除的文件**：删除本地已从服务器上删除的文件

### 标签设置

- **按标签过滤文章**：只下载包含特定标签的文章
- **忽略标签**：不下载包含指定标签的文章
- **自动标签**：为新添加的文章自动添加标签

### 历史记录管理

- **从历史记录中移除已完成文章**：将已完成的文章从 KOReader 历史记录中移除
- **从历史记录中移除已读 100% 的文章**：将已读完的文章从历史记录中移除

## 🔍 故障排除

- 如果下载失败，请检查服务器 URL 和认证设置。
- 遇到连接问题时，确认 KOReader 有网络访问权限。
- 如果文章处理不正确，确保下载文件夹设置正确。
- 可以在代码中启用使用 logcat 的高级日志记录进行调试。

## 🙏 致谢

- 基于 [clach04 的 wallabag2.koplugin](https://github.com/clach04/wallabag2.koplugin) 开发
- [KOReader](https://github.com/koreader/koreader)，一个开源电子书阅读应用。
- [Readeck](https://readeck.org)，一个简洁的网络应用，让你能够保存喜欢并希望永久保留的网页内容。
