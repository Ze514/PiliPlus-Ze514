import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/main/web_tabs/web_tab.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// Holds the runtime-only web tabs shown in the desktop side bar.
///
/// Nothing is persisted: tabs die with the process, and each tab's web view
/// uses an incognito profile (see `WebTabView`), so cookies never reach disk.
class WebTabsController extends GetxController {
  /// The web tab feature needs a platform implementation of
  /// `flutter_inappwebview`; Linux is handled by the in-house `LinuxWebview`
  /// plugin instead, which has no incognito support.
  static bool get supported =>
      PlatformUtils.isDesktop && (Platform.isWindows || Platform.isMacOS);

  final RxList<WebTab> tabs = <WebTab>[].obs;
  final RxnInt activeId = RxnInt();
  final RxBool enabled = Pref.webTabEnable.obs;

  int _nextId = 0;

  int get maxTabs => Pref.webTabMax;

  WebTab? get active {
    final id = activeId.value;
    if (id == null) return null;
    for (final tab in tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  /// Opens a new tab and makes it active.
  ///
  /// Returns null when the feature is disabled or [maxTabs] is reached.
  WebTab? open([String? url]) {
    if (!enabled.value) return null;
    if (tabs.length >= maxTabs) {
      SmartDialog.showToast('最多 $maxTabs 个标签页');
      return null;
    }
    final tab = WebTab(_nextId++, url);
    tabs.add(tab);
    activeId.value = tab.id;
    return tab;
  }

  void select(WebTab tab) {
    if (activeId.value != tab.id) {
      activeId.value = tab.id;
    }
  }

  void deactivate() {
    if (activeId.value != null) {
      activeId.value = null;
    }
  }

  void close(WebTab tab) {
    final index = tabs.indexOf(tab);
    if (index == -1) return;
    final wasActive = activeId.value == tab.id;
    tabs.removeAt(index);
    if (wasActive) {
      activeId.value = tabs.isEmpty
          ? null
          : tabs[math.min(index, tabs.length - 1)].id;
    }
    if (tabs.isEmpty) {
      _backToHome();
    }
  }

  void closeAll() {
    tabs.clear();
    activeId.value = null;
  }

  void setEnabled(bool value) {
    enabled.value = value;
    if (!value) closeAll();
  }

  /// Entry point for the settings switch, which may run before/without a
  /// registered controller.
  static void applyEnabled(bool value) {
    if (Get.isRegistered<WebTabsController>()) {
      Get.find<WebTabsController>().setEnabled(value);
    }
  }

  void _backToHome() {
    if (!Get.isRegistered<MainController>()) return;
    final mainController = Get.find<MainController>();
    final index = mainController.navigationBars.indexOf(NavigationBarType.home);
    if (index >= 0 && index != mainController.selectedIndex.value) {
      mainController.setIndex(index);
    }
  }
}
