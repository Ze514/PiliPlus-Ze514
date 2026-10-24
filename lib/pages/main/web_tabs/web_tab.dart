import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

/// A single web tab rendered as an extra item of the desktop side bar.
///
/// Everything here is runtime only: the tab is never serialized, and the
/// web view it hosts runs in an incognito profile, so nothing survives a
/// restart.
class WebTab {
  WebTab(this.id, [String? initialUrl]) : url = (initialUrl ?? '').obs;

  final int id;

  /// Current page url. Empty while the tab is still the blank "new tab" page.
  final RxString url;

  final RxString title = ''.obs;
  final RxBool loading = false.obs;
  final RxDouble progress = 1.0.obs;
  final RxBool canGoBack = false.obs;
  final RxBool canGoForward = false.obs;
  final Rxn<Uint8List> favicon = Rxn<Uint8List>();

  InAppWebViewController? webViewController;

  bool get isBlank => url.value.isEmpty;

  String get label {
    final title = this.title.value.trim();
    if (title.isNotEmpty) return title;
    if (!isBlank) return url.value;
    return '新标签页';
  }
}
