import 'package:PiliPlus/utils/desktop/window_position.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart' show Offset, Size;
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:screen_retriever/screen_retriever.dart';

const _displayManager = nativeapi.DisplayManager.instance;

nativeapi.Rectangle calcWindowBounds() {
  final windowSize = Pref.windowSize;
  final offset = calcWindowPosition(windowSize);
  return nativeapi.Rectangle(
    x: offset.dx,
    y: offset.dy,
    width: windowSize.width,
    height: windowSize.height,
  );
}

Offset calcWindowPosition(Size windowSize) {
  final displays = _displayManager.getAll();
  final cursorPosition = _displayManager.getCursorPosition().toOffset();

  final currentDisplay =
      displays.firstWhereOrNull(
        (display) => (display.position.toOffset() & display.size.toSize())
            .contains(cursorPosition),
      ) ??
      _displayManager.getPrimary();

  if (currentDisplay == null) return .zero;

  final workArea = currentDisplay.workArea.toRect();

  final windowPosition = Pref.windowPosition;
  if (windowPosition != null && windowPosition.length >= 2) {
    final fitted = fitWindowPosition(
      windowSize: windowSize,
      workArea: workArea,
      savedPosition: Offset(windowPosition[0], windowPosition[1]),
    );
    if (fitted != null) return fitted;
  }

  return Offset(
    workArea.left + (workArea.width / 2) - (windowSize.width / 2),
    workArea.top + ((workArea.height / 2) - (windowSize.height / 2)),
  );
}
