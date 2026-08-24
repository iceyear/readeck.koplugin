# Changelog

## Unreleased

### English

#### Added

- Added an article browser, reachable from **Readeck sync → Browse articles**, that lists everything in your Readeck account without downloading it. Rows not yet on the device are marked with a cloud icon; tapping one downloads just that article.
- Added seven browsing buckets: all, unread, archived, favorite, collections, by label, and by source.
- Added label drill-down. Each label you pick narrows the list, and the remaining labels are re-counted and re-ordered against only the articles that still match, so a label that would return nothing is never offered. The back arrow deselects one label at a time.
- Added a source picker listing every site in your account with its article count.
- Added Readeck collections to the browser. A collection whose server-side filter includes a full-text search is prefixed with `~` and counted on its other filters only, because the device has no article text to search.
- Added an on-device search over titles, authors, sources, and labels.
- Added browser sorting: newest, oldest, title, source, longest read, shortest read, and most read.
- Added long-press actions on an article: open, download, add to or remove from favorites, archive or move to unread, delete the local file, and article details.
- Added a local article catalog so the browser works fully offline. It is fetched once, kept up to date with a delta request at the end of each normal sync, and refreshed or rebuilt on demand from the browser menu.
- Added a degraded offline fallback that reconstructs a browsable list from downloaded files and their KOReader metadata when no catalog exists yet.
- The browser now hides what a sync would skip: video bookmarks, articles missing the **Only download articles with tag** label, and articles carrying a tag from **Tags to ignore**. The subtitle reports how many are hidden, and **Hide what sync skips** in the browser menu turns it off when you want to reach one of them.

#### Changed

- Reading progress from the device is now merged with the server's when deciding whether an article counts as unread, so an article finished in KOReader but not yet synced no longer shows up as unread in the browser.
- Article list requests can now express repeated and quoted filter parameters, which is what makes multi-word labels and multi-value filters work.
- Tapping an article in the browser that is not on the device yet now downloads **and** opens it. It used to stop at the list once the download finished, so reading an article took two taps. Long-press → **Download** still downloads without leaving the list.
- **Tags to ignore** now trims spaces around each tag, so `work, later` ignores `later` instead of a tag literally named ` later`.
- **Only download articles with tag** is now sent to the server as a quoted term, so a multi-word tag matches that tag instead of being split into two separate requirements.

#### Fixed

- Fixed every collection in the browser showing zero articles. Readeck sends `null` for a filter a collection does not restrict, and KOReader's JSON decoder represents `null` as a value that is neither `nil` nor a boolean, so the "is it archived?" and "is it a favorite?" tests rejected every article. An unset filter is now correctly read as "no restriction".
- Fixed a collection's label filter being ignored. Readeck stores it as a search expression rather than a list, and multi-word labels are quoted, so it is now parsed with the same syntax the plugin already uses to send label filters.
- Fixed the catalog file being written with an unreadable value, which made KOReader silently fall back to the previous backup. Collections stored by an earlier build are repaired the next time the browser opens, with no re-sync needed.

### 中文

#### 新增

- 新增文章浏览器，可从 **Readeck 同步 → 浏览文章** 进入，无需下载即可列出 Readeck 账户中的全部文章。尚未下载到设备的条目会标有云图标，轻点即可仅下载该篇文章。
- 新增七个浏览分类：全部、未读、已归档、收藏、收藏集、按标签、按来源。
- 新增标签逐层筛选。每选中一个标签都会缩小列表范围，剩余标签会仅针对仍然匹配的文章重新计数和排序，因此不会出现选中后结果为空的标签。返回键每次取消一个标签。
- 新增来源选择器，列出账户中的所有站点及其文章数量。
- 新增 Readeck 收藏集浏览。若某个收藏集的服务器端筛选包含全文搜索，其名称会加上 `~` 前缀，并且仅按其他筛选条件计数，因为设备上没有文章正文可供搜索。
- 新增设备端搜索，可搜索标题、作者、来源和标签。
- 新增浏览排序：最新、最早、标题、来源、阅读时长最长、阅读时长最短、阅读最多。
- 新增文章长按操作：打开、下载、加入或取消收藏、归档或标为未读、删除本地文件、查看文章详情。
- 新增本地文章目录，使浏览器可完全离线使用。目录仅获取一次，随后在每次常规同步结束时通过增量请求保持更新，也可从浏览器菜单手动刷新或重建。
- 新增离线降级方案：在尚无目录时，根据已下载文件及其 KOReader 元数据重建可浏览的列表。
- 浏览器现在会隐藏同步会跳过的内容：视频书签、缺少**仅下载带此标签的文章**所指标签的文章，以及带有**要忽略的标签**中任一标签的文章。副标题会显示隐藏了多少篇；如需查看其中某篇，可在浏览器菜单中关闭**隐藏同步跳过的内容**。

#### 变更

- 判断文章是否未读时，现在会将设备上的阅读进度与服务器进度合并，因此在 KOReader 中已读完但尚未同步的文章不会再显示为未读。
- 文章列表请求现在支持重复参数和带引号的筛选参数，这也是多词标签和多值筛选得以生效的基础。
- 在浏览器中轻点尚未下载的文章，现在会下载**并**打开该文章。此前下载完成后会停留在列表，导致阅读一篇文章需要点两次。长按 → **下载** 仍然只下载而不离开列表。
- **要忽略的标签**现在会去除每个标签前后的空格，因此 `work, later` 会忽略 `later`，而不是一个名为 ` later` 的标签。
- **仅下载带此标签的文章**现在以带引号的词条发送给服务器，因此多词标签会作为整体匹配，而不再被拆成两个独立条件。

#### 修复

- 修复浏览器中所有收藏集都显示 0 篇文章的问题。收藏集未限制的筛选项，Readeck 会返回 `null`，而 KOReader 的 JSON 解码结果既不是 `nil` 也不是布尔值，导致“是否已归档”和“是否已收藏”的判断否决了每一篇文章。现在未设置的筛选项会被正确理解为“不做限制”。
- 修复收藏集的标签筛选被忽略的问题。Readeck 将其存储为搜索表达式而非列表，且多词标签带引号，现在会使用插件发送标签筛选时的同一套语法进行解析。
- 修复目录文件写入了无法读取的值，导致 KOReader 静默回退到上一个备份的问题。由旧版本写入的收藏集会在下次打开浏览器时自动修复，无需重新同步。

## v0.1.1 - 2026-05-07

Source: https://github.com/iceyear/readeck.koplugin  
License: MIT

### English

This release is a maintenance and refactoring release focused on reliability, clearer sync behavior, Readeck 0.22.2 compatibility, and a more maintainable plugin structure.

#### Added

- Added plugin-provided i18n fallbacks with English and Simplified Chinese, while still reusing KOReader gettext strings when available.
- Added configurable log levels: `Info`, `Debug`, `Warnings`, and `Errors`.
- Added Readeck server feature detection through `/api/info`, with an automatic mode plus manual modern/legacy compatibility modes.
- Added bidirectional highlight sync for Readeck annotations and KOReader highlights, including note and color support for modern Readeck servers.
- Added highlight conflict strategies: merge changes, let Readeck overwrite KOReader, or let KOReader overwrite Readeck.
- Added a remote-deleted highlight policy so users can preserve local highlights or respect Readeck-side deletions.
- Added reading progress sync below 100% between KOReader and Readeck.
- Added file timestamp sync from Readeck metadata and estimated reading time as a KOReader keyword.
- Added periodic sync beta support.
- Added a dismissible, movable sync progress popup that can be reopened from the Readeck menu while sync is still running.
- Added KOReader runtime smoke tests and mock Readeck API network smoke tests for OAuth, article download, and highlight sync.

#### Changed

- Refactored the previous single-file implementation into smaller Lua modules; `main.lua` is now a compact plugin assembly entry point.
- Reorganized settings into clearer groups: server, authentication, client, article selection, article actions, highlights, periodic sync, and ratings/review tags.
- Reworked authentication around API token and OAuth device flow; username/password login is no longer exposed because current Readeck versions no longer support it.
- Improved sync status wording so archive/delete actions are reported accurately and less alarmingly.
- Improved article sync progress wording to show checked, downloaded, skipped, failed, and planned/completed local or remote actions.
- Made subprocess downloads experimental and explicit opt-in; failed or timed-out subprocess downloads now fall back to the stable blocking downloader.
- Reduced UI stalls by rendering status messages before slow work and by using async/cooperative paths only when KOReader runtime support is available.
- Updated development workflow with Stylua, Luacheck, Busted, KOReader runtime probes, and GitHub Actions CI.
- Documented the project as MIT-licensed open source at https://github.com/iceyear/readeck.koplugin and exposed this in the KOReader plugin About dialog.

#### Fixed

- Fixed misleading “Deleted” sync status text when articles were archived instead of deleted.
- Fixed repeated full-list redownload behavior by skipping already-downloaded articles by embedded Readeck ID.
- Fixed finished/read local actions being skipped incorrectly during sync in common archive workflows.
- Fixed Readeck 0.22.2 highlight payload compatibility for notes and transparent/none colors.
- Fixed progress popup behavior so dismissing it does not stop background sync progress tracking.
- Fixed saved experimental subprocess-download settings from old test builds being migrated back to stable defaults unless users explicitly opt in again.

#### Upgrade Notes

- Readeck username/password login is not supported. Use OAuth device flow or an API token.
- If upgrading from an early experimental build and sync/authentication behaves strangely, clear the old `readeck.lua` plugin settings and configure the plugin again.
- Experimental subprocess downloads are off by default. Keep them disabled unless you are testing that backend on your device/server.

### 中文

这是一个偏维护和重构的版本，重点是提高同步可靠性、理清同步行为、兼容 Readeck 0.22.2，并把插件结构整理到更容易长期维护的状态。

#### 新增

- 新增插件自带 i18n 回退，提供英文和简体中文，同时仍会优先复用 KOReader 已有 gettext 文本。
- 新增日志等级设置：`Info`、`Debug`、`Warnings`、`Errors`。
- 新增通过 `/api/info` 自动探测 Readeck 服务端能力，并支持手动固定新版/旧版兼容模式。
- 新增 Readeck annotations 与 KOReader highlights 的双向高亮同步，并支持新版 Readeck 的笔记和颜色字段。
- 新增高亮冲突策略：合并变更、Readeck 覆盖 KOReader、KOReader 覆盖 Readeck。
- 新增远端已删除高亮的处理策略：可保留本地高亮，也可尊重 Readeck 远端删除。
- 新增低于 100% 的阅读进度在 KOReader 与 Readeck 之间同步。
- 新增下载文件按 Readeck 元数据设置时间戳，并将预计阅读时间写入 KOReader 关键词。
- 新增周期同步 Beta。
- 新增可关闭、可移动的同步进度框；同步仍在进行时，可从 Readeck 菜单重新显示。
- 新增 KOReader runtime smoke 测试和 mock Readeck API 网络 smoke 测试，覆盖 OAuth、文章下载和高亮同步。

#### 变更

- 将原本单文件为主的实现重构为多个较小的 Lua 模块；`main.lua` 现在只负责插件装配。
- 重新整理设置菜单分组：服务器、认证、客户端、文章选择、文章动作、高亮、周期同步、评分/评论标签。
- 认证流程改为围绕 API token 和 OAuth 设备授权；当前 Readeck 已不支持用户名/密码登录，因此插件不再暴露该方式。
- 改进同步状态文案，归档和删除会分别显示，避免“明明归档却显示删除”的惊吓感。
- 改进文章同步进度文案，会显示已检查、已下载、已跳过、失败，以及本地/远端即将或已经执行的动作。
- 子进程下载改为实验性显式开启；如果失败或超时，会回退到稳定的阻塞下载路径。
- 减少 UI 卡顿：慢操作前先渲染状态提示，并且只在 KOReader runtime 支持时使用异步/协作式路径。
- 更新开发流程，加入 Stylua、Luacheck、Busted、KOReader runtime probe 和 GitHub Actions CI。
- 明确项目以 MIT 协议开源，源码仓库为 https://github.com/iceyear/readeck.koplugin，并在 KOReader 插件“关于”弹窗中显示。

#### 修复

- 修复设置为归档时，状态消息仍显示 “Deleted” 的误导性问题。
- 修复同步时可能重复处理整批已下载文章的问题，现在会通过文件名内嵌的 Readeck ID 跳过已存在文章。
- 修复常见归档流程中，同步时本地已完成/已读动作可能被错误跳过的问题。
- 修复 Readeck 0.22.2 高亮 payload 对笔记和透明/none 颜色字段的兼容性。
- 修复进度框被关闭后影响后台同步进度追踪的问题。
- 修复早期测试版本保存过的实验性子进程下载设置：升级后会回到稳定默认值，除非用户再次显式开启。

#### 升级提示

- 不再支持 Readeck 用户名/密码登录，请使用 OAuth 设备授权或 API token。
- 如果从很早期实验版本升级后，同步或认证表现异常，请清除旧的 `readeck.lua` 插件配置并重新配置。
- 实验性子进程下载默认关闭。除非你正在专门测试该后端在自己设备/服务器上的表现，否则建议保持关闭。
