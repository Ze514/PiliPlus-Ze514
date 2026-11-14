import 'dart:ui' show Offset, Rect, Size;

import 'package:PiliPlus/utils/desktop/window_position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fitWindowPosition', () {
    test('没有保存位置时返回 null，由调用方居中', () {
      expect(
        fitWindowPosition(
          windowSize: const Size(1180, 720),
          workArea: const Rect.fromLTWH(0, 0, 1920, 1080),
        ),
        isNull,
      );
    });

    test('保存的位置仍可见时保持不动', () {
      expect(
        fitWindowPosition(
          windowSize: const Size(1180, 720),
          workArea: const Rect.fromLTWH(0, 0, 1920, 1080),
          savedPosition: const Offset(100, 120),
        ),
        const Offset(100, 120),
      );
    });

    test('保存的位置贴着工作区左上角时保持不动', () {
      expect(
        fitWindowPosition(
          windowSize: const Size(1180, 720),
          workArea: const Rect.fromLTWH(0, 0, 1920, 1080),
          savedPosition: Offset.zero,
        ),
        Offset.zero,
      );
    });

    test('保存的位置完全不在工作区时返回 null', () {
      expect(
        fitWindowPosition(
          windowSize: const Size(1180, 720),
          workArea: const Rect.fromLTWH(1920, 0, 1920, 1080),
          savedPosition: Offset.zero,
        ),
        isNull,
      );
    });

    test('保存的位置部分越界时拉回工作区', () {
      expect(
        fitWindowPosition(
          windowSize: const Size(1180, 720),
          workArea: const Rect.fromLTWH(0, 0, 1920, 1080),
          savedPosition: const Offset(1500, 900),
        ),
        const Offset(740, 360),
      );
    });

    test('负坐标工作区也能拉回左侧和上侧越界的窗口', () {
      expect(
        fitWindowPosition(
          windowSize: const Size(800, 600),
          workArea: const Rect.fromLTWH(-1280, -100, 1280, 800),
          savedPosition: const Offset(-1320, -120),
        ),
        const Offset(-1280, -100),
      );
    });

    test('可见宽度不足时返回 null', () {
      expect(
        fitWindowPosition(
          windowSize: const Size(1180, 720),
          workArea: const Rect.fromLTWH(0, 0, 1920, 1080),
          savedPosition: const Offset(1900, 120),
        ),
        isNull,
      );
    });

    test('窗口比工作区还大时不会被拉出工作区', () {
      expect(
        fitWindowPosition(
          windowSize: const Size(1180, 720),
          workArea: const Rect.fromLTWH(0, 0, 1024, 640),
          savedPosition: const Offset(40, 40),
        ),
        Offset.zero,
      );
    });
  });
}
