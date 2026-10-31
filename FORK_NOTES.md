# PiliPlus fork 改动记录

> 给自己看的：改了什么、为什么这么改、还差什么。上游是 [bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)。
> 不是给上游看的 PR 说明，所以会写动机和取舍。

## 0. 工作方式

- 远端：`origin` = fork（可推），`upstream` = 上游（**push URL 设成了 `no_push`**，防误推）
- 同步上游：`git fetch upstream && git merge upstream/main`，冲突时优先保留本 fork 的改动
- 提交风格：中文 `feat:` / `fix:` / `chore:`；不为版本号单独提交
- 只推 origin，不向上游提 PR（除非哪天想回报）

## 1. 特性清单

| 特性 | 动机 | 提交 | 状态 |
|---|---|---|---|
| 表情包下载 + 自定义保存路径 | 评论区表情想存下来，手机/桌面路径要能自己选 | `bea4ab399` 起 4 个 | 已完成 |
| 桌面端网页标签页 | PC 上要边看 B 站边开别的网页，但不想挤占移动端布局 | `ff37e15ef` | 已完成 |
| CDN 一键测速并选择最快 | 上游 PR #3091，自己用着有用就移植 | `ac9fb8e4b` | 已完成 |
| 关键词过滤列表化 + 正则模式 | 上游 PR #3344，`a\|b\|c` 太难维护 | `2716b79d3` | 已完成 |
| WebDAV 备份（含评论记录） | 换机/重装不想丢设置和自己的评论记录 | `703403082` + 合并 `6ae3b858b` | 已完成 |
| 安卓端离线缓存路径 + 卸载保留 | 安卓卸载会连缓存一起删，重装要重新下 | `3d75f57e9` / `9a59dc897` | 已完成，API 27 真机验过 |

## 2. 各特性的设计要点

### 2.1 桌面端网页标签页

- **只做桌面**：移动端屏幕宝贵，左栏根本没位置；用 `WebTabsController.supported` 收口（Windows/macOS，Linux 没有 `flutter_inappwebview` 实现所以排除）
- **不保存 Cookie**：每个进程一份内存 profile，所有标签共享，退出即弃。够用又不留痕迹
- **标签页不跨重启恢复**：临时用的，不需要持久化
- 交互：左栏 `＋ 新建标签页`（在导航项下面，带分割线）；点开就是空白页 + 自动聚焦地址栏；`Esc` 论外，关闭靠悬停 ✕ 或中键
- 上限可配（默认 10），开关在「其它设置」
- webview 里的链接**不跳原生页**，后台标签继续放音频

### 2.2 关键词过滤

移植 #3344 时原 PR 有几个硬伤，一并修了：

- 分区/评论两处的 `regexKey` 都错接到 recommend 的键上，四个过滤项会互相覆盖
- 正则模式只写 regex 键，但 `Pref.banWordForX` 只读关键词键 → 重启后过滤静默失效
- 保存时先 `Get.back()` 再校验正则，表达式非法时输入已丢
- 关键词改成 `RegExp.escape` 拼接后，「加入过滤」的写回逻辑会把转义再转义一次

另外我自己加了一条：切到正则模式**不清空**关键词列表（原 PR 会清空，误触就全没了）。

### 2.3 WebDAV 备份

- payload 升到 v2：`{version, app, platform, exportedAt, setting, video, reply}`
- 评论走 **base64(原始 protobuf)**，不走 `toProto3Json`（会丢 unknown fields）
- **导出剔除 `webdavUri/Username/Password/Directory`**：原来密码是明文跟着备份一起传到服务器的
- 恢复流程：先完整校验（结构 + 每条评论能还原成 `ReplyInfo`）→ 落本机快照 → 导入 → 恢复 webdav 配置 → 导入评论
- 备份先 `rename` 成 `.bak` 再写，失败回滚；服务器不支持 MOVE 时退化为直接覆盖
- 错误按类型给中文提示：401/403/404/405/超时/JSON/结构不符
- 连接探测 12s、实际收发 60s；payload 上限 20MB

### 2.4 安卓离线缓存路径

- **`Android/media/<pkg>` 不能实现「卸载保留」**——`getExternalMediaDirs()` 文档明写卸载即删，AOSP `installd.destroyAppData` 会连 `Android/data`、`Android/media`、`Android/obb` 一起清。这条我一开始想错了，被查证推翻
- 所以保留位置只能放共享存储公共目录：`/storage/emulated/0/Download/PiliPlus`
- 权限矩阵：API 24–28 用 `WRITE_EXTERNAL_STORAGE`；API 30+ 用 `MANAGE_EXTERNAL_STORAGE`（跳系统设置授权）；**API 29 无解**，降级私有目录
- 开关「卸载时保留缓存」默认**开**（单人 fork，老用户迁移顾虑可接受）
- 关掉开关 = 严格回到改动前的 `Android/data/<pkg>/files/download`
- 切换不迁移旧缓存，但会明确提示

## 3. 踩过的坑

- **`upstream` 的 push URL 是 `no_push`**：说「推送到上游」时实际推的是 origin
- **合并上游后 pub cache 版本漂移**：`pubspec.lock` 要的版本本机 cache 里没有（`chat_bottom_container`、`file_picker` 等），`flutter pub get` 又因为符号链接权限报 `ERROR_ACCESS_DENIED`。分析/测试能过是因为手动把 cache 里的 git 依赖 checkout 到 lock 的 commit
- **Windows 打包必须给版本常量**：不带 `--dart-define-from-file=pili_release.json` 时 `BuildConfig.buildTime = 0`，`update.dart` 会认为"有新版本"，**每次启动都弹更新提示**
- `flutter clean` 之后 ANGLE.7z 解压和 `CMAKE_INSTALL_PREFIX` 会被重置，要手动修 `build/windows/x64/CMakeCache.txt`
- **`test/` 被 `.gitignore` 的 `test*` 规则忽略**，加测试要 `git add -f`
- 本机**没有 Android SDK / JDK / iscc / fastforge**：APK 只能走 GitHub Actions，安装器只能静态核对
- `webdav_client` 是 git 依赖（`wgh136/webdav_client` fork），不是 pub 上的版本

## 4. 已知问题 / 待办

**真机验证缺失**
- API 30+ 的 `MANAGE_EXTERNAL_STORAGE` 分支没验过（手上只有 API 27 的机器）
- API 29 降级、SAF 选目录、下载中途卸载的半成品文件都没测

**真机暴露的小问题（未修）**
- API 27 上「授权所有文件访问」菜单文案没按版本变（应为「存储权限」），`extra_settings.dart` 里硬编码
- 切换缓存路径后，「离线缓存」里旧路径上的**未完成任务**会残留到重启
- 重装后权限被系统重置，应用静默回退私有目录，「离线缓存」页只显示"没有数据"，缺一句"请重新授权"的引导

**评审留的低危项**
- 开关的 `Switch` 本体被 `IgnorePointer` 包住，读屏聚焦时激活无效（触控整行正常）
- 断点续传入口 `startDownload` 没走新的路径可用性复检
- `_refreshAndroidDownPath` 未整体 try/catch

**认知修正**
- 评论记录在 release 包**不是空的**：发评论成功后 `replyAdd` 会自动写入（受「记录评论」开关控制，默认开）。debug 菜单里那个「保存到本地」只是额外手段

## 5. 构建 / 发版备忘

**Windows**
```powershell
cd C:\PiliPlus-Ze514
# 1) 生成版本常量（等价于 lib/scripts/build.ps1，但不改 pubspec）
#    pili.name=2.1.6, pili.code=<git rev-list --count HEAD>, pili.hash=<sha>, pili.time=<unix>
# 2) 构建
C:\flutter\bin\flutter.bat build windows --release --dart-define-from-file=pili_release.json
# 3) 同步到自用目录 + 打 portable zip（内容是 Release 目录下的文件，不含顶层文件夹）
```
版本号规则 `2.1.6+<commit 数>`；`pili_release.json` 在 `.gitignore` 里。

**Android**
GitHub Actions → **Build** workflow，选分支，只勾 `build_android`，**`tag` 留空**（填了会发正式 Release）。产物在本次 run 的 `Android_arm64-v8a` artifact 里。

## 6. 自建 WebDAV（Debian）

跑在局域网 Debian 12 主机上，用 rclone 的静态二进制，**不装系统包、不需要 root**。

```bash
# 二进制
~/bin/rclone version          # v1.75.2
# 数据目录（应用会在里面建 PiliPlus/）
~/webdav
# 服务
systemctl --user status  webdav.service
systemctl --user restart webdav.service
# 凭据（600 权限，不在仓库里）
~/.config/webdav/env
```

- 端口 `8080`，rclone 的 `serve webdav` + Basic Auth
- systemd **用户**服务，`Restart=on-failure`
- ⚠️ 默认 `Linger=no`：**退出登录后服务会停**。要开机常驻需执行一次 `sudo loginctl enable-linger $USER`
- ⚠️ 这台机器在 Windows 热点的 `192.168.137.0/24` 网段上。手机如果连的是主路由 Wi-Fi（`172.28.x` 网段），**直接连不到**，要么让手机也连热点，要么把 Debian 挪到主 Wi-Fi，或者在 Windows 上做端口转发（需要管理员）

已验证：`PROPFIND / MKCOL / PUT / GET / MOVE / DELETE` 全部正常，其中 **MOVE 可用**是 `.bak` 回滚的前提。

## 7. 上游同步历史

| 日期 | 结果 |
|---|---|
| 2026-10-20 | 合到 `d89112b55` |
| 2026-10-22 | 合到 `8a3cf6cf8` / `63cb75fe4` |
| 2026-10-24 | 合到 `03e1e5380`（含表情包系列） |
| 2026-10-30 | 合 26 个提交到 `ec9e8b93b`，零冲突 |
