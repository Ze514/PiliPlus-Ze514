import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/pages/webdav/backup_payload.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _replyBytes({String id = '1'}) =>
    (ReplyInfo.create()..mergeFromProto3Json({'id': id, 'ctime': 1700000000}))
        .writeToBuffer();

Uint8List _bytes(Object? json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

Matcher _rejected([String? message]) => throwsA(
  isA<BackupFormatException>().having(
    (e) => e.message,
    'message',
    message == null ? anything : contains(message),
  ),
);

void main() {
  group('BackupPayload.parse', () {
    test('解析 v2 备份并还原评论原始字节', () {
      final replyBytes = _replyBytes();
      final payload = BackupPayload.parse(
        _bytes({
          'version': 2,
          'app': 'PiliPlus',
          'platform': 'desktop',
          'exportedAt': '2026-01-01T00:00:00.000Z',
          'setting': {'key': 'value'},
          'video': {'cdn': 1},
          'reply': {'1': base64Encode(replyBytes)},
        }),
      );

      expect(payload.version, 2);
      expect(payload.setting, {'key': 'value'});
      expect(payload.video, {'cdn': 1});
      expect(payload.reply, isNotNull);
      expect(payload.reply!['1'], replyBytes);
    });

    test('兼容没有 version 的 v1 备份', () {
      final payload = BackupPayload.parse(
        _bytes({
          'setting': {'a': 1},
          'video': {'b': 2},
        }),
      );

      expect(payload.version, 1);
      expect(payload.setting, {'a': 1});
      expect(payload.video, {'b': 2});
      expect(payload.reply, isNull);
    });

    test('无评论时 reply 为 null', () {
      final payload = BackupPayload.parse(
        _bytes({'version': 2, 'setting': {}, 'video': {}}),
      );

      expect(payload.reply, isNull);
    });

    test('encodeReply 与 parse 互为逆运算', () {
      final replyBytes = _replyBytes();
      final payload = BackupPayload.parse(
        _bytes({
          'version': 2,
          'setting': {},
          'video': {},
          'reply': BackupPayload.encodeReply({42: replyBytes}),
        }),
      );

      expect(payload.reply!['42'], replyBytes);
    });

    test('非 JSON 内容被拒绝', () {
      expect(
        () => BackupPayload.parse(Uint8List.fromList(utf8.encode('not json'))),
        _rejected('JSON'),
      );
    });

    test('顶层不是对象被拒绝', () {
      expect(() => BackupPayload.parse(_bytes(['a'])), _rejected('顶层'));
    });

    test('缺少 setting / video 被拒绝', () {
      expect(
        () => BackupPayload.parse(_bytes({'version': 2, 'video': {}})),
        _rejected('setting'),
      );
      expect(
        () => BackupPayload.parse(_bytes({'version': 2, 'setting': 1})),
        _rejected('setting'),
      );
    });

    test('高于当前版本的备份被拒绝', () {
      expect(
        () => BackupPayload.parse(
          _bytes({'version': 99, 'setting': {}, 'video': {}}),
        ),
        _rejected('更新'),
      );
    });

    test('版本号非法被拒绝', () {
      expect(
        () => BackupPayload.parse(
          _bytes({'version': '2', 'setting': {}, 'video': {}}),
        ),
        _rejected('版本号'),
      );
    });

    test('reply 不是对象被拒绝', () {
      expect(
        () => BackupPayload.parse(
          _bytes({'version': 2, 'setting': {}, 'video': {}, 'reply': []}),
        ),
        _rejected('评论'),
      );
    });

    test('reply 值不是 base64 被拒绝', () {
      expect(
        () => BackupPayload.parse(
          _bytes({
            'version': 2,
            'setting': {},
            'video': {},
            'reply': {'1': '***'},
          }),
        ),
        _rejected('损坏'),
      );
    });

    test('reply 值不是合法 protobuf 被拒绝', () {
      expect(
        () => BackupPayload.parse(
          _bytes({
            'version': 2,
            'setting': {},
            'video': {},
            'reply': {
              '1': base64Encode([0xFF, 0xFF, 0xFF]),
            },
          }),
        ),
        _rejected('损坏'),
      );
    });
  });
}
