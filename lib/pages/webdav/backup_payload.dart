import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/utils/storage_key.dart';

/// 备份格式版本
///
/// 1 为旧的 `{setting, video}` 平铺结构（无版本号），2 起带元信息与评论记录。
const int webDavBackupVersion = 2;

/// 不随备份上传的设置项，避免账号密码跟着备份一起泄露
const List<String> webDavExcludedSettingKeys = [
  SettingBoxKey.webdavUri,
  SettingBoxKey.webdavUsername,
  SettingBoxKey.webdavPassword,
  SettingBoxKey.webdavDirectory,
];

/// 备份文件不合法，[message] 可直接展示给用户
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 解析后的备份内容
class BackupPayload {
  const BackupPayload({
    required this.version,
    required this.setting,
    required this.video,
    this.reply,
  });

  final int version;
  final Map<String, dynamic> setting;
  final Map<String, dynamic> video;

  /// 评论 id → protobuf 原始字节，旧备份为 null
  final Map<String, Uint8List>? reply;

  /// 评论按 id → base64(protobuf) 编码，保留原始字节而不走 JSON 映射
  static Map<String, String> encodeReply(Map<dynamic, Uint8List> values) => {
    for (final entry in values.entries)
      entry.key.toString(): base64Encode(entry.value),
  };

  /// 解析备份文件
  ///
  /// 任何一项不通过都抛 [BackupFormatException]，调用方据此在不改动本机数据的前提下返回。
  factory BackupPayload.parse(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw BackupFormatException('备份文件不是合法的 JSON（${e.message}）');
    }

    if (decoded is! Map) {
      throw const BackupFormatException('备份文件结构不正确（顶层不是对象）');
    }

    final version = decoded['version'];
    if (version != null) {
      if (version is! int || version < 1) {
        throw const BackupFormatException('备份文件的版本号无效');
      }
      if (version > webDavBackupVersion) {
        throw BackupFormatException(
          '备份文件来自更新的版本（v$version），请升级应用后再恢复',
        );
      }
    }

    final setting = decoded['setting'];
    final video = decoded['video'];
    if (setting is! Map || video is! Map) {
      throw const BackupFormatException('备份文件缺少设置数据（setting / video）');
    }

    return BackupPayload(
      // 旧文件没有 version，按 v1 处理：只恢复设置，不含评论
      version: version is int ? version : 1,
      setting: Map<String, dynamic>.from(setting),
      video: Map<String, dynamic>.from(video),
      reply: _parseReply(decoded['reply']),
    );
  }

  /// 评论必须能还原成 [ReplyInfo]，避免把坏数据写进 Hive
  static Map<String, Uint8List>? _parseReply(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) {
      throw const BackupFormatException('备份文件中的评论记录格式不正确');
    }
    final result = <String, Uint8List>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! String) {
        throw const BackupFormatException('备份文件中的评论记录格式不正确');
      }
      try {
        final data = base64Decode(value);
        ReplyInfo.fromBuffer(data);
        result[key] = data;
      } catch (_) {
        throw BackupFormatException('备份文件中的评论「$key」已损坏，无法恢复');
      }
    }
    return result;
  }
}
