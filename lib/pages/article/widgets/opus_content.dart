import 'dart:math' as math;

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/dialog/simple_dialog_option.dart';
import 'package:PiliPlus/common/widgets/emote_tooltip.dart';
import 'package:PiliPlus/common/widgets/gesture/tap_gesture_recognizer.dart';
import 'package:PiliPlus/common/widgets/image/cached_network_svg_image.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/image_grid/image_grid_view.dart';
import 'package:PiliPlus/common/widgets/image_viewer/hero.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/models/common/image_preview_type.dart';
import 'package:PiliPlus/models/dynamics/article_content_model.dart'
    show ArticleContentModel, Rich, Style, Word, Node;
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/pages/article/widgets/sliver_list_ext.dart';
import 'package:PiliPlus/pages/dynamics/widgets/vote.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';

class OpusContent extends StatelessWidget {
  final List<ArticleContentModel> opus;
  final ValueGetter<List<SourceModel>> images;
  final double maxWidth;
  final String opusId;
  final bool reverse;

  const OpusContent({
    super.key,
    required this.opus,
    required this.images,
    required this.maxWidth,
    required this.opusId,
    required this.reverse,
  });

  static InlineSpan _node2Widget({
    required Node item,
    bool isQuote = false,
    required String opusId,
    required ColorScheme colorScheme,
    required ValueGetter<double> surfaceLuminance,
  }) {
    switch (item.type) {
      case 'TEXT_NODE_TYPE_RICH' when (item.rich != null):
        final rich = item.rich!;
        switch (rich.type) {
          case 'RICH_TEXT_NODE_TYPE_EMOJI':
            Emoji emoji = rich.emoji!;
            final size = 20.0 * emoji.size;
            return WidgetSpan(
              rawText: rich.origText,
              child: emoteTooltipBuilder(
                url: emoji.url,
                triggerMode: .tap,
                emote: rich.origText,
                jumpUrl: emoji.jumpUrl,
                colorScheme: colorScheme,
                child: NetworkImgLayer(
                  width: size,
                  height: size,
                  src: emoji.url,
                  type: .emote,
                ),
              ),
            );
          case 'RICH_TEXT_NODE_TYPE_LOTTERY':
            return TextSpan(
              children: [
                WidgetSpan(
                  alignment: .middle,
                  child: Icon(
                    Icons.redeem_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                ),
                TextSpan(
                  text: '${rich.origText} ',
                  style: TextStyle(color: colorScheme.primary),
                  recognizer: NoDeadlineTapGestureRecognizer()
                    ..onTap = () => Get.toNamed(
                      '/webview',
                      parameters: {
                        'url':
                            'https://www.bilibili.com/h5/lottery/result?business_id=$opusId',
                      },
                    ),
                ),
              ],
            );
          case 'RICH_TEXT_NODE_TYPE_VOTE':
            final rid = rich.rid != null ? int.tryParse(rich.rid!) : null;
            return TextSpan(
              children: [
                WidgetSpan(
                  alignment: .middle,
                  child: Icon(
                    Icons.bar_chart_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                ),
                TextSpan(
                  text: ' ${rich.origText} ',
                  style: TextStyle(color: colorScheme.primary),
                  recognizer: rid != null
                      ? (NoDeadlineTapGestureRecognizer()
                          ..onTap = () => showVoteDialog(Get.context!, rid))
                      : null,
                ),
              ],
            );
          default:
            return TextSpan(
              text:
                  '${rich.type == 'RICH_TEXT_NODE_TYPE_WEB' ? '\u{1F517}' : ''}${item.rich!.text}',
              style: _getStyle(
                rich.style,
                rich.type == 'RICH_TEXT_NODE_TYPE_TEXT'
                    ? null
                    : colorScheme.primary,
              ),
              recognizer: NoDeadlineTapGestureRecognizer()
                ..onTap = () {
                  switch (rich.type) {
                    case 'RICH_TEXT_NODE_TYPE_AT':
                      Get.toNamed('/member?mid=${rich.rid}');
                    // case 'RICH_TEXT_NODE_TYPE_TOPIC':
                    default:
                      if (rich.jumpUrl != null) {
                        PiliScheme.routePushFromUrl(rich.jumpUrl!);
                      }
                  }
                },
            );
        }
      case 'TEXT_NODE_TYPE_FORMULA' when (item.formula != null):
        final latex = item.formula!.latexContent!;
        return WidgetSpan(
          child: CachedNetworkSVGImage(
            cacheKey: latex,
            semanticsLabel: latex,
            '${HttpString.apiBaseUrl}/x/web-frontend/mathjax/tex?formula=${Uri.encodeComponent(latex)}',
            colorFilter: ColorFilter.mode(
              colorScheme.onSurfaceVariant,
              BlendMode.srcIn,
            ),
            alignment: .centerLeft,
            placeholderBuilder: (_) => Text(latex),
            errorBuilder: (_) => Text(latex),
          ),
        );
      default:
        return _getSpan(
          item.word,
          surfaceLuminance: surfaceLuminance,
          defaultColor: isQuote ? colorScheme.onSurfaceVariant : null,
        );
    }
  }

  static TextStyle _getStyle(Style? style, [Color? color, double? fontSize]) =>
      TextStyle(
        decoration: style?.strikethrough == true
            ? TextDecoration.lineThrough
            : null,
        decorationColor: color,
        fontStyle: style?.italic == true ? FontStyle.italic : null,
        fontWeight: style?.bold == true ? .bold : null,
        color: color,
        fontSize: fontSize,
      );

  static TextSpan _getSpan(
    Word? word, {
    Color? defaultColor,
    required ValueGetter<double> surfaceLuminance,
  }) {
    Color? color;
    if (word?.color case final c?) {
      final tmpColor = Color(c);
      double max = tmpColor.computeLuminance();
      double min = surfaceLuminance();
      if (max < min) {
        final tmp = max;
        max = min;
        min = tmp;
      }

      // WCAG AA : (max + 0.05) / (min + 0.05) > 3.0
      if (max > 3.0 * min + 0.1) {
        color = tmpColor;
      }
    }
    return TextSpan(
      text: word?.words,
      style: _getStyle(
        word?.style,
        color ?? defaultColor,
        word?.effectiveFontSize,
      ),
    );
  }

  /// 渲染单个列表项段落
  ///
  /// `theme` 为 `arabic_num` 时用「序号. 」，`dot`（或缺失）用圆点，
  /// 按 `level` 做缩进；正文仍走 [_node2Widget] 以保留加粗、表情、链接。
  static Widget _listItemWidget({
    required ArticleContentModel element,
    required String opusId,
    required ColorScheme colorScheme,
    required ValueGetter<double> surfaceLuminance,
  }) {
    final listFormat = element.format!.listFormat!;
    final level = listFormat.level ?? 1;
    final spans = <InlineSpan>[];
    // theme 缺省按 dot 处理；square/circle 是嵌套层级的循环样式
    switch (listFormat.theme) {
      case 'arabic_num':
        spans.add(TextSpan(text: '${listFormat.order ?? 0}. '));
      case 'roman_num':
        spans.add(TextSpan(text: '${_toRoman(listFormat.order ?? 0)}. '));
      case 'square':
        spans.add(
          const WidgetSpan(
            child: Icon(MdiIcons.squareMedium, size: 10),
            alignment: .middle,
          ),
        );
      case 'circle':
        spans.add(
          const WidgetSpan(
            child: Icon(MdiIcons.circleOutline, size: 12),
            alignment: .middle,
          ),
        );
      default:
        spans.add(
          const WidgetSpan(
            child: Icon(MdiIcons.circleMedium),
            alignment: .middle,
          ),
        );
    }
    if (element.text?.nodes case final nodes?) {
      for (final item in nodes) {
        spans.add(
          _node2Widget(
            item: item,
            opusId: opusId,
            colorScheme: colorScheme,
            surfaceLuminance: surfaceLuminance,
          ),
        );
      }
    }
    return Padding(
      padding: EdgeInsets.only(left: (level - 1).clamp(0, 8) * 16.0),
      child: Text.rich(TextSpan(children: spans)),
    );
  }

  /// 1 → i、4 → iv（roman_num 列表用）
  static String _toRoman(int n) {
    if (n <= 0) return '';
    const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const symbols = [
      'm', 'cm', 'd', 'cd', 'c', 'xc', 'l', 'xl', 'x', 'ix', 'v', 'iv', 'i', //
    ];
    final sb = StringBuffer();
    for (var i = 0; i < values.length; i++) {
      while (n >= values[i]) {
        sb.write(symbols[i]);
        n -= values[i];
      }
    }
    return sb.toString();
  }

  /// 卡片的「封面 + 文字」布局
  ///
  /// 标题或描述为空时自动省略，不再用 `!` 断言——缺字段只会少一行字，
  /// 不会让整段变成红字。
  static Widget _coverCard({
    String? cover,
    String? title,
    required List<String?> descs,
    required ColorScheme colorScheme,
  }) {
    return Row(
      spacing: 10,
      children: [
        NetworkImgLayer(
          width: 104,
          height: 65,
          src: cover,
          borderRadius: const .all(.circular(6)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              if (title?.isNotEmpty == true)
                Text(title!, maxLines: 2, overflow: .ellipsis),
              for (final desc in descs)
                if (desc?.isNotEmpty == true)
                  Text(
                    desc!,
                    maxLines: 2,
                    overflow: .ellipsis,
                    style: TextStyle(fontSize: 13, color: colorScheme.outline),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  /// 通用链接卡片：图标 + 标题 + 链接
  ///
  /// 三处共用：article/view 的卡片没有 `type`；已知类型但 payload 缺失；
  /// 以及 archive/match/reserve 等尚未实现的类型。
  static Widget _genericLinkCard({
    String? showText,
    String? link,
    required ColorScheme colorScheme,
  }) {
    return Row(
      spacing: 10,
      children: [
        Container(
          width: 70,
          height: 50,
          alignment: .center,
          decoration: BoxDecoration(
            borderRadius: const .all(.circular(6)),
            color: colorScheme.secondaryContainer,
          ),
          child: Icon(
            MdiIcons.linkVariant,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            mainAxisAlignment: .center,
            children: [
              Text(
                showText ?? link ?? '链接',
                maxLines: 2,
                overflow: .ellipsis,
              ),
              if (link != null && link.isNotEmpty)
                Text(
                  link,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: TextStyle(fontSize: 13, color: colorScheme.outline),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // if (kDebugMode) debugPrint('opusContent');
    if (opus.isEmpty) {
      return const SliverToBoxAdapter();
    }

    final colorScheme = ColorScheme.of(context);
    late final isDarkMode = colorScheme.isDark;
    double? surfaceLuminance;
    double getSurfaceLuminance() =>
        surfaceLuminance ??= colorScheme.surface.computeLuminance();

    late final highlight = Highlight()..registerLanguages(builtinAllLanguages);

    return SliverListExt.separated(
      reverse: reverse,
      itemCount: opus.length,
      itemBuilder: (context, index) {
        final element = opus[index];
        try {
          switch (element.paraType) {
            case 1 || 4:
              final isQuote = element.paraType == 4;
              List<InlineSpan>? spans;
              if (element.text?.nodes case final nodes?) {
                spans = nodes
                    .map(
                      (item) => _node2Widget(
                        item: item,
                        opusId: opusId,
                        colorScheme: colorScheme,
                        surfaceLuminance: getSurfaceLuminance,
                      ),
                    )
                    .toList();
              } else if (element.blockquote?.children case final children?) {
                spans = [
                  for (final child in children)
                    ...?child.text?.nodes?.map(
                      (item) => _node2Widget(
                        item: item,
                        opusId: opusId,
                        colorScheme: colorScheme,
                        surfaceLuminance: getSurfaceLuminance,
                      ),
                    ),
                ];
              }
              Widget widget = Text.rich(
                textAlign: element.align == 1 ? TextAlign.center : null,
                TextSpan(children: spans),
              );
              if (isQuote) {
                widget = Container(
                  padding: const .only(left: 8, top: 4, right: 4, bottom: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: colorScheme.outlineVariant,
                        width: 4,
                      ),
                    ),
                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                    color: colorScheme.onInverseSurface,
                  ),
                  child: widget,
                );
              }
              return widget;
            case 2 when (element.pic != null):
              final pics = element.pic!.pics!;
              if (pics.length == 1) {
                final pic = pics.first;
                double? width = pic.width == null
                    ? null
                    : math.min(maxWidth, pic.width!);
                final height = width == null || pic.height == null
                    ? null
                    : width * pic.height! / pic.width!;
                width ??= maxWidth;
                Widget child = CachedNetworkImage(
                  width: width,
                  height: height,
                  gaplessPlayback: true,
                  memCacheWidth: width.cacheSize(context),
                  imageUrl: ImageUtils.thumbnailUrl(pic.url!, 60),
                  fadeInDuration: const Duration(milliseconds: 120),
                  fadeOutDuration: const Duration(milliseconds: 120),
                  placeholder: (_, _) => Image.asset(Assets.loading),
                );
                if (!(pic.isLongPic ?? false)) {
                  child = fromHero(
                    tag: '${pic.url!}$hashCode',
                    child: child,
                  );
                }
                final images = this.images();
                return GestureDetector(
                  onTap: () => PageUtils.imageView(
                    imgList: images,
                    initialPage: images.indexWhere((e) => e.url == pic.url),
                    quality: 60,
                    tag: hashCode.toString(),
                  ),
                  child: child,
                );
              } else {
                return ImageGridView(
                  picArr: pics
                      .map(
                        (e) => ImageModel(
                          width: e.width,
                          height: e.height,
                          url: e.url!,
                        ),
                      )
                      .toList(),
                );
              }
            case 3:
              if (element.line?.pic case final pic?) {
                final height = pic.height?.toDouble();
                return CachedNetworkImage(
                  fit: .contain,
                  height: height,
                  width: maxWidth,
                  gaplessPlayback: true,
                  memCacheWidth: maxWidth.cacheSize(context),
                  imageUrl: ImageUtils.thumbnailUrl(pic.url!),
                  placeholder: (_, _) => const SizedBox.shrink(),
                );
              } else {
                return const Divider();
              }
            case 5 when (element.list?.children?.isNotEmpty == true):
              return Text.rich(
                TextSpan(
                  children: element.list!.children!.mapIndexed((i, e) {
                    return TextSpan(
                      children: [
                        const WidgetSpan(
                          child: Icon(MdiIcons.circleMedium),
                          alignment: .middle,
                        ),
                        ...?e.children?.map((child) {
                          return TextSpan(
                            children: child.text?.nodes
                                ?.map(
                                  (item) => _node2Widget(
                                    item: item,
                                    opusId: opusId,
                                    colorScheme: colorScheme,
                                    surfaceLuminance: getSurfaceLuminance,
                                  ),
                                )
                                .toList(),
                          );
                        }),
                        if (i < element.list!.children!.length - 1)
                          const TextSpan(text: '\n'),
                      ],
                    );
                  }).toList(),
                ),
              );
            case 5 when (element.list?.items?.isNotEmpty == true):
              return Text.rich(
                TextSpan(
                  children: element.list!.items!.mapIndexed((i, entry) {
                    return TextSpan(
                      children: [
                        const WidgetSpan(
                          child: Icon(MdiIcons.circleMedium),
                          alignment: .middle,
                        ),
                        // nodes 可能缺失（空列表项），缺了就只留一个标记
                        ...?entry.nodes?.map((item) {
                          if (item.word != null) {
                            return _getSpan(
                              item.word,
                              surfaceLuminance: getSurfaceLuminance,
                            );
                          }
                          if (item.rich case Rich(
                            :final text,
                            :final jumpUrl,
                          )) {
                            final hasUrl =
                                jumpUrl != null && jumpUrl.isNotEmpty;
                            return TextSpan(
                              text: '${hasUrl ? '\u{1F517}' : ''}$text',
                              recognizer: hasUrl
                                  ? (NoDeadlineTapGestureRecognizer()
                                      ..onTap = () =>
                                          PiliScheme.routePushFromUrl(jumpUrl))
                                  : null,
                              style: hasUrl
                                  ? TextStyle(color: colorScheme.primary)
                                  : null,
                            );
                          }
                          return const TextSpan();
                        }),
                        if (i < element.list!.items!.length - 1)
                          const TextSpan(text: '\n'),
                      ],
                    );
                  }).toList(),
                ),
              );
            // 两个接口的 para_type 编号不同（od: 6 卡片/7 代码/8 标题；
            // av: 7 卡片/8 代码/9 标题），所以下面一律按字段判，不按编号。
            case _ when (element.format?.listFormat != null):
              return _listItemWidget(
                element: element,
                opusId: opusId,
                colorScheme: colorScheme,
                surfaceLuminance: getSurfaceLuminance,
              );
            // article/view 的卡片没有 type，只有 link_type/show_text/link，
            // 与 opus/detail 的卡片是两种结构，单独处理
            case _
                when (element.linkCard?.card != null &&
                    element.linkCard!.card!.type == null):
              final card = element.linkCard!.card!;
              return Material(
                shape: const RoundedRectangleBorder(
                  borderRadius: .all(.circular(8)),
                ),
                color: colorScheme.onInverseSurface,
                child: InkWell(
                  borderRadius: const .all(.circular(8)),
                  onTap: card.link == null || card.link!.isEmpty
                      ? null
                      : () => PiliScheme.routePushFromUrl(card.link!),
                  child: Padding(
                    padding: const .all(8),
                    child: _genericLinkCard(
                      showText: card.showText,
                      link: card.link,
                      colorScheme: colorScheme,
                    ),
                  ),
                ),
              );
            // 链接卡片：od 6 / av 7
            case _ when (element.linkCard?.card != null):
              final card = element.linkCard!.card!;
              final type = card.type;
              Widget child;
              // 每种类型都要求自己的 payload 存在，缺失时落到 default 兜底，
              // 不再用 ! 断言（服务端偶尔会 type 与实际字段不一致）
              switch (type) {
                case 'LINK_CARD_TYPE_UGC' when (card.ugc != null):
                  final ugc = card.ugc!;
                  child = _coverCard(
                    cover: ugc.cover,
                    title: ugc.title,
                    descs: [ugc.descSecond],
                    colorScheme: colorScheme,
                  );
                case 'LINK_CARD_TYPE_ITEM_NULL':
                  final itemNull = card.itemNull;
                  child = Text(' ${itemNull?.text}: ${card.oid}');
                case 'LINK_CARD_TYPE_COMMON' when (card.common != null):
                  final common = card.common!;
                  child = _coverCard(
                    cover: common.cover,
                    title: common.title,
                    descs: [common.desc1, common.desc2],
                    colorScheme: colorScheme,
                  );
                case 'LINK_CARD_TYPE_LIVE' when (card.live != null):
                  final live = card.live!;
                  final liveState = live.liveState == 1;
                  child = Row(
                    spacing: 10,
                    children: [
                      // 直播状态角标来自上游 improve opus
                      Stack(
                        clipBehavior: .none,
                        children: [
                          NetworkImgLayer(
                            width: 104,
                            height: 65,
                            src: live.cover,
                            borderRadius: const .all(.circular(6)),
                          ),
                          PBadge(
                            top: 6,
                            right: 6,
                            text: liveState ? '直播中' : '直播结束',
                            type: liveState ? .primary : .gray,
                          ),
                        ],
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: .start,
                          children: [
                            if (live.title?.isNotEmpty == true)
                              Text(
                                live.title!,
                                maxLines: 2,
                                overflow: .ellipsis,
                              ),
                            for (final desc in [live.descFirst, live.descSecond])
                              if (desc?.isNotEmpty == true)
                                Text(
                                  desc!,
                                  maxLines: 1,
                                  overflow: .ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.outline,
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                  );
                case 'LINK_CARD_TYPE_OPUS' when (card.opus != null):
                  final opus = card.opus!;
                  child = _coverCard(
                    cover: opus.cover,
                    title: opus.title,
                    descs: [
                      if (opus.authorName != null)
                        '${opus.authorName} · ${opus.statView ?? 0}阅读',
                    ],
                    colorScheme: colorScheme,
                  );
                case 'LINK_CARD_TYPE_VOTE' when (card.vote != null):
                  final vote = card.vote!;
                  child = Row(
                    spacing: 10,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: const .all(.circular(6)),
                          color: colorScheme.secondaryContainer,
                        ),
                        width: 70,
                        height: 50,
                        alignment: .center,
                        child: Icon(
                          Icons.bar_chart_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: .start,
                          children: [
                            if (vote.desc?.isNotEmpty == true)
                              Text(vote.desc!),
                            Text(
                              '${vote.joinNum}人参与',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                case 'LINK_CARD_TYPE_MUSIC' when (card.music != null):
                  final music = card.music!;
                  child = _coverCard(
                    cover: music.cover,
                    title: music.title,
                    descs: [music.label],
                    colorScheme: colorScheme,
                  );
                case 'LINK_CARD_TYPE_GOODS' when (card.goods != null):
                  final goods = card.goods!;
                  child = Column(
                    children: (goods.items ?? const []).map((e) {
                      return GestureDetector(
                        onTap: () {
                          if (e.jumpUrl?.isNotEmpty == true) {
                            PiliScheme.routePushFromUrl(e.jumpUrl!);
                          }
                        },
                        child: Row(
                          spacing: 10,
                          children: [
                            NetworkImgLayer(
                              width: 104,
                              height: 65,
                              src: e.cover,
                              borderRadius: const .all(.circular(6)),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: .start,
                                children: [
                                  if (e.name?.isNotEmpty == true)
                                    Text(e.name!),
                                  if (e.brief?.isNotEmpty == true)
                                    Text(
                                      e.brief!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colorScheme.outline,
                                      ),
                                    ),
                                  if (e.price?.isNotEmpty == true)
                                    Text(
                                      '${e.price!}起',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colorScheme.outline,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                case "LINK_CARD_TYPE_EVA3_VIDEO"
                    when (card.eva3Video?.info != null):
                  final info = card.eva3Video!.info!;
                  Widget cover = NetworkImgLayer(
                    width: 104,
                    height: 65,
                    src: info.cover,
                    borderRadius: const .all(.circular(6)),
                  );
                  if (info.videoTs?.durationText != null) {
                    cover = Stack(
                      clipBehavior: .none,
                      children: [
                        cover,
                        PBadge(
                          right: 4,
                          bottom: 4,
                          type: .gray,
                          text: info.videoTs?.durationText,
                        ),
                      ],
                    );
                  }
                  child = SizedBox(
                    height: 65,
                    child: Row(
                      spacing: 10,
                      children: [
                        cover,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: .start,
                            mainAxisAlignment: .spaceBetween,
                            children: [
                              if (info.title?.isNotEmpty == true)
                                Text(
                                  info.title!,
                                  maxLines: 2,
                                  overflow: .ellipsis,
                                ),
                              if (info.statInfos case final statInfos?
                                  when statInfos.isNotEmpty)
                                Text(
                                  statInfos.map((e) => e.text).join('    '),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.outline,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                case "LINK_CARD_TYPE_EVA3_OPUS"
                    when (card.eva3Opus?.info != null):
                  final info = card.eva3Opus!.info!;
                  final cover = info.pics?.firstOrNull?.src;
                  child = SizedBox(
                    height: 65,
                    child: Row(
                      spacing: 10,
                      children: [
                        if (cover != null && cover.isNotEmpty)
                          NetworkImgLayer(
                            width: 104,
                            height: 65,
                            src: cover,
                            borderRadius: const .all(.circular(6)),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: .start,
                            mainAxisAlignment: .spaceBetween,
                            children: [
                              if (info.title?.isNotEmpty == true)
                                Text(
                                  info.title!,
                                  maxLines: 2,
                                  overflow: .ellipsis,
                                ),
                              Text.rich(
                                TextSpan(
                                  children:
                                      [
                                            if (info.badge != null)
                                              TextSpan(text: info.badge),
                                            if (info.authorName != null)
                                              TextSpan(
                                                text: 'UP: ${info.authorName!}',
                                              ),
                                            if (info.view != null)
                                              TextSpan(text: info.view!),
                                            if (info.reply != null)
                                              TextSpan(text: info.reply!),
                                          ]
                                          .expand((e) sync* {
                                            yield const TextSpan(text: ' ');
                                            yield e;
                                          })
                                          .skip(1)
                                          .toList(),
                                ),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                // 以下四种卡片由上游 improve opus 引入
                case "LINK_CARD_TYPE_EVA3_USER"
                    when (card.eva3User?.info?.user != null):
                  final info = card.eva3User!.info!;
                  final user = info.user!;
                  child = Row(
                    spacing: 10,
                    children: [
                      NetworkImgLayer(
                        width: 48,
                        height: 48,
                        type: .avatar,
                        src: user.face,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: .start,
                          children: [
                            if (user.name?.isNotEmpty == true)
                              Text(
                                user.name!,
                                maxLines: 1,
                                overflow: .ellipsis,
                              ),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: info.follower),
                                  const TextSpan(text: '   '),
                                  TextSpan(text: info.like),
                                ],
                              ),
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.outline,
                              ),
                            ),
                            if (info.desc?.isNotEmpty == true)
                              Text(
                                info.desc!,
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.outline,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                case "LINK_CARD_TYPE_EVA3_TOY" when (card.eva3Toy?.info != null):
                  final info = card.eva3Toy!.info!;
                  child = SizedBox(
                    height: 65,
                    child: Row(
                      spacing: 10,
                      children: [
                        NetworkImgLayer(
                          width: 65,
                          height: 65,
                          src: info.poster,
                          borderRadius: const .all(.circular(6)),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: .start,
                            mainAxisAlignment: .spaceBetween,
                            children: [
                              if (info.title?.isNotEmpty == true)
                                Text(
                                  info.title!,
                                  maxLines: 2,
                                  overflow: .ellipsis,
                                ),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: info.up?.name),
                                    const TextSpan(text: '   '),
                                    TextSpan(text: info.statText),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                case "LINK_CARD_TYPE_EVA3_VOTE"
                    when (card.eva3Vote?.info != null):
                  final info = card.eva3Vote!.info!;
                  child = Row(
                    spacing: 10,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: const .all(.circular(8)),
                        ),
                        width: 60,
                        height: 42,
                        child: Icon(
                          Icons.bar_chart_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: .start,
                          children: [
                            if (info.title?.isNotEmpty == true)
                              Text(
                                info.title!,
                                maxLines: 1,
                                overflow: .ellipsis,
                              ),
                            Text(
                              '${info.joinNum ?? 0}人参与',
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                case "LINK_CARD_TYPE_EVA3_COMMENT"
                    when (card.eva3Comment?.info != null):
                  final comment = card.eva3Comment!.info!;
                  child = Text(
                    '${comment.linkShowText ?? ''}:\n'
                    '${comment.source?.desc ?? ''}',
                  );
                // 已知类型但 payload 缺失，或属于 archive/match/reserve 等
                // 尚未实现的类型：退回通用链接卡，不再抛异常
                default:
                  child = _genericLinkCard(
                    showText: card.showText,
                    link: card.link,
                    colorScheme: colorScheme,
                  );
              }
              return Material(
                shape: const RoundedRectangleBorder(
                  borderRadius: .all(.circular(8)),
                ),
                color: colorScheme.onInverseSurface,
                child: InkWell(
                  onTap: type == 'LINK_CARD_TYPE_GOODS'
                      ? null
                      : () {
                          try {
                            if (type == 'LINK_CARD_TYPE_VOTE') {
                              final voteId =
                                  card.vote?.voteId ??
                                  int.tryParse(card.oid ?? '');
                              if (voteId != null) {
                                showVoteDialog(context, voteId);
                              }
                              return;
                            }
                            if (type == 'LINK_CARD_TYPE_ITEM_NULL') {
                              final oid = card.oid;
                              if (oid == null) return;
                              showDialog(
                                context: context,
                                builder: (context) => SimpleDialog(
                                  clipBehavior: .hardEdge,
                                  contentPadding: const .symmetric(
                                    vertical: 12,
                                  ),
                                  children: [
                                    DialogOption(
                                      onPressed: () {
                                        final aid = int.tryParse(oid);
                                        if (aid == null) return;
                                        Get.back();
                                        PiliScheme.videoPush(aid, null);
                                      },
                                      child: const Text('视频'),
                                    ),
                                    DialogOption(
                                      onPressed: () {
                                        Get.back();
                                        PageUtils.pushDynFromId(id: oid);
                                      },
                                      child: const Text('动态/专栏'),
                                    ),
                                  ],
                                ),
                              );
                              return;
                            }
                            if (type == 'LINK_CARD_TYPE_EVA3_USER') {
                              final mid = card.eva3User?.info?.user?.mid;
                              if (mid != null && mid.isNotEmpty) {
                                Get.toNamed('/member?mid=$mid');
                              }
                              return;
                            }
                            if (type == 'LINK_CARD_TYPE_EVA3_VOTE') {
                              final voteId = int.tryParse(
                                card.eva3Vote?.info?.voteId ?? '',
                              );
                              if (voteId != null) {
                                showVoteDialog(context, voteId);
                              }
                              return;
                            }
                            final url = switch (type) {
                              'LINK_CARD_TYPE_UGC' => card.ugc?.jumpUrl,
                              'LINK_CARD_TYPE_COMMON' => card.common?.jumpUrl,
                              'LINK_CARD_TYPE_LIVE' => card.live?.jumpUrl,
                              'LINK_CARD_TYPE_OPUS' => card.opus?.jumpUrl,
                              'LINK_CARD_TYPE_MUSIC' => card.music?.jumpUrl,
                              'LINK_CARD_TYPE_EVA3_VIDEO' =>
                                card.eva3Video?.info?.jumpUrl,
                              'LINK_CARD_TYPE_EVA3_OPUS' =>
                                card.eva3Opus?.info?.jumpUrl,
                              'LINK_CARD_TYPE_EVA3_TOY' =>
                                card.eva3Toy?.info?.jumpUri,
                              'LINK_CARD_TYPE_EVA3_COMMENT' =>
                                card.eva3Comment?.resourceUrl,
                              _ => card.link,
                            };
                            if (url != null && url.isNotEmpty) {
                              PiliScheme.routePushFromUrl(url);
                            }
                          } catch (_) {}
                        },
                  borderRadius: const .all(.circular(8)),
                  child: Padding(
                    padding: const .all(8),
                    child: child,
                  ),
                ),
              );
            // 代码块：od 7 / av 8
            case _ when (element.code != null):
              final renderer = TextSpanRenderer(
                null,
                isDarkMode ? githubDarkTheme : githubTheme,
              );
              highlight
                  .highlightAuto(
                    element.code!.content!,
                    element.code!.lang == 'language-clike'
                        ? const ['c', 'java']
                        : [
                            element.code!.lang!
                                .replaceAll('language-', '')
                                .replaceAll('like', ''),
                          ],
                  )
                  .render(renderer);
              return Container(
                padding: const .all(12),
                decoration: BoxDecoration(
                  borderRadius: const .all(.circular(8)),
                  color: colorScheme.onInverseSurface,
                ),
                width: .infinity,
                child: Text.rich(renderer.span!),
              );
            // 文章标题：仅 od 8，两端均无实测样本，保持候选实现
            case _ when (element.heading?.nodes?.isNotEmpty == true):
              return Text.rich(
                TextSpan(
                  children: element.heading!.nodes!
                      .map(
                        (e) => _node2Widget(
                          item: e,
                          opusId: opusId,
                          colorScheme: colorScheme,
                          surfaceLuminance: getSurfaceLuminance,
                        ),
                      )
                      .toList(),
                ),
              );
            // 分级标题：av 9，正文在 text，级别看 heading_type
            case _
                when (element.format?.headingType != null &&
                    element.text?.nodes?.isNotEmpty == true):
              final headingLevel = element.format?.headingType ?? 1;
              return Padding(
                padding: EdgeInsets.only(
                  top: headingLevel <= 1 ? 12 : 8,
                  bottom: 4,
                ),
                child: Semantics(
                  header: true,
                  child: Text.rich(
                    TextSpan(
                      children: element.text!.nodes!
                          .map(
                            (e) => _node2Widget(
                              item: e,
                              opusId: opusId,
                              colorScheme: colorScheme,
                              surfaceLuminance: getSurfaceLuminance,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              );
            default:
              if (kDebugMode) debugPrint('unknown type ${element.paraType}');
              if (element.text?.nodes?.isNotEmpty == true) {
                return Text.rich(
                  textAlign: element.align == 1 ? TextAlign.center : null,
                  TextSpan(
                    children: element.text!.nodes!
                        .map<TextSpan>(
                          (item) => _getSpan(
                            item.word,
                            surfaceLuminance: getSurfaceLuminance,
                          ),
                        )
                        .toList(),
                  ),
                );
              }

              return Text(
                '不支持的类型 (${element.paraType})',
                style: const TextStyle(
                  fontWeight: .bold,
                  color: Colors.red,
                ),
              );
          }
        } catch (e, s) {
          return Text(
            '错误的类型 $e${kDebugMode ? '\n$s' : ''}',
            style: const TextStyle(
              fontWeight: .bold,
              color: Colors.red,
            ),
          );
        }
      },
      separatorBuilder: (context, index) => const SizedBox(height: 10),
    );
  }
}

Widget moduleBlockedItem(
  BuildContext context,
  ColorScheme colorScheme,
  ModuleBlocked moduleBlocked,
) {
  late final isDarkMode = colorScheme.isDark;

  BoxDecoration? bgImg(double width) {
    return moduleBlocked.bgImg == null
        ? null
        : BoxDecoration(
            borderRadius: const .all(.circular(6)),
            border: .all(
              width: 0.8,
              color: isDarkMode
                  ? colorScheme.surfaceContainerHighest
                  : colorScheme.surfaceContainerHigh,
            ),
            image: DecorationImage(
              fit: .fill,
              image: ResizeImage(
                CachedNetworkImageProvider(
                  ImageUtils.thumbnailUrl(
                    isDarkMode
                        ? moduleBlocked.bgImg!.imgDark
                        : moduleBlocked.bgImg!.imgDay,
                  ),
                ),
                width: width.cacheSize(context),
              ),
            ),
          );
  }

  Widget icon(double width) {
    return CachedNetworkImage(
      width: width,
      memCacheWidth: width.cacheSize(context),
      fit: .contain,
      gaplessPlayback: true,
      imageUrl: ImageUtils.thumbnailUrl(
        isDarkMode ? moduleBlocked.icon!.imgDark : moduleBlocked.icon!.imgDay,
      ),
      placeholder: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget btn(
    BuildContext context, {
    OutlinedBorder? shape,
    VisualDensity? visualDensity,
    EdgeInsetsGeometry? padding,
  }) {
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        tapTargetSize: .shrinkWrap,
        visualDensity: visualDensity,
        shape: shape,
        padding: padding,
        foregroundColor: Colors.white,
        backgroundColor: colorScheme.btnColor,
      ),
      onPressed: () {
        if (moduleBlocked.button!.jumpUrl?.isNotEmpty == true) {
          PiliScheme.routePushFromUrl(moduleBlocked.button!.jumpUrl!);
        }
      },
      child: Row(
        mainAxisSize: .min,
        children: [
          if (moduleBlocked.button!.icon?.isNotEmpty == true)
            CachedNetworkImage(
              height: 16,
              color: Colors.white,
              gaplessPlayback: true,
              memCacheHeight: 16.cacheSize(context),
              placeholder: (_, _) => const SizedBox.shrink(),
              imageUrl: ImageUtils.safeThumbnailUrl(moduleBlocked.button!.icon),
            ),
          Text(moduleBlocked.button!.text ?? ''),
        ],
      ),
    );
  }

  if (moduleBlocked.blockedType == 1) {
    return Align(
      alignment: .centerLeft,
      child: LayoutBuilder(
        builder: (context, constraints) {
          var maxWidth = constraints.maxWidth;
          maxWidth = maxWidth <= 255 ? maxWidth : math.min(400, maxWidth * 0.8);
          return Container(
            width: maxWidth,
            height: maxWidth,
            decoration: bgImg(maxWidth),
            padding: const .all(12),
            child: Column(
              mainAxisAlignment: .center,
              children: [
                if (moduleBlocked.icon != null)
                  icon(math.max(40, maxWidth / 7)),
                if (moduleBlocked.hintMessage?.isNotEmpty == true) ...[
                  const SizedBox(height: 5),
                  Text(
                    moduleBlocked.hintMessage!,
                    textAlign: .center,
                    style: TextStyle(color: colorScheme.outline),
                  ),
                ],
                if (moduleBlocked.button != null) ...[
                  const SizedBox(height: 8),
                  btn(
                    context,
                    visualDensity: const VisualDensity(vertical: -2.5),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
  return LayoutBuilder(
    builder: (context, constraints) {
      return Container(
        decoration: bgImg(constraints.maxWidth),
        padding: const .all(12),
        child: Row(
          spacing: 8,
          children: [
            if (moduleBlocked.icon != null) icon(42),
            Expanded(
              child: Column(
                spacing: 2,
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  if (moduleBlocked.title?.isNotEmpty == true)
                    Text(moduleBlocked.title!),
                  if (moduleBlocked.hintMessage?.isNotEmpty == true)
                    Text(
                      moduleBlocked.hintMessage!,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
            if (moduleBlocked.button != null)
              btn(
                context,
                visualDensity: const VisualDensity(
                  vertical: -3,
                  horizontal: -4,
                ),
                shape: const RoundedRectangleBorder(
                  borderRadius: .all(.circular(6)),
                ),
                padding: const .symmetric(horizontal: 10),
              ),
          ],
        ),
      );
    },
  );
}

Widget opusCollection(ColorScheme colorScheme, ModuleCollection item) {
  return Padding(
    padding: const .only(bottom: 10),
    child: Material(
      borderRadius: const .all(.circular(8)),
      color: colorScheme.onInverseSurface,
      child: InkWell(
        borderRadius: const .all(.circular(8)),
        onTap: () => Get.toNamed(
          '/articleList',
          parameters: {'id': '${item.id}'},
        ),
        child: Padding(
          padding: const .all(10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: [
                    Text(item.title!),
                    Text.rich(
                      TextSpan(
                        children: [
                          WidgetSpan(
                            alignment: .middle,
                            child: Icon(
                              size: 18,
                              Icons.article_outlined,
                              color: colorScheme.outline,
                            ),
                          ),
                          TextSpan(
                            text: '${item.name} · ${item.count}',
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.keyboard_arrow_right,
                color: colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
