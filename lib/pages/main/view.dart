import 'dart:io';

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/floating_navigation_bar.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/main_layout.dart';
import 'package:PiliPlus/common/widgets/route_aware_mixin.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/home/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/main/web_tabs/controller.dart';
import 'package:PiliPlus/pages/main/web_tabs/view.dart';
import 'package:PiliPlus/pages/main/web_tabs/web_tab.dart';
import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/desktop/tray_controller.dart';
import 'package:PiliPlus/utils/desktop/window_controller.dart';
import 'package:PiliPlus/utils/extension/context_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/mobile_observer.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends PopScopeState<MainApp>
    with RouteAware, RouteAwareMixin, WidgetsBindingObserver {
  final _mainController = Get.put(MainController());
  late EdgeInsets _padding;
  late ColorScheme _colorScheme;
  Brightness? _brightness;

  @override
  bool get initCanPop => false;

  @override
  void initState() {
    super.initState();
    addObserverMobile(this);
    if (Platform.isMacOS) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
    if (PlatformUtils.isDesktop) {
      WindowController.instance.init();
      TrayController.instance.init();
    }
    if (!Platform.isMacOS) {
      PiliScheme.init();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _padding = MediaQuery.viewPaddingOf(context);
    _colorScheme = ColorScheme.of(context);
    final brightness = _colorScheme.brightness;
    NetworkImgLayer.reduce =
        NetworkImgLayer.reduceLuxColor != null && brightness.isDark;
    if (PlatformUtils.isDesktop) {
      if (_brightness != brightness) {
        _brightness = brightness;
        nativeapi.Application.instance.setBrightness(
          brightness == .dark ? .dark : .light,
        );
      }
    }
    if (!_mainController.useSideBar) {
      _mainController.useBottomNav = MediaQuery.sizeOf(context).isPortrait;
    }
  }

  @override
  void didPopNext() {
    addObserverMobile(this);
    _mainController
      ..checkUnreadDynamic()
      ..checkDefaultSearch(true)
      ..checkUnread(_mainController.useBottomNav);
    super.didPopNext();
  }

  @override
  void didPushNext() {
    removeObserverMobile(this);
    super.didPushNext();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _mainController
        ..checkUnreadDynamic()
        ..checkDefaultSearch(true)
        ..checkUnread(_mainController.useBottomNav);
    }
  }

  @override
  void dispose() {
    if (Platform.isMacOS) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    if (PlatformUtils.isDesktop) {
      WindowController.instance.dispose();
      TrayController.instance.dispose();
    }
    removeObserverMobile(this);
    PiliScheme.listener?.cancel();
    GStorage.close();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    return event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyR &&
        HardwareKeyboard.instance.isMetaPressed &&
        _mainController.refreshRecommendations();
  }

  @pragma('vm:prefer-inline')
  static void _onBack() {
    if (Platform.isAndroid) {
      AndroidHelper.back();
    }
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (_mainController.directExitOnBack) {
      _onBack();
    } else {
      if (_mainController.selectedIndex.value != 0) {
        _mainController
          ..setIndex(0)
          ..barOffset?.value = 0.0
          ..showBottomBar?.value = true
          ..setSearchBar();
      } else {
        _onBack();
      }
    }
  }

  Widget? get _bottomNav {
    Widget? bottomNav;
    if (_mainController.navigationBars.length > 1) {
      if (_mainController.floatingNavBar) {
        bottomNav = Obx(
          () => FloatingNavigationBar(
            onDestinationSelected: _mainController.setIndex,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: _mainController.navigationBars
                .map(
                  (e) => FloatingNavigationDestination(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      } else if (_mainController.enableMYBar) {
        bottomNav = Obx(
          () => NavigationBar(
            maintainBottomViewPadding: true,
            onDestinationSelected: _mainController.setIndex,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: _mainController.navigationBars
                .map(
                  (e) => NavigationDestination(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      } else {
        bottomNav = Obx(
          () => BottomNavigationBar(
            currentIndex: _mainController.selectedIndex.value,
            onTap: _mainController.setIndex,
            iconSize: 16,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            type: .fixed,
            items: _mainController.navigationBars
                .map(
                  (e) => BottomNavigationBarItem(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    activeIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      }

      if (_mainController.hideBottomBar) {
        if (_mainController.barOffset case final barOffset?) {
          return Obx(
            () => FractionalTranslation(
              translation: Offset(
                0.0,
                barOffset.value / Style.topBarHeight,
              ),
              child: bottomNav,
            ),
          );
        }
        if (_mainController.showBottomBar case final showBottomBar?) {
          return Obx(
            () => AnimatedSlide(
              curve: Curves.easeInOutCubicEmphasized,
              duration: const Duration(milliseconds: 500),
              offset: Offset(0, showBottomBar.value ? 0 : 1),
              child: bottomNav,
            ),
          );
        }
      }
    }

    return bottomNav;
  }

  Widget _sideBar() {
    final webTabs = _mainController.webTabs;
    if (webTabs == null) {
      return _buildSideBar(null, const <WebTab>[]);
    }
    return Obx(() {
      final tabs = webTabs.enabled.value ? webTabs.tabs : const <WebTab>[];
      return _buildSideBar(webTabs, tabs);
    });
  }

  Widget _buildSideBar(WebTabsController? webTabs, List<WebTab> tabs) {
    if (_mainController.navigationBars.length > 1 ||
        tabs.isNotEmpty ||
        (webTabs != null && webTabs.enabled.value)) {
      if (context.isTablet && _mainController.optTabletNav) {
        return _buildNavigationDrawer(webTabs, tabs);
      }
      return _buildNavigationRail(webTabs, tabs);
    }
    return Container(
      width: 80,
      margin: .only(top: 12 + _padding.top, left: _padding.left),
      child: userAndSearchVertical(),
    );
  }

  /// Index of the selected entry in the combined `[tabs..., navigationBars...]`
  /// list used by both drawers and rails.
  int _sideBarSelectedIndex(WebTabsController? webTabs, List<WebTab> tabs) {
    final activeTab = webTabs?.active;
    if (activeTab != null) {
      final index = tabs.indexOf(activeTab);
      if (index >= 0) return index;
    }
    return tabs.length + _mainController.selectedIndex.value;
  }

  void _onSideBarDestinationSelected(
    WebTabsController? webTabs,
    List<WebTab> tabs,
    int value,
  ) {
    if (value < tabs.length) {
      feedBack();
      webTabs!.select(tabs[value]);
    } else {
      _mainController.setIndex(value - tabs.length);
    }
  }

  /// Tab labels come from page titles, so they can be long; the drawer lays its
  /// label out unbounded, hence the fixed [width].
  Widget _buildTabLabel(WebTab tab, {double? width}) {
    final label = Obx(
      () => Text(
        tab.label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (width == null) return label;
    return SizedBox(width: width, child: label);
  }

  /// Tablet/narrow-desktop side bar: same entries as the rail, but a drawer.
  Widget _buildNavigationDrawer(
    WebTabsController? webTabs,
    List<WebTab> tabs,
  ) {
    return Padding(
      padding: const .only(top: 25),
      child: MediaQuery.removePadding(
        context: context,
        removeRight: true,
        child: Obx(
          () => DrawerTheme(
            data: DrawerThemeData(
              width:
                  (_mainController.hideSideBarLabel ? 80 : 130) + _padding.left,
            ),
            child: NavigationDrawer(
              /// apply `lib/scripts/navigation_drawer.patch`
              flex: 5,
              backgroundColor: Colors.transparent,
              onDestinationSelected: (value) =>
                  _onSideBarDestinationSelected(webTabs, tabs, value),
              selectedIndex: _sideBarSelectedIndex(webTabs, tabs),
              header: Expanded(flex: 4, child: userAndSearchVertical()),
              tilePadding: const .symmetric(vertical: 5, horizontal: 12),
              indicatorShape: _mainController.hideSideBarLabel
                  ? const RoundedRectangleBorder(
                      borderRadius: .all(.circular(12)),
                    )
                  : const RoundedRectangleBorder(
                      borderRadius: .all(.circular(16)),
                    ),
              children: [
                for (final tab in tabs)
                  NavigationDrawerDestination(
                    label: _mainController.hideSideBarLabel
                        ? Semantics(
                            label: tab.label,
                            child: const SizedBox.shrink(),
                          )
                        : _buildTabLabel(tab, width: 46),
                    icon: WebTabRailIcon(
                      tab: tab,
                      size: 24,
                      onClose: () => webTabs!.close(tab),
                    ),
                    selectedIcon: WebTabRailIcon(
                      tab: tab,
                      size: 24,
                      onClose: () => webTabs!.close(tab),
                    ),
                  ),
                for (final e in _mainController.navigationBars)
                  NavigationDrawerDestination(
                    label: _mainController.hideSideBarLabel
                        ? Semantics(
                            label: e.label,
                            child: const SizedBox.shrink(),
                          )
                        : Text(e.label),
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                if (webTabs != null && webTabs.enabled.value) ...[
                  const Divider(height: 9, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: _mainController.hideSideBarLabel
                        ? null
                        : const Text(
                            '新建标签页',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () => webTabs.open(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The rail holds the regular destinations plus, on desktop, the runtime
  /// web tabs prepended to them and a "new tab" button below them.
  Widget _buildNavigationRail(WebTabsController? webTabs, List<WebTab> tabs) {
    final navigationBars = _mainController.navigationBars;

    return NavigationRail(
      groupAlignment: 0.5,
      labelType: _mainController.hideSideBarLabel ? .none : .selected,
      leading: userAndSearchVertical(),
      backgroundColor: Colors.transparent,
      scrollable: tabs.length + navigationBars.length > 9,
      onDestinationSelected: (value) =>
          _onSideBarDestinationSelected(webTabs, tabs, value),
      selectedIndex: _sideBarSelectedIndex(webTabs, tabs),
      destinations: [
        for (final tab in tabs)
          NavigationRailDestination(
            label: _buildTabLabel(tab),
            icon: WebTabRailIcon(tab: tab, onClose: () => webTabs!.close(tab)),
            selectedIcon: WebTabRailIcon(
              tab: tab,
              onClose: () => webTabs!.close(tab),
            ),
          ),
        for (final e in navigationBars)
          NavigationRailDestination(
            label: Text(e.label),
            icon: _buildIcon(type: e),
            selectedIcon: _buildIcon(type: e, selected: true),
          ),
      ],
      trailing: webTabs == null || !webTabs.enabled.value
          ? null
          : _buildNewTabButton(webTabs),
    );
  }

  Widget _buildNewTabButton(WebTabsController webTabs) {
    final colorScheme = ColorScheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Divider(
            height: 1,
            thickness: 0.5,
            color: colorScheme.outline.withValues(alpha: 0.12),
          ),
        ),
        IconButton(
          tooltip: '新建标签页',
          icon: const Icon(Icons.add, size: 20),
          onPressed: () => webTabs.open(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_mainController.mainTabBarView) {
      child = TabBarView(
        controller: _mainController.controller,
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: _mainController.useBottomNav ? .horizontal : .vertical,
        children: _mainController.navigationBars.map((i) => i.page).toList(),
      );
    } else {
      child = PageView(
        controller: _mainController.controller,
        physics: const NeverScrollableScrollPhysics(),
        children: _mainController.navigationBars.map((i) => i.page).toList(),
      );
    }

    Widget? sideBar;
    Widget? bottomNav;
    final EdgeInsets padding;
    if (_mainController.useBottomNav) {
      bottomNav = _bottomNav;
      if (bottomNav != null) {
        bottomNav = MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: bottomNav,
        );
      }
      padding = _padding.copyWith(bottom: 0);
    } else {
      sideBar = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: _colorScheme.outline.withValues(alpha: 0.06),
            ),
          ),
        ),
        child: _sideBar(),
      );
      padding = .only(top: _padding.top, right: _padding.right);
    }

    final Widget navBody = Padding(padding: padding, child: child);
    Widget body = navBody;
    final webTabs = _mainController.webTabs;
    if (webTabs != null) {
      body = Obx(() {
        final tabs = webTabs.enabled.value ? webTabs.tabs : const <WebTab>[];
        final activeTab = webTabs.active;
        final activeTabIndex = activeTab == null ? -1 : tabs.indexOf(activeTab);
        final showWebTab =
            activeTabIndex >= 0 &&
            !_mainController.useBottomNav &&
            sideBar != null;
        return IndexedStack(
          sizing: StackFit.expand,
          index: showWebTab ? 1 : 0,
          children: [
            navBody,
            if (tabs.isEmpty)
              const SizedBox.shrink()
            else
              IndexedStack(
                sizing: StackFit.expand,
                index: activeTabIndex >= 0 ? activeTabIndex : 0,
                children: [
                  for (final tab in tabs)
                    WebTabView(key: ValueKey(tab.id), tab: tab),
                ],
              ),
          ],
        );
      });
    }

    child = Material(
      child: MainLayout(
        sideBar: sideBar,
        bottomNav: bottomNav,
        body: body,
      ),
    );

    if (PlatformUtils.isMobile) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: _colorScheme.brightness,
          statusBarIconBrightness: _colorScheme.brightness.reverse,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: _colorScheme.brightness.reverse,
        ),
        child: child,
      );
    }

    return child;
  }

  Widget _buildIcon({required NavigationBarType type, bool selected = false}) {
    final icon = selected ? type.selectIcon : type.icon;
    return type == .dynamics
        ? Obx(
            () {
              final dynCount = _mainController.dynCount.value;
              return Badge(
                isLabelVisible: dynCount > 0,
                label: _mainController.dynamicBadgeMode == .number
                    ? Text(dynCount.toString())
                    : null,
                padding: const .symmetric(horizontal: 6),
                child: icon,
              );
            },
          )
        : icon;
  }

  Widget userAndSearchVertical() {
    return Column(
      children: [
        userAvatar(colorScheme: _colorScheme, mainController: _mainController),
        const SizedBox(height: 8),
        msgBadge(_mainController),
        IconButton(
          tooltip: '搜索',
          icon: const Icon(
            Icons.search_outlined,
            semanticLabel: '搜索',
          ),
          onPressed: () => Get.toNamed('/search'),
        ),
      ],
    );
  }
}
