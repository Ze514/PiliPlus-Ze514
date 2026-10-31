import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/widgets/pair.dart';
import 'package:PiliPlus/pages/webdav/backup_payload.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart' show DioException, DioExceptionType;
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as path;
import 'package:webdav_client/webdav_client.dart' as webdav;

typedef _WebDavConfig = ({
  String uri,
  String username,
  String password,
  String directory,
});

/// WebDAV 操作类型，UI 据此禁用按钮并展示进行状态
enum WebDavTask { backup, restore }

class WebDav {
  _WebDavConfig? _clientConfig;
  webdav.Client? _client;

  /// 当前进行中的操作，null 表示空闲
  final ValueNotifier<WebDavTask?> task = ValueNotifier<WebDavTask?>(null);

  WebDav._internal();
  static final WebDav _instance = WebDav._internal();
  factory WebDav() => _instance;

  /// 备份格式版本；1 为旧的 {setting, video} 平铺结构，无版本号
  static const int formatVersion = webDavBackupVersion;

  /// 备份文件体积上限
  static const int _maxPayloadBytes = 20 * 1024 * 1024;

  /// 连接探测超时
  static const int _probeTimeoutMs = 12 * 1000;

  /// 实际收发超时，慢盘或大文件不误判失败
  static const int _transferTimeoutMs = 60 * 1000;

  _WebDavConfig _getConfig() {
    String directory = Pref.webdavDirectory;
    if (!directory.endsWith('/')) {
      directory += '/';
    }
    return (
      uri: Pref.webdavUri,
      username: Pref.webdavUsername,
      password: Pref.webdavPassword,
      directory: '$directory${Constants.appName}',
    );
  }

  webdav.Client _newClient(_WebDavConfig config, int timeoutMs) {
    return webdav.newClient(
        config.uri,
        user: config.username,
        password: config.password,
      )
      ..setHeaders({'accept-charset': 'utf-8'})
      ..setConnectTimeout(timeoutMs)
      ..setReceiveTimeout(timeoutMs)
      ..setSendTimeout(timeoutMs);
  }

  Future<webdav.Client> _connect(
    _WebDavConfig config, {
    bool force = false,
  }) async {
    final cachedClient = _client;
    if (!force && cachedClient != null && _clientConfig == config) {
      return cachedClient;
    }

    final client = _newClient(config, _probeTimeoutMs);

    await client.mkdirAll(config.directory);
    _clientConfig = config;
    _client = client;
    return client;
  }

  /// 探测连通性，再单独建一个宽松超时的客户端用于收发
  Future<webdav.Client> _openTransferClient(_WebDavConfig config) async {
    await _connect(config);
    return _newClient(config, _transferTimeoutMs);
  }

  Future<Pair<bool, String?>> init() async {
    try {
      await _connect(_getConfig(), force: true);

      return Pair(first: true, second: null);
    } catch (e) {
      return Pair(first: false, second: _describeError(e));
    }
  }

  String _getFileName() {
    return 'piliplus_settings_${DeviceUtils.platformName}.json';
  }

  Future<void> backup() => _run(WebDavTask.backup, _doBackup);

  Future<void> restore() => _run(WebDavTask.restore, _doRestore);

  /// 同一时刻只允许一个操作，避免连点并发写同一文件
  Future<void> _run(WebDavTask type, Future<void> Function() action) async {
    if (task.value != null) {
      SmartDialog.showToast('操作进行中，请稍候');
      return;
    }
    task.value = type;
    try {
      await action();
    } catch (e) {
      // 兜底，避免未捕获异常打断 UI 或让按钮一直处于禁用状态
      SmartDialog.showToast(
        '${type == WebDavTask.backup ? '备份' : '恢复'}失败：${_describeError(e)}',
      );
    } finally {
      task.value = null;
    }
  }

  // ---------------------------------------------------------------- backup

  Future<void> _doBackup() async {
    final config = _getConfig();

    final Map<String, dynamic> payload;
    try {
      payload = _buildPayload();
    } catch (e) {
      SmartDialog.showToast('备份失败：读取本地数据出错（$e）');
      return;
    }

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    if (bytes.length > _maxPayloadBytes) {
      SmartDialog.showToast(
        '备份失败：内容过大（${_formatSize(bytes.length)}），'
        '上限为 ${_formatSize(_maxPayloadBytes)}',
      );
      return;
    }

    final webdav.Client client;
    try {
      client = await _openTransferClient(config);
    } catch (e) {
      SmartDialog.showToast('备份失败：${_describeError(e)}');
      return;
    }

    final target = '${config.directory}/${_getFileName()}';
    final bakPath = '$target.bak';
    var hasBak = false;
    try {
      // 先把上一次的备份改成 .bak 留底，写入失败时回滚
      try {
        await client.rename(target, bakPath, true);
        hasBak = true;
      } catch (_) {
        // 旧文件不存在，或服务器不支持 MOVE：退化为直接覆盖
      }
      await client.write(target, bytes);
    } catch (e) {
      if (hasBak) {
        try {
          await client.rename(bakPath, target, true);
        } catch (_) {}
      }
      SmartDialog.showToast('备份失败：${_describeError(e)}');
      return;
    }

    final replyCount = (payload['reply'] as Map?)?.length ?? 0;
    SmartDialog.showToast(
      '备份成功：设置 ${(payload['setting'] as Map).length} 项'
      '${replyCount > 0 ? '、评论 $replyCount 条' : ''}'
      '，共 ${_formatSize(bytes.length)}',
    );
  }

  Map<String, dynamic> _buildPayload() {
    final settings =
        jsonDecode(GStorage.exportAllSettings()) as Map<String, dynamic>;
    final setting = Map<String, dynamic>.from(
      settings[GStorage.setting.name] as Map,
    )..removeWhere((key, _) => webDavExcludedSettingKeys.contains(key));

    final payload = <String, dynamic>{
      'version': formatVersion,
      'app': Constants.appName,
      'platform': DeviceUtils.platformName,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'setting': setting,
      'video': settings[GStorage.video.name],
    };
    if (_exportReply() case final reply?) {
      payload['reply'] = reply;
    }
    return payload;
  }

  /// 评论按 id → base64(protobuf) 导出，保留原始字节
  Map<String, String>? _exportReply() {
    final box = GStorage.reply;
    if (box == null) return null;
    return BackupPayload.encodeReply(box.toMap());
  }

  // --------------------------------------------------------------- restore

  Future<void> _doRestore() async {
    final config = _getConfig();

    final webdav.Client client;
    try {
      client = await _openTransferClient(config);
    } catch (e) {
      SmartDialog.showToast('恢复失败：${_describeError(e)}');
      return;
    }

    final List<int> raw;
    try {
      raw = await client.read('${config.directory}/${_getFileName()}');
    } catch (e) {
      SmartDialog.showToast('恢复失败：${_describeError(e)}');
      return;
    }
    if (raw.length > _maxPayloadBytes) {
      SmartDialog.showToast(
        '恢复失败：备份文件过大（${_formatSize(raw.length)}），'
        '上限为 ${_formatSize(_maxPayloadBytes)}',
      );
      return;
    }

    // 先完整校验，任何一项不通过都不动本机数据
    final BackupPayload data;
    try {
      data = BackupPayload.parse(raw);
    } on BackupFormatException catch (e) {
      SmartDialog.showToast('恢复失败：${e.message}');
      return;
    }

    // 备份里剔除了 WebDAV 配置，导入后要写回，避免本机配置被清空
    final localWebDav = <String, dynamic>{
      for (final key in webDavExcludedSettingKeys)
        key: GStorage.setting.get(key),
    };

    final String snapshotPath;
    try {
      snapshotPath = await _writeLocalSnapshot();
    } catch (e) {
      SmartDialog.showToast('恢复失败：无法保存本机设置快照（$e）');
      return;
    }

    try {
      await GStorage.importAllJsonSettings({
        GStorage.setting.name: data.setting,
        GStorage.video.name: data.video,
      });
    } catch (e) {
      // 写入中途失败时设置已被清空，尽量用快照回滚
      var rollbackTip = '';
      try {
        await GStorage.importAllSettings(
          await File(snapshotPath).readAsString(),
        );
        rollbackTip = '，已自动回滚到恢复前的设置';
      } catch (_) {
        rollbackTip = '，可手工回滚：$snapshotPath';
      }
      SmartDialog.showToast('恢复失败：写入本机设置出错（$e）$rollbackTip');
      return;
    }

    for (final entry in localWebDav.entries) {
      if (entry.value != null) {
        await GStorage.setting.put(entry.key, entry.value);
      }
    }

    var replyTip = '';
    final reply = data.reply;
    if (reply != null && reply.isNotEmpty) {
      final box = GStorage.reply;
      if (box == null) {
        replyTip = '\n评论记录未恢复：请先在设置里开启「保存评论」并重启应用';
      } else {
        await box.putAll(reply);
        // 让已打开的评论页重新加载
        GStorage.replyRevision.value++;
        replyTip = '，已导入 ${reply.length} 条评论';
      }
    }

    SmartDialog.showToast('恢复成功$replyTip\n部分设置需重启生效');
  }

  /// 恢复前在本机留一份当前设置快照，出问题可手工回滚
  Future<String> _writeLocalSnapshot() async {
    final dir = Directory(path.join(appSupportDirPath, 'settings_backup'))
      ..createSync(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    final file = File(path.join(dir.path, 'piliplus_local_$stamp.json'));
    await file.writeAsString(GStorage.exportAllSettings());
    return file.path;
  }

  // ---------------------------------------------------------------- errors

  String _describeError(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.transformTimeout:
          return '请求超时，请检查网络或服务器状态';
        case DioExceptionType.connectionError:
          return '无法连接到服务器，请检查地址与网络';
        case DioExceptionType.badCertificate:
          return '服务器证书校验失败';
        case DioExceptionType.cancel:
          return '操作已取消';
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode;
          return switch (code) {
            401 => '认证失败（401），请检查用户名和密码',
            403 => '没有访问权限（403）',
            404 => '备份文件不存在（404）',
            405 || 501 => '服务器不支持该操作（$code）',
            507 => '服务器存储空间不足（507）',
            _ => '服务器返回错误（${code ?? '未知状态码'}）',
          };
        case DioExceptionType.unknown:
          return '网络请求失败：${error.message ?? error.error ?? '未知错误'}';
      }
    }
    return error.toString();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}
