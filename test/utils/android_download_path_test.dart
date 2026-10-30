import 'dart:io' show Platform;

import 'package:PiliPlus/utils/android_download_path.dart';
import 'package:flutter_test/flutter_test.dart';

const _root = '/storage/emulated/0';
const _pkgFiles = '/storage/emulated/0/Android/data/com.example.piliplus/files';

void main() {
  group('sharedRootFromExternalStorageDir', () {
    test('从外部私有目录推导共享存储根', () {
      expect(
        AndroidDownloadPath.sharedRootFromExternalStorageDir(_pkgFiles),
        _root,
      );
    });

    test('兼容 Android/media 与 Android/obb', () {
      expect(
        AndroidDownloadPath.sharedRootFromExternalStorageDir(
          '/storage/emulated/0/Android/media/com.example.piliplus',
        ),
        _root,
      );
      expect(
        AndroidDownloadPath.sharedRootFromExternalStorageDir(
          '/storage/emulated/0/Android/obb/com.example.piliplus',
        ),
        _root,
      );
    });

    test('末尾多余分隔符不影响结果', () {
      expect(
        AndroidDownloadPath.sharedRootFromExternalStorageDir('$_pkgFiles/'),
        _root,
      );
    });

    test('非应用专属目录或空值返回 null', () {
      expect(
        AndroidDownloadPath.sharedRootFromExternalStorageDir(null),
        isNull,
      );
      expect(
        AndroidDownloadPath.sharedRootFromExternalStorageDir('  '),
        isNull,
      );
      expect(
        AndroidDownloadPath.sharedRootFromExternalStorageDir(_root),
        isNull,
      );
      expect(
        AndroidDownloadPath.sharedRootFromExternalStorageDir(
          '/data/user/0/com.example.piliplus/files',
        ),
        isNull,
      );
      expect(
        AndroidDownloadPath.sharedRootFromExternalStorageDir(
          'Android/data/x/files',
        ),
        isNull,
      );
    });
  });

  group('keptDownloadPath', () {
    test('默认落到 Download/PiliPlus', () {
      expect(
        AndroidDownloadPath.keptDownloadPath(),
        '/storage/emulated/0/Download/PiliPlus',
      );
      expect(
        AndroidDownloadPath.keptDownloadPath(_root),
        '/storage/emulated/0/Download/PiliPlus',
      );
    });

    test('支持自定义共享存储根，非法根退回默认值', () {
      expect(
        AndroidDownloadPath.keptDownloadPath('/mnt/media/0'),
        '/mnt/media/0/Download/PiliPlus',
      );
      expect(
        AndroidDownloadPath.keptDownloadPath('relative'),
        '/storage/emulated/0/Download/PiliPlus',
      );
    });
  });

  group('legacyDownloadPath', () {
    test('等于改动前的 Android/data/<pkg>/files/download', () {
      expect(
        AndroidDownloadPath.legacyDownloadPath(_pkgFiles),
        '$_pkgFiles/download',
      );
    });

    test('拿不到外部目录时为 null，由调用方回退 defDownloadPath', () {
      expect(AndroidDownloadPath.legacyDownloadPath(null), isNull);
      expect(AndroidDownloadPath.legacyDownloadPath('  '), isNull);
    });
  });

  group('normalizeCustomPath', () {
    test('接受共享存储内的目录', () {
      expect(
        AndroidDownloadPath.normalizeCustomPath(
          '/storage/emulated/0/Download/Movies',
        ),
        '/storage/emulated/0/Download/Movies',
      );
    });

    test('去掉首尾空格并规整 .、.. 与重复分隔符', () {
      expect(
        AndroidDownloadPath.normalizeCustomPath(
          '  /storage/emulated/0/Download//Movies/../Movies  ',
        ),
        '/storage/emulated/0/Download/Movies',
      );
    });

    test('拒绝空值与相对路径', () {
      expect(AndroidDownloadPath.normalizeCustomPath(null), isNull);
      expect(AndroidDownloadPath.normalizeCustomPath('   '), isNull);
      expect(
        AndroidDownloadPath.normalizeCustomPath('Download/PiliPlus'),
        isNull,
      );
    });

    test('拒绝共享存储根本身与共享存储外的路径', () {
      expect(AndroidDownloadPath.normalizeCustomPath(_root), isNull);
      expect(
        AndroidDownloadPath.normalizeCustomPath('/storage/emulated/0/../0'),
        isNull,
      );
      expect(
        AndroidDownloadPath.normalizeCustomPath('/storage/ABCD-1234/PiliPlus'),
        isNull,
      );
      expect(
        AndroidDownloadPath.normalizeCustomPath('/data/local/tmp'),
        isNull,
      );
    });

    test('拒绝 Android/data|media|obb 应用专属目录', () {
      expect(
        AndroidDownloadPath.normalizeCustomPath('$_pkgFiles/download'),
        isNull,
      );
      expect(
        AndroidDownloadPath.normalizeCustomPath(
          '/storage/emulated/0/Android/media/com.example.piliplus/x',
        ),
        isNull,
      );
      expect(
        AndroidDownloadPath.normalizeCustomPath(
          '/storage/emulated/0/Android/obb/com.example.piliplus',
        ),
        isNull,
      );
    });

    test('共享存储内名字不叫 Android 的目录仍然可以选', () {
      expect(
        AndroidDownloadPath.normalizeCustomPath('/storage/emulated/0/data/foo'),
        '/storage/emulated/0/data/foo',
      );
    });

    test('共享存储根可覆写', () {
      expect(
        AndroidDownloadPath.normalizeCustomPath(
          '/mnt/media/0/Foo',
          sharedRoot: '/mnt/media/0',
        ),
        '/mnt/media/0/Foo',
      );
      expect(
        AndroidDownloadPath.normalizeCustomPath(
          '/storage/emulated/0/Foo',
          sharedRoot: '/mnt/media/0',
        ),
        isNull,
      );
    });

    test('推导出的卸载保留目录自身合法', () {
      final kept = AndroidDownloadPath.keptDownloadPath(_root);
      expect(
        AndroidDownloadPath.normalizeCustomPath(kept, sharedRoot: _root),
        kept,
      );
    });
  });

  group('sharedStorageDocumentUri', () {
    test('为主共享存储目录生成 DocumentsUI URI', () {
      expect(
        AndroidDownloadPath.sharedStorageDocumentUri(
          '/storage/emulated/0/Download/PiliPlus',
        ),
        'content://com.android.externalstorage.documents/document/'
        'primary%3ADownload%2FPiliPlus',
      );
    });

    test('私有目录等无法直接打开的位置返回 null', () {
      expect(AndroidDownloadPath.sharedStorageDocumentUri(_pkgFiles), isNull);
      expect(AndroidDownloadPath.sharedStorageDocumentUri(null), isNull);
    });
  });

  group('supportsPublicStorage', () {
    test('API 29 是无解区间，24-28 与 30+ 可用', () {
      expect(AndroidDownloadPath.supportsPublicStorage(24), isTrue);
      expect(AndroidDownloadPath.supportsPublicStorage(28), isTrue);
      expect(AndroidDownloadPath.supportsPublicStorage(29), isFalse);
      expect(AndroidDownloadPath.supportsPublicStorage(30), isTrue);
      expect(AndroidDownloadPath.supportsPublicStorage(37), isTrue);
    });
  });

  group('keepOnUninstallSubtitle', () {
    test('按系统版本给出不同说明', () {
      expect(AndroidDownloadPath.keepOnUninstallSubtitle(28), contains('存储权限'));
      expect(
        AndroidDownloadPath.keepOnUninstallSubtitle(29),
        contains('Android 10'),
      );
      expect(
        AndroidDownloadPath.keepOnUninstallSubtitle(33),
        contains('所有文件访问'),
      );
    });
  });

  group('resolve', () {
    test('关闭开关时固定用现状私有目录，自定义路径暂停生效', () async {
      final resolution = await AndroidDownloadPath.resolve(
        externalStorageDir: _pkgFiles,
        customPath: '/storage/emulated/0/Download/Movies',
        keepOnUninstall: false,
        fallbackPath: '/fallback/download',
        sdkInt: 34,
      );
      expect(resolution.path, '$_pkgFiles/download');
      expect(resolution.source, AndroidDownPathSource.legacy);
      // 用户设置要保留，重新开启开关时继续生效
      expect(resolution.droppedCustomPath, isNull);
      expect(resolution.fallbackReason, isNull);
    });

    test('拿不到外部目录时回退 defDownloadPath', () async {
      final resolution = await AndroidDownloadPath.resolve(
        externalStorageDir: null,
        keepOnUninstall: false,
        fallbackPath: '/data/user/0/com.example.piliplus/files/download',
        sdkInt: 34,
      );
      expect(
        resolution.path,
        '/data/user/0/com.example.piliplus/files/download',
      );
      expect(resolution.sharedRoot, isNull);
    });

    test('API 29 无解，开启开关也回退私有目录并给出原因', () async {
      final resolution = await AndroidDownloadPath.resolve(
        externalStorageDir: _pkgFiles,
        keepOnUninstall: true,
        fallbackPath: '/fallback/download',
        sdkInt: 29,
      );
      expect(resolution.path, '$_pkgFiles/download');
      expect(resolution.source, AndroidDownPathSource.legacy);
      expect(resolution.fallbackReason, contains('不支持'));
    });

    test('开启但未授权共享存储时回退私有目录并给出原因', () async {
      // 非 Android 宿主上权限检查固定为未授权，可稳定验证该回退分支
      if (Platform.isAndroid) return;
      final resolution = await AndroidDownloadPath.resolve(
        externalStorageDir: _pkgFiles,
        keepOnUninstall: true,
        fallbackPath: '/fallback/download',
        sdkInt: 33,
      );
      expect(resolution.path, '$_pkgFiles/download');
      expect(resolution.source, AndroidDownPathSource.legacy);
      expect(resolution.fallbackReason, contains('权限'));
    });

    test('自定义路径不可用但合法时保留设置，只在不能规范化时丢弃', () async {
      // 无权限/不可写都属「本次没生效」，不能删用户设置
      final kept = await AndroidDownloadPath.resolve(
        externalStorageDir: _pkgFiles,
        customPath: '/storage/emulated/0/Download/Movies',
        keepOnUninstall: true,
        fallbackPath: '/fallback/download',
        sdkInt: 34,
      );
      expect(kept.droppedCustomPath, isNull);
      expect(kept.fallbackReason, isNotNull);

      // 规范化失败（不在共享存储内）才算无效设置，交给调用方清理
      final dropped = await AndroidDownloadPath.resolve(
        externalStorageDir: _pkgFiles,
        customPath: '/storage/ABCD-1234/PiliPlus',
        keepOnUninstall: true,
        fallbackPath: '/fallback/download',
        sdkInt: 34,
      );
      expect(dropped.droppedCustomPath, '/storage/ABCD-1234/PiliPlus');
    });
  });

  group('missingPermissionReason', () {
    test('API 24–28 说存储权限，API 29 说系统不支持，API 30+ 说所有文件访问', () {
      expect(AndroidDownloadPath.missingPermissionReason(24), contains('存储权限'));
      expect(AndroidDownloadPath.missingPermissionReason(28), contains('存储权限'));
      expect(
        AndroidDownloadPath.missingPermissionReason(29),
        contains('不支持'),
      );
      expect(
        AndroidDownloadPath.missingPermissionReason(30),
        contains('所有文件访问'),
      );
      expect(
        AndroidDownloadPath.missingPermissionReason(37),
        contains('所有文件访问'),
      );
    });
  });

  group('sharedStorageDocumentUri 卷限制', () {
    test('只有主共享存储才是 primary，其它卷返回 null 走复制路径', () {
      expect(
        AndroidDownloadPath.sharedStorageDocumentUri(
          '/storage/ABCD-1234/PiliPlus',
          sharedRoot: '/storage/ABCD-1234',
        ),
        isNull,
      );
      expect(
        AndroidDownloadPath.sharedStorageDocumentUri(
          '/storage/emulated/0/Download/PiliPlus',
          sharedRoot: '/storage/emulated/0',
        ),
        contains('primary%3ADownload%2FPiliPlus'),
      );
    });
  });
}
