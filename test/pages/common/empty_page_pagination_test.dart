import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用脚本化的分页数据验证「空页是否等于没有更多了」
class _ListCtrl extends CommonListController<List<int>, int> {
  _ListCtrl(this.pages, {this.limit = 1});

  /// 按 page 依次返回的数据，超出范围一律视为空页
  final List<List<int>> pages;
  final int limit;
  int requests = 0;

  @override
  int get emptyPageLimit => limit;

  @override
  Future<LoadingState<List<int>>> customGetData() async {
    requests++;
    final index = page - 1;
    return Success(index < pages.length ? pages[index] : const <int>[]);
  }
}

void main() {
  group('空页与「没有更多了」', () {
    test('默认行为：一页取空就结束，不再翻页', () async {
      final c = _ListCtrl([
        [1, 2],
        <int>[],
        [3], // 默认限制下不应该被取到
      ]);

      await c.queryData();
      expect(c.loadingState.value.data, [1, 2]);
      expect(c.isEnd, isFalse);
      expect(c.page, 2);

      await c.queryData(false); // 第 2 页空
      expect(c.isEnd, isTrue);
      expect(c.page, 2, reason: '结束时不推进页码');
      expect(c.loadingState.value.data, [1, 2], reason: '已有数据不受影响');

      await c.queryData(false);
      expect(c.requests, 2, reason: 'isEnd 之后不应再请求');
    });

    test('放宽限制后：空页只是跳过，继续取下一页', () async {
      final c = _ListCtrl([
        [1, 2],
        <int>[],
        <int>[],
        [3],
      ], limit: 3);

      await c.queryData();
      expect(c.page, 2);

      await c.queryData(false); // 第 2 页空
      expect(c.isEnd, isFalse);
      expect(c.page, 3, reason: '空页要推进页码，否则会重复请求同一页');
      expect(c.requests, 2);

      await c.queryData(false); // 第 3 页空
      expect(c.isEnd, isFalse);
      expect(c.page, 4);

      await c.queryData(false); // 第 4 页有数据
      expect(c.loadingState.value.data, [1, 2, 3]);
      expect(c.isEnd, isFalse);
      expect(c.page, 5);
    });

    test('连续空页达到限制才认定到底', () async {
      final c = _ListCtrl([<int>[], <int>[], <int>[]], limit: 3);

      await c.queryData(); // 第 1 页空
      expect(c.isEnd, isFalse);
      expect(c.page, 2);

      await c.queryData(false); // 第 2 页空
      expect(c.isEnd, isFalse);
      expect(c.page, 3);

      await c.queryData(false); // 第 3 页空，达到限制
      expect(c.isEnd, isTrue);
      expect(c.page, 3);
    });

    test('取到非空页会重置连续空页计数', () async {
      final c = _ListCtrl([
        [1],
        <int>[],
        [2],
        <int>[],
        <int>[],
      ], limit: 2);

      await c.queryData(); // 第 1 页
      await c.queryData(false); // 第 2 页空，计数 1
      expect(c.isEnd, isFalse);
      await c.queryData(false); // 第 3 页有数据，计数清零
      expect(c.isEnd, isFalse);
      expect(c.loadingState.value.data, [1, 2]);
      await c.queryData(false); // 第 4 页空，计数 1
      expect(c.isEnd, isFalse, reason: '中间取到过数据，不该累积到上限');
      await c.queryData(false); // 第 5 页空，计数 2 -> 结束
      expect(c.isEnd, isTrue);
    });

    test('刷新会重置页码、连续空页计数与已有数据', () async {
      final c = _ListCtrl([
        [1],
        <int>[],
        [2],
      ], limit: 2);

      await c.queryData();
      await c.queryData(false); // 第 2 页空，计数 1
      expect(c.page, 3);
      expect(c.isEnd, isFalse);

      await c.onRefresh(); // 回到第 1 页重新取
      expect(c.isEnd, isFalse);
      expect(c.page, 2, reason: '刷新后从第一页开始，并推进到第二页');
      expect(c.loadingState.value.data, [1], reason: '刷新应替换而不是累加');
    });
  });
}
