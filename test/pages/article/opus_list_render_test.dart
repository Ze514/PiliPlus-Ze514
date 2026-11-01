import 'package:PiliPlus/models/dynamics/article_content_model.dart';
import 'package:PiliPlus/pages/article/widgets/opus_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

/// 构造新版专栏的列表项段落：没有 list / link_card，只有 format.list_format
ArticleContentModel _listItem({
  required String theme,
  required int order,
  int level = 1,
}) => ArticleContentModel.fromJson({
  // dot 对应无序列表（para_type 6），arabic_num 对应有序列表（para_type 5）
  'para_type': theme == 'dot' ? 6 : 5,
  'format': {
    'list_format': {'level': level, 'order': order, 'theme': theme},
    'combine_hash': 'list_1_abc',
  },
  'text': {
    'nodes': [
      {
        'node_type': 1,
        'word': {
          'words': '连续：',
          'font_size': 17,
          'style': {'bold': true},
          'font_level': 'regular',
        },
      },
      {
        'node_type': 1,
        'word': {'words': '正文内容', 'font_size': 17, 'font_level': 'regular'},
      },
    ],
  },
});

Widget _app(List<ArticleContentModel> opus) => MaterialApp(
  home: Scaffold(
    body: CustomScrollView(
      slivers: [
        OpusContent(
          opus: opus,
          images: () => const [],
          maxWidth: 360,
          opusId: '53698541',
          reverse: false,
        ),
      ],
    ),
  ),
);

void main() {
  group('专栏列表项解析', () {
    test('para_type=6 的列表项有 listFormat 且没有 linkCard', () {
      final item = _listItem(theme: 'dot', order: 3);

      expect(item.paraType, 6);
      // 旧代码在这里做 element.linkCard! 于是抛空指针
      expect(item.linkCard, isNull);
      expect(item.format?.listFormat?.theme, 'dot');
      expect(item.format?.listFormat?.level, 1);
      expect(item.format?.listFormat?.order, 3);
    });

    test('para_type=5 的列表项没有 list 字段', () {
      final item = _listItem(theme: 'arabic_num', order: 2);

      expect(item.paraType, 5);
      expect(item.list, isNull);
      expect(item.format?.listFormat?.theme, 'arabic_num');
      expect(item.format?.listFormat?.order, 2);
    });
  });

  group('专栏列表项渲染', () {
    testWidgets('para_type=6 渲染为列表项，不再出现错误文案', (tester) async {
      await tester.pumpWidget(_app([_listItem(theme: 'dot', order: 1)]));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('错误的类型', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('连续：', findRichText: true),
        findsOneWidget,
      );
      // 圆点标记
      expect(find.byIcon(MdiIcons.circleMedium), findsOneWidget);
    });

    testWidgets('para_type=5 的阿拉伯数字列表项带序号', (tester) async {
      await tester.pumpWidget(_app([_listItem(theme: 'arabic_num', order: 2)]));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('错误的类型', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('2. ', findRichText: true), findsOneWidget);
    });

    testWidgets('link_card 缺失且没有 list_format 时退回纯文本', (tester) async {
      final orphan = ArticleContentModel.fromJson({
        'para_type': 6,
        'text': {
          'nodes': [
            {
              'node_type': 1,
              'word': {'words': '没有卡片也没有列表格式', 'font_size': 17},
            },
          ],
        },
      });

      await tester.pumpWidget(_app([orphan]));
      await tester.pumpAndSettle();

      // 不应抛异常，内容也不能被吞掉
      expect(
        find.textContaining('错误的类型', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('没有卡片也没有列表格式', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('专栏标题渲染', () {
    testWidgets('para_type=9 带标题语义且不报错', (tester) async {
      final heading = ArticleContentModel.fromJson({
        'para_type': 9,
        'format': {
          'indent': {},
          'heading_type': 1,
        },
        'text': {
          'nodes': [
            {
              'node_type': 1,
              'word': {
                'words': '1. Super-agent',
                'font_size': 24,
                'font_level': 'xxLarge',
              },
            },
          ],
        },
      });

      await tester.pumpWidget(_app([heading]));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('错误的类型', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('不支持的类型', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('1. Super-agent', findRichText: true),
        findsOneWidget,
      );
      // 标题语义：读屏能识别为 heading
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.header == true,
        ),
        findsOneWidget,
      );
    });

    test('heading_type 能解析出来', () {
      final h1 = ArticleContentModel.fromJson({
        'para_type': 9,
        'format': {'heading_type': 1},
        'text': {
          'nodes': [
            {
              'node_type': 1,
              'word': {'words': 'A'},
            },
          ],
        },
      });
      final h2 = ArticleContentModel.fromJson({
        'para_type': 9,
        'format': {'heading_type': 2},
        'text': {
          'nodes': [
            {
              'node_type': 1,
              'word': {'words': 'B'},
            },
          ],
        },
      });

      expect(h1.format?.headingType, 1);
      expect(h2.format?.headingType, 2);
      // 普通段落不应带 headingType
      expect(_listItem(theme: 'dot', order: 1).format?.headingType, isNull);
    });
  });
}
