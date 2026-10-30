import 'dart:io' show Platform, Directory;

import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/dialog/simple_dialog_option.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart'
    show RefreshIndicator, displacement, refreshDragExtent;
import 'package:PiliPlus/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart'
    show deviceTouchSlop, touchSlopH;
import 'package:PiliPlus/common/widgets/image_grid/image_grid_view.dart'
    show ImageGridView, ImageModel;
import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/sponsor_block/skip_type.dart';
import 'package:PiliPlus/pages/common/slide/common_slide_page.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/main/web_tabs/controller.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/slider_dialog.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/android_download_path.dart';
import 'package:PiliPlus/utils/desktop/window_controller.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/filtering_text.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/update.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide RefreshIndicator;
import 'package:path_provider/path_provider.dart' show getExternalStorageDirectory;
import 'package:url_launcher/url_launcher.dart' show LaunchMode, launchUrl;

List<SettingsModel> get extraSettings => [
  if (PlatformUtils.isDesktop) ...[
    SwitchModel(
      title: '退出时最小化',
      leading: const Icon(Icons.exit_to_app),
      setKey: SettingBoxKey.minimizeOnExit,
      defaultVal: true,
      onChanged: (value) => WindowController.instance.minimizeOnExit = value,
    ),
    NormalModel(
      title: '缓存路径',
      getSubtitle: () => downloadPath,
      leading: const Icon(Icons.storage),
      onTap: _showDownPathDialog,
    ),
    if (WebTabsController.supported) ...[
      const SwitchModel(
        title: '启用网页标签',
        subtitle: '在左侧栏新建网页标签页，不保存 Cookie，退出后不留痕迹',
        leading: Icon(Icons.tab_outlined),
        setKey: SettingBoxKey.webTabEnable,
        defaultVal: true,
        onChanged: WebTabsController.applyEnabled,
      ),
      NormalModel(
        title: '标签页数量上限',
        getSubtitle: () => '${Pref.webTabMax} 个',
        leading: const Icon(Icons.filter_none),
        onTap: _showWebTabMaxDialog,
      ),
    ],
  ] else if (Platform.isAndroid) ...[
    SwitchModel(
      title: '允许三方APP访问私有存储',
      subtitle: '允许三方APP（例如MT管理器）通过访问外部存储的方式访问私有存储下的文件',
      leading: const Icon(Icons.storage),
      setKey: SettingBoxKey.enableDocProvider,
      defaultVal: Pref.enableDocProvider,
      onChanged: AndroidHelper.updateDocProvider,
    ),
    NormalModel(
      title: '卸载时保留缓存',
      subtitle: AndroidDownloadPath.keepOnUninstallSubtitle(
        DeviceUtils.sdkInt,
      ),
      leading: const Icon(Icons.save_alt),
      getTrailing: (_) =>
          _KeepCacheSwitch(value: Pref.keepDownPathOnUninstall),
      onTap: _toggleKeepCacheOnUninstall,
    ),
    const NormalModel(
      title: '离线缓存路径',
      getSubtitle: _androidDownPathSubtitle,
      leading: Icon(Icons.folder_outlined),
      onTap: _showAndroidDownPathDialog,
    ),
  ],
  SplitModel(
    normalModel: const NormalModel.split(
      title: '空降助手',
      subtitle: '点击配置',
      leading: Icon(CustomIcons.shield_play_arrow),
    ),
    switchModel: SwitchModel.split(
      defaultVal: false,
      setKey: SettingBoxKey.enableSponsorBlock,
      onTap: (context) => Get.toNamed('/sponsorBlock'),
    ),
  ),
  PopupModel<SkipType>(
    title: '番剧片头/片尾跳过类型',
    leading: const Icon(MdiIcons.debugStepOver),
    value: () => Pref.pgcSkipType,
    items: SkipType.values,
    onSelected: (value, setState) => GStorage.setting
        .put(SettingBoxKey.pgcSkipType, value.index)
        .whenComplete(setState),
  ),
  const SwitchModel(
    title: '禁用 SSL 证书验证',
    subtitle: '谨慎开启，禁用容易受到中间人攻击',
    leading: Icon(Icons.security),
    needReboot: true,
    setKey: SettingBoxKey.badCertificateCallback,
  ),
  const SwitchModel(
    title: '使用外部浏览器打开链接',
    leading: Icon(Icons.open_in_browser),
    setKey: SettingBoxKey.openInBrowser,
    defaultVal: false,
  ),
  NormalModel(
    title: '横向滑动阈值',
    getSubtitle: () => '当前:「${Pref.touchSlopH}」，系统默认值: $deviceTouchSlop',
    onTap: _showTouchSlopDialog,
    leading: const Icon(Icons.pan_tool_alt_outlined),
  ),
  NormalModel(
    title: '刷新指示器高度',
    leading: const Icon(Icons.height),
    getSubtitle: () =>
        '当前指示器高度: ${Pref.refreshDisplacement}, 刷新滑动距离: $refreshDragExtent',
    onTap: _showRefreshDialog,
  ),
  const SwitchModel(
    title: '显示热门推荐',
    subtitle: '热门页面显示每周必看等推荐内容入口',
    leading: Icon(Icons.local_fire_department_outlined),
    setKey: SettingBoxKey.showHotRcmd,
    defaultVal: false,
    needReboot: true,
  ),
  const SwitchModel(
    title: '搜索建议',
    leading: Icon(Icons.search),
    setKey: SettingBoxKey.searchSuggestion,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '记录搜索历史',
    leading: Icon(Icons.history),
    setKey: SettingBoxKey.recordSearchHistory,
    defaultVal: true,
  ),
  SwitchModel(
    title: '预览 Live Photo',
    subtitle: '开启则以视频形式预览 Live Photo，否则预览静态图片',
    leading: const Icon(Icons.image_outlined),
    setKey: SettingBoxKey.enableLivePhoto,
    defaultVal: true,
    onChanged: (value) => ImageModel.enableLivePhoto = value,
  ),
  SwitchModel(
    title: '侧滑关闭二级页面',
    leading: const Icon(CustomIcons.touch_app_rotate_270),
    setKey: SettingBoxKey.slideDismissReplyPage,
    defaultVal: Platform.isIOS,
    onChanged: (value) => CommonSlideMixin.slideDismissReplyPage = value,
  ),
  const SwitchModel(
    title: '展示追番时间表',
    leading: Icon(MdiIcons.chartTimelineVariantShimmer),
    setKey: SettingBoxKey.showPgcTimeline,
    defaultVal: true,
    needReboot: true,
  ),
  SwitchModel(
    title: '静默下载图片',
    subtitle: '不显示下载 Loading 弹窗',
    leading: const Icon(Icons.download_for_offline_outlined),
    setKey: SettingBoxKey.silentDownImg,
    defaultVal: false,
    onChanged: (value) => ImageUtils.silentDownImg = value,
  ),
  SwitchModel(
    title: '长按/右键显示图片菜单',
    leading: const Icon(Icons.menu),
    setKey: SettingBoxKey.enableImgMenu,
    defaultVal: false,
    onChanged: (value) => ImageGridView.enableImgMenu = value,
  ),
  SwitchModel(
    setKey: SettingBoxKey.feedBackEnable,
    onChanged: (value) {
      enableFeedback = value;
      feedBack();
    },
    leading: const Icon(Icons.vibration_outlined),
    title: '震动反馈',
    subtitle: '请确定手机设置中已开启震动反馈',
  ),
  const SwitchModel(
    title: '大家都在搜',
    subtitle: '是否展示「大家都在搜」',
    leading: Icon(Icons.data_thresholding_outlined),
    setKey: SettingBoxKey.enableHotKey,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '搜索发现',
    subtitle: '是否展示「搜索发现」',
    leading: Icon(Icons.search_outlined),
    setKey: SettingBoxKey.enableSearchRcmd,
    defaultVal: true,
  ),
  SwitchModel(
    title: '搜索默认词',
    subtitle: '是否展示搜索框默认词',
    leading: const Icon(Icons.whatshot_outlined),
    setKey: SettingBoxKey.enableSearchWord,
    defaultVal: false,
    onChanged: (val) {
      try {
        final controller = Get.find<HomeController>()..enableSearchWord = val;
        if (val) {
          controller.querySearchDefault();
        } else {
          controller.defaultSearch.value = '';
        }
      } catch (_) {}
    },
  ),
  const SwitchModel(
    title: '快速收藏',
    subtitle: '点击设置默认收藏夹\n点按收藏至默认，长按选择文件夹',
    leading: Icon(Icons.bookmark_add_outlined),
    setKey: SettingBoxKey.enableQuickFav,
    onTap: _showFavDialog,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '启用AI总结',
    subtitle: '视频详情页开启AI总结',
    leading: Icon(Icons.engineering_outlined),
    setKey: SettingBoxKey.enableAi,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '消息页禁用"收到的赞"功能',
    subtitle: '禁止打开入口，降低网络社交依赖',
    leading: Icon(Icons.beach_access_outlined),
    setKey: SettingBoxKey.disableLikeMsg,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '启用HTTP/2',
    leading: Icon(Icons.swap_horizontal_circle_outlined),
    setKey: SettingBoxKey.enableHttp2,
    defaultVal: false,
    needReboot: true,
  ),
  const NormalModel(
    title: '连接重试次数',
    subtitle: '为0时禁用',
    leading: Icon(Icons.repeat),
    onTap: _showReplyCountDialog,
  ),
  const NormalModel(
    title: '连接重试间隔',
    subtitle: '实际间隔 = 间隔 * 第x次重试',
    leading: Icon(Icons.more_time_outlined),
    onTap: _showReplyDelayDialog,
  ),
  const SplitModel(
    normalModel: NormalModel.split(
      title: '设置代理',
      subtitle: '设置代理 host:port',
      leading: Icon(Icons.airplane_ticket_outlined),
    ),
    switchModel: SwitchModel.split(
      defaultVal: false,
      setKey: SettingBoxKey.enableSystemProxy,
      onTap: _showProxyDialog,
    ),
  ),
  NormalModel(
    title: '最大缓存大小',
    getSubtitle: () => '当前最大缓存大小: 「${Pref.maxCacheSize.formatSize}」',
    leading: const Icon(Icons.delete_outlined),
    onTap: _showCacheDialog,
  ),
  SwitchModel(
    title: '检查更新',
    subtitle: '每次启动时检查是否需要更新',
    leading: const Icon(Icons.system_update_alt),
    setKey: SettingBoxKey.autoUpdate,
    defaultVal: true,
    onChanged: (val) {
      if (val) {
        Update.checkUpdate(false);
      }
    },
  ),
];

Future<void> _showWebTabMaxDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final result = await showDialog<int>(
    context: context,
    builder: (context) => SelectDialog<int>(
      title: '标签页数量上限',
      value: Pref.webTabMax,
      values: const [
        (5, '5 个'),
        (10, '10 个'),
        (15, '15 个'),
        (20, '20 个'),
        (30, '30 个'),
      ],
    ),
  );
  if (result != null && result != Pref.webTabMax) {
    GStorage.setting.put(SettingBoxKey.webTabMax, result);
    setState();
    SmartDialog.showToast('已设为 $result 个');
  }
}

void _showDownPathDialog(BuildContext context, VoidCallback setState) {
  showDialog(
    context: context,
    builder: (context) => SimpleDialog(
      clipBehavior: Clip.hardEdge,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        DialogOption(
          onPressed: () {
            Get.back();
            PathUtils.openDir(downloadPath);
          },
          child: const Text('打开'),
        ),
        DialogOption(
          onPressed: () {
            Get.back();
            Utils.copyText(downloadPath);
          },
          child: const Text('复制', style: TextStyle(fontSize: 14)),
        ),
        DialogOption(
          onPressed: () {
            Get.back();
            final defPath = defDownloadPath;
            if (downloadPath == defPath) return;
            downloadPath = defPath;
            setState();
            Get.find<DownloadService>().initDownloadList();
            GStorage.setting.delete(SettingBoxKey.downloadPath);
          },
          child: const Text('重置', style: TextStyle(fontSize: 14)),
        ),
        DialogOption(
          onPressed: () async {
            Get.back();
            final path = await FilePicker.getDirectoryPath(
              initialDirectory: Directory(downloadPath).existsSync()
                  ? downloadPath
                  : null,
            );
            if (path == null || path == downloadPath) return;
            downloadPath = path;
            setState();
            Get.find<DownloadService>().initDownloadList();
            GStorage.setting.put(SettingBoxKey.downloadPath, path);
          },
          child: const Text('设置新路径', style: TextStyle(fontSize: 14)),
        ),
      ],
    ),
  );
}

// ------------------------------------------------ 安卓离线缓存路径

/// 设置页副标题：当前实际路径，发生回退或自定义路径暂停时追加说明
String _androidDownPathSubtitle() {
  final reason = AndroidDownloadPath.latest?.fallbackReason;
  if (reason != null) return '$downloadPath（$reason）';
  if (!Pref.keepDownPathOnUninstall && Pref.androidDownloadPath != null) {
    return '$downloadPath（已关闭卸载保留，自定义路径暂停生效）';
  }
  return downloadPath;
}

/// 切换缓存路径/开关前统一提示：旧缓存位置不变，列表只显示新路径
const _cachePathNotice = '已缓存的内容不会自动迁移，仍保留在原路径；切换后下载列表只显示新路径下的缓存。';

bool _isDownloading() {
  if (!Get.isRegistered<DownloadService>()) return false;
  // 只看正在下载的那条；暂停/排队不应阻止切换，否则会出现无法切换的死循环
  return Get.find<DownloadService>().curDownload.value?.status.isDownloading ==
      true;
}

/// 让整张设置列表重建：开关行与路径行必须同步刷新，
/// 只刷新当前行会出现「开关变了、路径还是旧的」的错觉
void _rebuildSettingList(BuildContext context) {
  if (context is Element) {
    context.visitAncestorElements((element) {
      element.markNeedsBuild();
      return true;
    });
  }
}

/// 路径变更后的统一收口：重新初始化下载列表 → 等读完 → 通知各页面刷新
Future<void> _refreshDownloadList() async {
  if (!Get.isRegistered<DownloadService>()) return;
  try {
    final service = Get.find<DownloadService>()..initDownloadList();
    await service.waitForInitialization;
    service.flagNotifier.refresh();
  } catch (e) {
    // 列表刷新失败不影响已经生效的路径
    SmartDialog.showToast('下载列表刷新失败：${e.runtimeType}');
  }
}

/// 按当前设置重新解析缓存目录，并刷新下载列表
Future<AndroidDownPathResolution?> _refreshAndroidDownPath() async {
  final resolution = await AndroidDownloadPath.resolve(
    externalStorageDir: (await getExternalStorageDirectory())?.path,
    customPath: Pref.androidDownloadPath,
    keepOnUninstall: Pref.keepDownPathOnUninstall,
    fallbackPath: defDownloadPath,
    sdkInt: DeviceUtils.sdkInt,
  );
  AndroidDownloadPath.latest = resolution;
  downloadPath = resolution.path;
  if (resolution.droppedCustomPath != null) {
    // 只有规范化失败才清理设置，且清理失败不影响已解析路径
    try {
      await GStorage.setting.delete(SettingBoxKey.androidDownloadPath);
    } catch (_) {
      // 清理失败忽略
    }
  }
  await _refreshDownloadList();
  return resolution;
}

/// 应用「卸载时保留缓存」：重新解析路径并刷新下载列表
Future<void> _applyKeepCacheOnUninstall(bool value) async {
  String? warning;
  if (value) {
    final granted = await AndroidDownloadPath.requestPublicStorageAccess(
      sdkInt: DeviceUtils.sdkInt,
    );
    if (!granted) {
      warning = AndroidDownloadPath.missingPermissionReason(
        DeviceUtils.sdkInt,
      );
    }
  }
  await _refreshAndroidDownPath();
  SmartDialog.showToast(warning ?? '缓存路径：$downloadPath');
}

/// 点击开关行：先确认，再落盘并应用
Future<void> _toggleKeepCacheOnUninstall(
  BuildContext context,
  VoidCallback setState,
) async {
  if (_isDownloading()) {
    SmartDialog.showToast('有任务正在下载，请暂停后再切换');
    return;
  }
  final target = !Pref.keepDownPathOnUninstall;
  final confirmed = await showConfirmDialog(
    context: context,
    title: Text(target ? '开启「卸载时保留缓存」？' : '关闭「卸载时保留缓存」？'),
    content: const Text(_cachePathNotice),
  );
  if (!confirmed || !context.mounted) return;
  await GStorage.setting.put(SettingBoxKey.keepDownPathOnUninstall, target);
  await _applyKeepCacheOnUninstall(target);
  if (!context.mounted) return;
  // 整张列表重建：开关行与路径行都要跟着刷新
  setState();
  _rebuildSettingList(context);
}

/// 「卸载时保留缓存」开关的外观；点击由所在行统一处理
class _KeepCacheSwitch extends StatelessWidget {
  const _KeepCacheSwitch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Switch(value: value, onChanged: (_) {}),
    );
  }
}

void _showAndroidDownPathDialog(BuildContext context, VoidCallback setState) {
  final latest = AndroidDownloadPath.latest;
  // 当前没落在共享存储上（没权限/回退）时始终给出授权入口，
  // 不依赖开关状态，避免「无权限时对话框里拿不到授权」
  final canGrant =
      AndroidDownloadPath.supportsPublicStorage(DeviceUtils.sdkInt) &&
      latest?.isKept != true &&
      latest?.isCustom != true;
  showDialog(
    context: context,
    // 不复用 builder 的 context：对话框关闭后回调还需要页面 context
    builder: (_) => SimpleDialog(
      clipBehavior: Clip.hardEdge,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        if (latest?.fallbackReason case final reason?)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              reason,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        DialogOption(
          onPressed: () {
            Get.back();
            _openAndroidDownPath(downloadPath);
          },
          child: const Text('打开'),
        ),
        DialogOption(
          onPressed: () {
            Get.back();
            Utils.copyText(downloadPath);
          },
          child: const Text('复制', style: TextStyle(fontSize: 14)),
        ),
        DialogOption(
          onPressed: () {
            Get.back();
            _resetAndroidDownPath(context, setState);
          },
          child: const Text('重置', style: TextStyle(fontSize: 14)),
        ),
        DialogOption(
          onPressed: () {
            Get.back();
            _setAndroidDownPath(context, setState);
          },
          child: const Text('设置新路径', style: TextStyle(fontSize: 14)),
        ),
        DialogOption(
          onPressed: () {
            Get.back();
            _pickAndroidDownPath(context, setState);
          },
          child: const Text('选择目录', style: TextStyle(fontSize: 14)),
        ),
        if (canGrant)
          DialogOption(
            onPressed: () {
              Get.back();
              _grantAndroidDownPath(context, setState);
            },
            child: const Text('授权所有文件访问', style: TextStyle(fontSize: 14)),
          ),
      ],
    ),
  );
}

/// 安卓端打开目录：共享存储目录交给系统文件管理器，
/// 私有目录等无法直接打开时退化为复制路径
Future<void> _openAndroidDownPath(String dirPath) async {
  final uri = AndroidDownloadPath.sharedStorageDocumentUri(dirPath);
  var opened = false;
  if (uri != null) {
    try {
      opened = await launchUrl(
        Uri.parse(uri),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // 系统没有能处理该 URI 的文件管理器时退化为复制路径
      opened = false;
    }
  }
  if (opened) return;
  await Utils.copyText(dirPath, toastText: '已复制路径，请在文件管理器中打开');
}

Future<void> _grantAndroidDownPath(
  BuildContext context,
  VoidCallback setState,
) async {
  final sdkInt = DeviceUtils.sdkInt;
  final permissionName = sdkInt < 29 ? '存储权限' : '所有文件访问';
  final confirmed = await showConfirmDialog(
    context: context,
    title: Text('授予「$permissionName」？'),
    content: const Text(_cachePathNotice),
  );
  if (!confirmed || !context.mounted) return;
  final granted = await AndroidDownloadPath.requestPublicStorageAccess(
    sdkInt: sdkInt,
  );
  if (!context.mounted) return;
  if (!granted) {
    SmartDialog.showToast(
      '未获得「$permissionName」权限，缓存仍写入应用私有目录；'
      '可在系统设置中开启后重试',
    );
    return;
  }
  await _refreshAndroidDownPath();
  if (!context.mounted) return;
  setState();
  _rebuildSettingList(context);
  SmartDialog.showToast('缓存路径：$downloadPath');
}

Future<void> _resetAndroidDownPath(
  BuildContext context,
  VoidCallback setState,
) async {
  if (_isDownloading()) {
    SmartDialog.showToast('有任务正在下载，请暂停后再切换缓存路径');
    return;
  }
  if (Pref.androidDownloadPath == null) {
    SmartDialog.showToast('已是默认路径：$downloadPath');
    return;
  }
  final confirmed = await showConfirmDialog(
    context: context,
    title: const Text('恢复默认缓存路径？'),
    content: const Text(_cachePathNotice),
  );
  if (!confirmed || !context.mounted) return;
  try {
    await GStorage.setting.delete(SettingBoxKey.androidDownloadPath);
  } catch (_) {
    SmartDialog.showToast('恢复默认路径失败，已保留当前设置');
    return;
  }
  await _refreshAndroidDownPath();
  if (!context.mounted) return;
  setState();
  _rebuildSettingList(context);
  SmartDialog.showToast('缓存路径：$downloadPath');
}

Future<void> _setAndroidDownPath(
  BuildContext context,
  VoidCallback setState,
) async {
  if (_isDownloading()) {
    SmartDialog.showToast('有任务正在下载，请暂停后再切换缓存路径');
    return;
  }
  final sharedRoot = AndroidDownloadPath.sharedRootFromExternalStorageDir(
    (await getExternalStorageDirectory())?.path,
  );
  if (!context.mounted) return;
  var input = downloadPath;
  final raw = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      clipBehavior: Clip.hardEdge,
      title: const Text('设置缓存路径'),
      content: TextFormField(
        initialValue: input,
        autofocus: true,
        onChanged: (value) => input = value,
        decoration: InputDecoration(
          hintText: AndroidDownloadPath.keptDownloadPath(sharedRoot),
        ),
      ),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('取消')),
        TextButton(
          onPressed: () => Get.back<String>(result: input),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  if (raw == null || !context.mounted) return;
  await _applyAndroidCustomPath(context, setState, raw);
}

/// 通过系统目录选择器设置路径；SAF 无法映射成文件路径时提示手输
Future<void> _pickAndroidDownPath(
  BuildContext context,
  VoidCallback setState,
) async {
  if (_isDownloading()) {
    SmartDialog.showToast('有任务正在下载，请暂停后再切换缓存路径');
    return;
  }
  final current = Directory(downloadPath);
  final picked = await FilePicker.getDirectoryPath(
    dialogTitle: '选择缓存目录',
    initialDirectory: current.existsSync() ? downloadPath : null,
  );
  if (!context.mounted) return;
  if (picked == null) {
    // 用户取消，或 SAF 返回的目录无法映射为可直写的文件路径
    return;
  }
  await _applyAndroidCustomPath(context, setState, picked);
}

/// 校验并应用自定义缓存路径：不可写/无权限时保持原路径并明确提示
Future<void> _applyAndroidCustomPath(
  BuildContext context,
  VoidCallback setState,
  String rawPath,
) async {
  final sdkInt = DeviceUtils.sdkInt;
  final sharedRoot = AndroidDownloadPath.sharedRootFromExternalStorageDir(
    (await getExternalStorageDirectory())?.path,
  );
  final target = AndroidDownloadPath.normalizeCustomPath(
    rawPath,
    sharedRoot: sharedRoot,
  );
  if (target == null) {
    SmartDialog.showToast(
      '路径无效：必须位于共享存储内，例如 '
      '${AndroidDownloadPath.keptDownloadPath(sharedRoot)}',
    );
    return;
  }
  if (!AndroidDownloadPath.supportsPublicStorage(sdkInt)) {
    SmartDialog.showToast('当前系统不支持直写共享存储，仍使用：$downloadPath');
    return;
  }
  // 先看权限：没权限时不能判定路径本身不可用，先申请一次再说
  if (!await AndroidDownloadPath.hasPublicStorageAccess(sdkInt: sdkInt)) {
    final granted = await AndroidDownloadPath.requestPublicStorageAccess(
      sdkInt: sdkInt,
    );
    if (!context.mounted) return;
    if (!granted) {
      SmartDialog.showToast(
        '未获得${sdkInt < 29 ? '存储权限' : '「所有文件访问」权限'}，'
        '无法写入该目录；请到系统设置授予后重试，仍使用：$downloadPath',
      );
      return;
    }
  }
  if (!await AndroidDownloadPath.isWritable(target)) {
    SmartDialog.showToast('路径不可写，仍使用当前路径：$downloadPath');
    return;
  }
  if (target == downloadPath && Pref.keepDownPathOnUninstall) return;
  if (!context.mounted) return;
  final confirmed = await showConfirmDialog(
    context: context,
    title: Text('切换到 $target ？'),
    content: const Text(_cachePathNotice),
  );
  if (!confirmed || !context.mounted) return;
  // 自定义路径只在开启「卸载时保留缓存」时生效，这里顺带打开开关
  final needEnableSwitch = !Pref.keepDownPathOnUninstall;
  final previousPath = Pref.androidDownloadPath;
  final previousKeep = Pref.keepDownPathOnUninstall;
  try {
    if (needEnableSwitch) {
      await GStorage.setting.put(SettingBoxKey.keepDownPathOnUninstall, true);
    }
    await GStorage.setting.put(SettingBoxKey.androidDownloadPath, target);
    await _refreshAndroidDownPath();
  } catch (_) {
    // 半应用状态回滚：设置写失败或解析失败都恢复原设置
    try {
      if (previousPath == null) {
        await GStorage.setting.delete(SettingBoxKey.androidDownloadPath);
      } else {
        await GStorage.setting.put(SettingBoxKey.androidDownloadPath, previousPath);
      }
      await GStorage.setting.put(
        SettingBoxKey.keepDownPathOnUninstall,
        previousKeep,
      );
    } catch (_) {
      // 回滚失败也要给出可读提示
    }
    if (context.mounted) {
      SmartDialog.showToast('切换缓存路径失败，已保留原路径：$downloadPath');
    }
    return;
  }
  if (!context.mounted) return;
  setState();
  _rebuildSettingList(context);
  SmartDialog.showToast(
    '缓存路径：$downloadPath'
    '${needEnableSwitch ? '（已开启「卸载时保留缓存」）' : ''}',
  );
}

void _showTouchSlopDialog(BuildContext context, VoidCallback setState) {
  String initialValue = Pref.touchSlopH.toString();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('横向滑动阈值'),
      content: TextFormField(
        autofocus: true,
        initialValue: initialValue,
        keyboardType: const .numberWithOptions(decimal: true),
        onChanged: (value) => initialValue = value,
        inputFormatters: FilteringText.decimal,
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () async {
            try {
              final val = double.parse(initialValue);
              Get.back();
              touchSlopH = val;
              await GStorage.setting.put(SettingBoxKey.touchSlopH, val);
              setState();
            } catch (e) {
              SmartDialog.showToast(e.toString());
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

Future<void> _showRefreshDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      title: const Text('刷新指示器高度'),
      min: 10.0,
      max: 100.0,
      divisions: 9,
      value: Pref.refreshDisplacement,
    ),
  );
  if (res != null) {
    displacement = res;
    await GStorage.setting.put(SettingBoxKey.refreshDisplacement, res);
    if (WidgetsBinding.instance.rootElement case final context?) {
      context.visitChildElements(_visitor);
    }
    setState();
  }
}

void _visitor(Element context) {
  if (!context.mounted) return;
  if (context.widget is RefreshIndicator) {
    context.markNeedsBuild();
  } else {
    context.visitChildren(_visitor);
  }
}

Future<void> _showFavDialog(BuildContext context) async {
  if (Accounts.main.isLogin) {
    final res = await FavHttp.allFavFolders(Accounts.main.mid);
    if (res case Success(:final response)) {
      final list = response.list;
      if (list == null || list.isEmpty) {
        return;
      }
      final quickFavId = Pref.quickFavId;
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          clipBehavior: Clip.hardEdge,
          title: const Text('选择默认收藏夹'),
          contentPadding: const EdgeInsets.only(top: 5, bottom: 18),
          content: SingleChildScrollView(
            child: RadioGroup(
              onChanged: (value) {
                Get.back();
                GStorage.setting.put(SettingBoxKey.quickFavId, value);
                SmartDialog.showToast('设置成功');
              },
              groupValue: quickFavId,
              child: Column(
                children: list
                    .map(
                      (item) => RadioListTile(
                        toggleable: true,
                        dense: true,
                        title: Text(item.title),
                        value: item.id,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      );
    } else {
      res.toast();
    }
  }
}

Future<void> _showReplyCountDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      title: const Text('连接重试次数'),
      min: 0,
      max: 8,
      divisions: 8,
      precise: 0,
      value: Pref.retryCount.toDouble(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.retryCount, res.toInt());
    setState();
    SmartDialog.showToast('重启生效');
  }
}

Future<void> _showReplyDelayDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      title: const Text('连接重试间隔'),
      min: 0,
      max: 1000,
      divisions: 10,
      precise: 0,
      value: Pref.retryDelay.toDouble(),
      suffix: 'ms',
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.retryDelay, res.toInt());
    setState();
    SmartDialog.showToast('重启生效');
  }
}

void _showProxyDialog(BuildContext context) {
  String systemProxyHost = Pref.systemProxyHost;
  String systemProxyPort = Pref.systemProxyPort;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('设置代理'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          TextFormField(
            initialValue: systemProxyHost,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '请输入Host，使用 . 分割',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(6)),
              ),
            ),
            onChanged: (e) => systemProxyHost = e,
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: systemProxyPort,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '请输入Port',
              border: OutlineInputBorder(borderRadius: .all(.circular(6))),
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (e) => systemProxyPort = e,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () {
            Get.back();
            GStorage.setting.put(
              SettingBoxKey.systemProxyHost,
              systemProxyHost,
            );
            GStorage.setting.put(
              SettingBoxKey.systemProxyPort,
              systemProxyPort,
            );
          },
          child: const Text('确认'),
        ),
      ],
    ),
  );
}

void _showCacheDialog(BuildContext context, VoidCallback setState) {
  String valueStr = '';
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('最大缓存大小'),
      content: TextField(
        maxLength: 6,
        autofocus: true,
        onChanged: (value) => valueStr = value,
        keyboardType: TextInputType.number,
        inputFormatters: FilteringText.decimal,
        decoration: const InputDecoration(suffixText: 'MB'),
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () async {
            try {
              final val = num.parse(valueStr);
              Get.back();
              await GStorage.setting.put(
                SettingBoxKey.maxCacheSize,
                val * 1024 * 1024,
              );
              setState();
            } catch (e) {
              SmartDialog.showToast(e.toString());
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
