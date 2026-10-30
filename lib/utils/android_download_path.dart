import 'dart:io' show Directory, File, Platform;

import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/permission_handler.dart';
import 'package:path/path.dart' as p;

/// 安卓离线缓存目录的来源，优先级由高到低。
enum AndroidDownPathSource {
  /// 用户自定义路径（必须位于共享存储内）。
  custom,

  /// 开启「卸载时保留缓存」后推导出的共享目录。
  kept,

  /// 改动前的现状：应用外部私有目录，卸载即删。
  legacy,
}

/// [AndroidDownloadPath.resolve] 的解析结果。
class AndroidDownPathResolution {
  const AndroidDownPathResolution({
    required this.path,
    required this.source,
    required this.legacyPath,
    this.sharedRoot,
    this.droppedCustomPath,
    this.fallbackReason,
  });

  /// 最终生效的缓存目录。
  final String path;

  /// 生效路径的来源。
  final AndroidDownPathSource source;

  /// 关闭开关时的现状私有目录，用于「重置」与各级回退。
  final String legacyPath;

  /// 共享存储根，如 `/storage/emulated/0`；无法推导时为 null。
  final String? sharedRoot;

  /// 校验失败而被丢弃的自定义路径，调用方据此清理设置。
  final String? droppedCustomPath;

  /// 回退原因（例如自定义路径不可写），没有回退时为 null。
  final String? fallbackReason;

  bool get isCustom => source == AndroidDownPathSource.custom;

  bool get isKept => source == AndroidDownPathSource.kept;
}

/// 安卓离线缓存路径的推导与校验。
///
/// 卸载时系统会删除 `Android/data`、`Android/media`、`Android/obb` 下
/// 的应用专属目录（`getExternalMediaDirs` 文档与 AOSP `destroyAppData`
/// 均如此），因此「卸载保留」只能落在共享存储的公共目录
/// （默认 `Download/PiliPlus`），并且系统版本决定能否直写：
/// - API 24–28：`WRITE_EXTERNAL_STORAGE` 即可直写（清单 maxSdkVersion=28）；
/// - API 29：scoped storage 生效且系统没有「所有文件访问」开关，无解，回退私有目录；
/// - API 30+：需要 `MANAGE_EXTERNAL_STORAGE`（所有文件访问）授权。
///
/// 带 `posix` 前缀的路径运算保证在任意宿主（含 Windows 上跑单测）都按
/// 安卓的 POSIX 语义解析。
abstract final class AndroidDownloadPath {
  /// 共享存储下给本应用使用的目录名。
  static const appDirName = 'PiliPlus';

  /// 主共享存储根，推导失败时的兜底值。
  static const defaultSharedRoot = '/storage/emulated/0';

  /// 最近一次解析结果，供设置页展示「已回退」等原因。
  static AndroidDownPathResolution? latest;

  static const _probeFileName = '.piliplus_write_probe';
  static const _privateHosts = {'data', 'media', 'obb'};

  // ---------------------------------------------------------------- 纯函数

  /// 从 [getExternalStorageDirectory] 的返回值（形如
  /// `/storage/emulated/0/Android/data/<applicationId>/files`）推导共享存储根。
  static String? sharedRootFromExternalStorageDir(String? externalStorageDir) {
    final raw = externalStorageDir?.trim();
    if (raw == null || raw.isEmpty) return null;
    final normalized = p.posix.normalize(raw);
    if (!p.posix.isAbsolute(normalized)) return null;
    final segments = p.posix.split(normalized);
    final index = segments.indexOf('Android');
    if (index <= 0 || index + 1 >= segments.length) return null;
    if (!_privateHosts.contains(segments[index + 1])) return null;
    final root = p.posix.joinAll(segments.sublist(0, index));
    return p.posix.isAbsolute(root) ? root : null;
  }

  /// 开启「卸载时保留缓存」后的默认目录：`<sharedRoot>/Download/PiliPlus`。
  static String keptDownloadPath([String? sharedRoot]) =>
      p.posix.join(_sharedRootOr(sharedRoot), 'Download', appDirName);

  /// 现状目录：`<externalFilesDir>/download`，卸载即删。
  static String? legacyDownloadPath(String? externalStorageDir) {
    final raw = externalStorageDir?.trim();
    if (raw == null || raw.isEmpty) return null;
    return p.posix.join(raw, PathUtils.downloadDir);
  }

  /// 规整并校验自定义路径；不可用时返回 null。
  ///
  /// 规则：必须是绝对路径、必须位于共享存储内，且不能落在
  /// `Android/data|media|obb` 这类应用专属或受保护目录里。
  static String? normalizeCustomPath(String? customPath, {String? sharedRoot}) {
    final raw = customPath?.trim();
    if (raw == null || raw.isEmpty) return null;
    final normalized = p.posix.normalize(raw);
    if (!p.posix.isAbsolute(normalized)) return null;
    final root = _sharedRootOr(sharedRoot);
    if (normalized == root) return null;
    final relative = p.posix.relative(normalized, from: root);
    if (relative.isEmpty || relative == '.' || relative.startsWith('..')) {
      return null;
    }
    // Android/data|media|obb 属于应用专属或受保护目录，即使授权也不该放缓存
    if (p.posix.split(relative).first == 'Android') return null;
    return normalized;
  }

  /// 生成交给系统文件管理器打开共享存储目录的 DocumentsUI URI。
  ///
  /// DocumentsUI 的 `primary` 卷只对应主共享存储（`/storage/emulated/0`），
  /// 因此其它卷一律返回 null，由调用方退化为复制路径。
  static String? sharedStorageDocumentUri(
    String? dirPath, {
    String? sharedRoot,
  }) {
    final root = _sharedRootOr(sharedRoot);
    if (root != defaultSharedRoot) return null;
    final normalized = normalizeCustomPath(dirPath, sharedRoot: root);
    if (normalized == null) return null;
    final relative = p.posix.relative(normalized, from: root);
    final documentId = Uri.encodeComponent('primary:$relative');
    return 'content://com.android.externalstorage.documents/document/'
        '$documentId';
  }

  /// 系统版本是否有可能直写共享存储（API 29 是无解区间）。
  static bool supportsPublicStorage(int sdkInt) => sdkInt < 29 || sdkInt >= 30;

  /// 拿不到公共目录写权限时的可读原因；API 29 说明系统限制。
  static String missingPermissionReason(int sdkInt) {
    if (!supportsPublicStorage(sdkInt)) {
      return '当前系统不支持卸载保留缓存，已回退';
    }
    // API 24–28 是运行时存储权限，API 30+ 才是「所有文件访问」
    return sdkInt < 29 ? '未获得存储权限，已回退' : '未获得「所有文件访问」权限，已回退';
  }

  /// 「卸载时保留缓存」开关的说明文案。
  static String keepOnUninstallSubtitle(int sdkInt) {
    if (sdkInt < 29) {
      return '开启后缓存写入 Download/$appDirName，卸载重装后仍可找回；需授予存储权限';
    }
    if (sdkInt < 30) {
      return 'Android 10 的系统限制无法直写公共目录，开启后仍会写入私有目录';
    }
    return '开启后缓存写入 Download/$appDirName，卸载重装后仍可找回；需授予「所有文件访问」权限';
  }

  static String _sharedRootOr(String? sharedRoot) {
    final raw = sharedRoot?.trim();
    if (raw == null || raw.isEmpty) return defaultSharedRoot;
    final normalized = p.posix.normalize(raw);
    return p.posix.isAbsolute(normalized) ? normalized : defaultSharedRoot;
  }

  // -------------------------------------------------------------------- IO

  /// 创建目录并写入探针文件，确认真实可写。
  ///
  /// 探针无论成功与否都会在 finally 中删除（删除失败忽略）；失败时再尝试
  /// 清理一次，并回收本次新建的空目录，尽量不在用户目录里留下垃圾。
  static Future<bool> isWritable(String dirPath) async {
    var createdDir = false;
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
        createdDir = true;
      }
      final probe = File(p.posix.join(dir.path, _probeFileName));
      try {
        await probe.writeAsString('piliplus', flush: true);
      } finally {
        try {
          await probe.delete();
        } catch (_) {
          // 删除探针失败不影响可写结论
        }
      }
      return true;
    } catch (_) {
      await _tryCleanProbe(dirPath);
      if (createdDir) {
        try {
          await Directory(dirPath).delete();
        } catch (_) {
          // 目录可能已被其它写入使用，清理失败忽略
        }
      }
      return false;
    }
  }

  static Future<void> _tryCleanProbe(String dirPath) async {
    try {
      final probe = File(p.posix.join(dirPath, _probeFileName));
      if (probe.existsSync()) {
        await probe.delete();
      }
    } catch (_) {
      // 清理失败忽略，不能因此判定为可写或抛给调用方
    }
  }

  /// 当前是否已获得直写共享存储的权限（只检查，不弹窗）。
  ///
  /// 插件通道异常时按「未授权」处理，由上层回退私有目录，不会往上抛。
  static Future<bool> hasPublicStorageAccess({required int sdkInt}) async {
    if (!Platform.isAndroid) return false;
    if (!supportsPublicStorage(sdkInt)) return false;
    try {
      if (sdkInt < 29) {
        // API 24–28：沿用清单里 maxSdkVersion=28 的 WRITE_EXTERNAL_STORAGE
        return await Permission.storage.isGranted;
      }
      return await Permission.manageExternalStorage.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// 申请直写共享存储的权限（API 30+ 会跳到「所有文件访问」系统页面）。
  ///
  /// 返回是否已获得授权；系统不支持或插件异常时返回 false，由调用方降级。
  static Future<bool> requestPublicStorageAccess({required int sdkInt}) async {
    if (!Platform.isAndroid) return false;
    if (!supportsPublicStorage(sdkInt)) return false;
    final permission = sdkInt < 29
        ? Permission.storage
        : Permission.manageExternalStorage;
    try {
      if (await permission.isGranted) return true;
      final status = await permission.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// 解析缓存目录：开关关闭时固定用现状私有目录；开启时按
  /// 「自定义路径 > 开关推导位置 > 现状私有目录」逐级回退。
  ///
  /// 每一级都先校验再使用：自定义路径不合法或不可写、开关推导位置拿不到
  /// 权限或不可写，都会逐级回退，最终落到 [legacyPath]，不会抛出异常。
  ///
  /// [AndroidDownPathResolution.droppedCustomPath] 只在自定义路径规范化失败
  /// （相对路径、不在共享存储内）时返回，调用方据此清理设置；仅仅是不可写
  /// 或没权限时保留用户设置，只通过 [AndroidDownPathResolution.fallbackReason]
  /// 说明当次为何没生效。
  static Future<AndroidDownPathResolution> resolve({
    required String fallbackPath,
    String? externalStorageDir,
    String? customPath,
    bool keepOnUninstall = true,
    required int sdkInt,
  }) async {
    final sharedRoot = sharedRootFromExternalStorageDir(externalStorageDir);
    final legacyPath = legacyDownloadPath(externalStorageDir) ?? fallbackPath;
    String? droppedCustomPath;
    String? fallbackReason;

    // 开关关闭：明确回到「卸载即删」的私有目录，自定义路径暂停生效
    if (!keepOnUninstall) {
      return AndroidDownPathResolution(
        path: legacyPath,
        source: AndroidDownPathSource.legacy,
        legacyPath: legacyPath,
        sharedRoot: sharedRoot,
      );
    }

    // 1. 自定义路径优先
    if (customPath != null && customPath.trim().isNotEmpty) {
      final custom = normalizeCustomPath(customPath, sharedRoot: sharedRoot);
      if (custom == null) {
        // 只有规范化失败（相对路径/不在共享存储内）才算无效设置，
        // 由调用方清理；不可写或没权限只记录原因，保留用户设置
        droppedCustomPath = customPath;
        fallbackReason = '自定义缓存路径不在共享存储内，已回退';
      } else if (!await hasPublicStorageAccess(sdkInt: sdkInt)) {
        fallbackReason = missingPermissionReason(sdkInt);
      } else if (await isWritable(custom)) {
        return AndroidDownPathResolution(
          path: custom,
          source: AndroidDownPathSource.custom,
          legacyPath: legacyPath,
          sharedRoot: sharedRoot,
        );
      } else {
        fallbackReason = '自定义缓存路径不可写，已回退';
      }
    }

    // 2. 开关推导出的卸载保留位置
    final accessible =
        supportsPublicStorage(sdkInt) &&
        await hasPublicStorageAccess(sdkInt: sdkInt);
    if (!accessible) {
      fallbackReason ??= missingPermissionReason(sdkInt);
    } else {
      final keptPath = keptDownloadPath(sharedRoot);
      if (await isWritable(keptPath)) {
        return AndroidDownPathResolution(
          path: keptPath,
          source: AndroidDownPathSource.kept,
          legacyPath: legacyPath,
          sharedRoot: sharedRoot,
          droppedCustomPath: droppedCustomPath,
          fallbackReason: fallbackReason,
        );
      }
      fallbackReason ??= '卸载保留目录不可写，已回退';
    }

    // 3. 现状私有目录
    return AndroidDownPathResolution(
      path: legacyPath,
      source: AndroidDownPathSource.legacy,
      legacyPath: legacyPath,
      sharedRoot: sharedRoot,
      droppedCustomPath: droppedCustomPath,
      fallbackReason: fallbackReason,
    );
  }
}
