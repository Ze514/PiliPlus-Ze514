import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:nativeapi/nativeapi.dart' as nativeapi;

/// 判定上次保存的窗口位置是否还有效时，要求至少有多少像素留在工作区内
const double kWindowKeepVisible = 30.0;

/// 窗口尺寸不得超过工作区，避免恢复出一个比屏幕还大的窗口
Size fitWindowSizeToWorkArea(Size windowSize, Rect workArea) => Size(
  math.min(windowSize.width, workArea.width),
  math.min(windowSize.height, workArea.height),
);

/// 最小窗口尺寸不得超过工作区，否则小屏（如 1024×640）上窗口无法收缩到屏幕内
nativeapi.Size fitMinSizeToWorkArea(nativeapi.Size minSize, Rect workArea) =>
    nativeapi.Size(
      width: math.min(minSize.width, workArea.width),
      height: math.min(minSize.height, workArea.height),
    );

/// 计算窗口左上角坐标。
///
/// [savedPosition] 是上次退出时的位置：已经完全不在工作区内（换了显示器、
/// 换了分辨率）时重新居中；仍然可见时留在原处，但会被拉回工作区内。
Offset calcWindowOffset({
  required Size windowSize,
  required Rect workArea,
  Offset? savedPosition,
}) {
  if (savedPosition != null) {
    final dx = savedPosition.dx;
    final dy = savedPosition.dy;
    // 窗口在保存位置下还有多少落在工作区内
    final visibleWidth =
        math.min(dx + windowSize.width, workArea.right) -
        math.max(dx, workArea.left);
    final visibleHeight =
        math.min(dy + windowSize.height, workArea.bottom) -
        math.max(dy, workArea.top);
    if (visibleWidth >= kWindowKeepVisible &&
        visibleHeight >= kWindowKeepVisible) {
      // 还看得见就不用重新居中，但把窗口拉回工作区，避免大部分跑到屏幕外
      final maxDx = math.max(workArea.left, workArea.right - windowSize.width);
      final maxDy = math.max(workArea.top, workArea.bottom - windowSize.height);
      return Offset(
        math.min(math.max(dx, workArea.left), maxDx),
        math.min(math.max(dy, workArea.top), maxDy),
      );
    }
  }

  return Offset(
    workArea.left + (workArea.width - windowSize.width) / 2,
    workArea.top + (workArea.height - windowSize.height) / 2,
  );
}
