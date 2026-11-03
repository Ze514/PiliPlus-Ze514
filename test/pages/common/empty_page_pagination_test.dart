import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用脚本化的分页数据验证 `endIfNullOrEmpty` 的语义：
/// 取到空页时是否直接认定「没有更多了」。
///
/// 回复列表把 `endIfNullOrEmpty` 覆盖为 false —— 屏蔽词过滤发生在取数阶段，
/// 整页被删空不代表到底，要继续往后翻。
class _ListCtrl extends CommonListController<List<int>, int> {
  _ListCtrl(this.pages, {required this.endIfEmpty});

  /// 按 cursor 依次返回的数据，超出范围一律视为空页
  final List<List<int>> pages;
  final bool endIfEmpty;

  int requests = 0;
  int cursor = 0;

  @override
  bool get endIfNullOrEmpty => endIfEmpty;

  @override
  Future<LoadingState<List<int>>> customGetData() async {
    requests++;
    final index = cursor++;
    return Success(index < pages.length ? pages[index] : const <int>[]);
  }

  @override
  Future<void> onRefresh() {
    cursor = 0;
    return super.onRefresh();
  }
}

void main() {
  group('空页与「没有更多了」', () {
    test('默认行为：一页取空就结束，不再翻页', () async {
      final c = _ListCtrl([
        [1, 2],
        <int>[],
        [3], // 默认行为下不应该被取到
      ], endIfEmpty: true);

      await c.queryData();
      expect(c.loadingState.value.data, [1, 2]);
      expect(c.isEnd, isFalse);

      await c.queryData(false); // 第 2 页空
      expect(c.isEnd, isTrue);
      expect(c.loadingState.value.data, [1, 2], reason: '已有数据不受影响');

      await c.queryData(false);
      expect(c.requests, 2, reason: 'isEnd 之后不应再请求');
    });

    test('endIfNullOrEmpty = false：空页只是跳过，继续取下一页', () async {
      final c = _ListCtrl([
        [1, 2],
        <int>[],
        <int>[],
        [3],
      ], endIfEmpty: false);

      await c.queryData();
      expect(c.isEnd, isFalse);

      await c.queryData(false); // 第 2 页空
      expect(c.isEnd, isFalse, reason: '被过滤空的一页不代表到底');

      await c.queryData(false); // 第 3 页仍然空
      expect(c.isEnd, isFalse);

      await c.queryData(false); // 第 4 页有数据
      expect(c.loadingState.value.data, [1, 2, 3]);
      expect(c.isEnd, isFalse);
      expect(c.requests, 4);
    });

    test('刷新会重置 isEnd，从第一页重新取', () async {
      final c = _ListCtrl([
        [1],
        <int>[],
      ], endIfEmpty: true);

      await c.queryData();
      await c.queryData(false);
      expect(c.isEnd, isTrue);

      await c.onRefresh();
      expect(c.isEnd, isFalse);
      expect(c.loadingState.value.data, [1], reason: '刷新应替换而不是累加');
    });
  });
}
