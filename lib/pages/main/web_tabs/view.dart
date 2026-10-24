import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/main.dart' show webViewEnvironment;
import 'package:PiliPlus/pages/main/web_tabs/web_tab.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Favicon bytes keyed by origin, shared by every tab. Purely in memory.
final _faviconCache = <String, Uint8List>{};

/// One web tab: a slim browser toolbar on top of an incognito web view.
///
/// The web view is created lazily, only once the tab actually navigates
/// somewhere, and is kept alive by the `IndexedStack` in the side bar so
/// switching tabs never reloads a page.
class WebTabView extends StatefulWidget {
  const WebTabView({super.key, required this.tab});

  final WebTab tab;

  @override
  State<WebTabView> createState() => _WebTabViewState();
}

class _WebTabViewState extends State<WebTabView> {
  late final TextEditingController _addressController = TextEditingController(
    text: widget.tab.url.value,
  );
  final FocusNode _addressFocus = FocusNode();

  /// Created once so address/title updates don't rebuild the web view.
  Widget? _webView;

  WebTab get _tab => widget.tab;

  @override
  void initState() {
    super.initState();
    if (_tab.isBlank) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addressFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  void _syncAddress(String url) {
    if (!mounted || url.isEmpty || _addressFocus.hasFocus) return;
    if (_addressController.text == url) return;
    _addressController.value = TextEditingValue(
      text: url,
      selection: TextSelection.collapsed(offset: url.length),
    );
  }

  Uri? _parseUrl(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    Uri? uri = Uri.tryParse(text);
    if (uri == null) {
      SmartDialog.showToast('无效的网址');
      return null;
    }
    if (!uri.hasScheme) {
      uri = Uri.tryParse('https://$text');
    }
    if (uri == null || uri.host.isEmpty) {
      SmartDialog.showToast('无效的网址');
      return null;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      SmartDialog.showToast('仅支持 http/https 网址');
      return null;
    }
    return uri;
  }

  Future<void> _onSubmit(String value) async {
    final uri = _parseUrl(value);
    if (uri == null) return;
    _addressFocus.unfocus();
    final controller = _tab.webViewController;
    if (controller == null) {
      _tab.url.value = uri.toString();
    } else {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri.uri(uri)));
    }
  }

  Future<void> _refreshHistoryState(InAppWebViewController controller) async {
    try {
      final canGoBack = await controller.canGoBack();
      final canGoForward = await controller.canGoForward();
      _tab.canGoBack.value = canGoBack;
      _tab.canGoForward.value = canGoForward;
    } catch (_) {}
  }

  Future<void> _loadFavicon() async {
    final tab = _tab;
    final uri = Uri.tryParse(tab.url.value);
    if (uri == null || uri.host.isEmpty) return;
    final origin = '${uri.scheme}://${uri.authority}';
    final cached = _faviconCache[origin];
    if (cached != null) {
      tab.favicon.value = cached;
      return;
    }
    try {
      final res = await Request().get<Uint8List>(
        '$origin/favicon.ico',
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 8),
          // Never carry the app's identity into these tabs.
          extra: {'account': const NoAccount()},
        ),
      );
      final data = res.data;
      if (res.statusCode == 200 && data is List<int> && data.length > 64) {
        final bytes = data is Uint8List ? data : Uint8List.fromList(data);
        _faviconCache[origin] = bytes;
        tab.favicon.value = bytes;
      }
    } catch (_) {}
  }

  void _openInBrowser() {
    final url = _tab.url.value;
    if (url.isEmpty) return;
    PageUtils.launchURL(url);
  }

  void _copyLink() {
    final url = _tab.url.value;
    if (url.isEmpty) return;
    Clipboard.setData(ClipboardData(text: url));
    SmartDialog.showToast('已复制链接');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Column(
      children: [
        _buildToolbar(context, colorScheme),
        Obx(
          () => _tab.loading.value
              ? LinearProgressIndicator(
                  minHeight: 2,
                  value: _tab.progress.value <= 0 || _tab.progress.value >= 1
                      ? null
                      : _tab.progress.value,
                )
              : const SizedBox(height: 2),
        ),
        Expanded(
          child: Obx(
            () => _tab.isBlank
                ? _buildBlankPage(context, colorScheme)
                : (_webView ??= _buildWebView()),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, ColorScheme colorScheme) {
    final theme = Theme.of(context);
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          Obx(
            () => _ToolbarButton(
              icon: Icons.arrow_back,
              tooltip: '后退',
              onPressed: _tab.canGoBack.value
                  ? () => _tab.webViewController?.goBack()
                  : null,
            ),
          ),
          Obx(
            () => _ToolbarButton(
              icon: Icons.arrow_forward,
              tooltip: '前进',
              onPressed: _tab.canGoForward.value
                  ? () => _tab.webViewController?.goForward()
                  : null,
            ),
          ),
          Obx(
            () => _tab.loading.value
                ? _ToolbarButton(
                    icon: Icons.close,
                    tooltip: '停止',
                    onPressed: () => _tab.webViewController?.stopLoading(),
                  )
                : _ToolbarButton(
                    icon: Icons.refresh,
                    tooltip: '刷新',
                    onPressed: _tab.isBlank
                        ? null
                        : () => _tab.webViewController?.reload(),
                  ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: 30,
              child: TextField(
                controller: _addressController,
                focusNode: _addressFocus,
                textInputAction: TextInputAction.go,
                onSubmitted: _onSubmit,
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '输入网址，回车访问',
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Obx(
            () => PopupMenuButton<String>(
              tooltip: '更多',
              iconSize: 18,
              enabled: !_tab.isBlank,
              onSelected: (value) => switch (value) {
                'browser' => _openInBrowser(),
                'copy' => _copyLink(),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'browser', child: Text('在浏览器打开')),
                PopupMenuItem(value: 'copy', child: Text('复制链接')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlankPage(BuildContext context, ColorScheme colorScheme) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.travel_explore,
            size: 64,
            color: colorScheme.outline.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 14),
          Text(
            '输入网址开始浏览',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '此标签不保存 Cookie，关闭后不留痕迹',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    final tab = _tab;
    return InAppWebView(
      webViewEnvironment: webViewEnvironment,
      initialSettings: InAppWebViewSettings(
        // WebView2 InPrivate profile: cookies/localStorage/cache stay in
        // memory and die with the process.
        incognito: true,
        cacheEnabled: false,
        javaScriptEnabled: true,
        forceDark: ForceDark.AUTO,
        algorithmicDarkeningAllowed: true,
        userAgent: BrowserUa.pc,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      ),
      initialUrlRequest: URLRequest(url: WebUri(tab.url.value)),
      onWebViewCreated: (controller) {
        tab.webViewController = controller;
      },
      onLoadStart: (controller, url) {
        tab.loading.value = true;
        tab.progress.value = 0;
        _syncAddress(url?.toString() ?? '');
      },
      onProgressChanged: (controller, progress) {
        tab.progress.value = progress / 100;
      },
      onTitleChanged: (controller, title) {
        tab.title.value = title ?? '';
      },
      onLoadStop: (controller, url) async {
        tab.loading.value = false;
        tab.progress.value = 1;
        final current = url?.toString() ?? '';
        if (current.isNotEmpty) tab.url.value = current;
        _syncAddress(current);
        await _refreshHistoryState(controller);
        await _loadFavicon();
      },
      onUpdateVisitedHistory: (controller, url, isReload) async {
        final current = url?.toString() ?? '';
        if (current.isNotEmpty && current != tab.url.value) {
          tab.url.value = current;
        }
        _syncAddress(current);
        await _refreshHistoryState(controller);
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? true) {
          tab.loading.value = false;
        }
      },
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    );
  }
}

/// The side bar entry of a tab: favicon, tooltip with the page title, a close
/// button on hover and middle-click to close.
class WebTabRailIcon extends StatefulWidget {
  const WebTabRailIcon({
    super.key,
    required this.tab,
    required this.onClose,
    this.size = 34,
  });

  final WebTab tab;
  final VoidCallback onClose;

  /// Box size of the icon; the drawer uses a smaller one than the rail.
  final double size;

  @override
  State<WebTabRailIcon> createState() => _WebTabRailIconState();
}

class _WebTabRailIconState extends State<WebTabRailIcon> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final iconSize = widget.size >= 30 ? 22.0 : 18.0;
    return Obx(() {
      final bytes = widget.tab.favicon.value;
      return Tooltip(
        message: widget.tab.label,
        waitDuration: const Duration(milliseconds: 500),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: Listener(
            onPointerDown: (event) {
              if (event.buttons == kMiddleMouseButton) {
                widget.onClose();
              }
            },
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (bytes == null)
                    Icon(
                      Icons.public,
                      size: iconSize,
                      color: colorScheme.onSurfaceVariant,
                    )
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.memory(
                        bytes,
                        width: iconSize,
                        height: iconSize,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.public,
                          size: iconSize,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (_hover)
                    Positioned(
                      top: -1,
                      right: -1,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onClose,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.surfaceContainerHighest,
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                              width: 0.5,
                            ),
                          ),
                          child: Icon(
                            Icons.close,
                            size: 10,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
