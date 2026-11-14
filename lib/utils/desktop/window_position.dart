import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// 判定上次保存的窗口位置是否还有效时，要求至少有多少像素留在工作区内
const double kWindowKeepVisible = 30.0;

/// 计算恢复窗口时应使用的左上角坐标。
///
/// [savedPosition] 为上次退出时的位置：
/// - 已经完全不在工作区内（换了显示器、改了分辨率）时返回 null，由调用方重新居中；
/// - 仍有 [kWindowKeepVisible] 像素可见时返回原位置，但会被拉回工作区内，
///   避免窗口大部分跑到屏幕外（上游 `calcWindowPosition` 的旧实现只比较左上角
///   与工作区宽高，在多显示器、负坐标工作区下会误判）。
Offset? fitWindowPosition({
  required Size windowSize,
  required Rect workArea,
  Offset? savedPosition,
}) {
  if (savedPosition == null) return null;

  final dx = savedPosition.dx;
  final dy = savedPosition.dy;
  // 窗口在保存位置下还有多少落在工作区内
  final visibleWidth =
      math.min(dx + windowSize.width, workArea.right) - math.max(dx, workArea.left);
  final visibleHeight =
      math.min(dy + windowSize.height, workArea.bottom) - math.max(dy, workArea.top);
  if (visibleWidth < kWindowKeepVisible ||
      visibleHeight < kWindowKeepVisible) {
    return null;
  }

  // 还看得见就不用重新居中，但把窗口拉回工作区
  final maxDx = math.max(workArea.left, workArea.right - windowSize.width);
  final maxDy = math.max(workArea.top, workArea.bottom - windowSize.height);
  return Offset(
    math.min(math.max(dx, workArea.left), maxDx),
    math.min(math.max(dy, workArea.top), maxDy),
  );
}
