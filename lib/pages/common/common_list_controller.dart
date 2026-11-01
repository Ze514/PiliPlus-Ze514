import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:get/get.dart';

abstract class CommonListController<R, T> extends CommonController<R, T> {
  int page = 1;
  bool isEnd = false;
  bool get hasFooter => false;

  @override
  Rx<LoadingState<List<T>?>> loadingState =
      LoadingState<List<T>?>.loading().obs;

  void handleListResponse(List<T> dataList) {}

  List<T>? getDataList(R response) {
    return response as List<T>?;
  }

  void checkIsEnd(int length) {}

  /// 连续多少页取到空数据才认定「没有更多了」。
  ///
  /// 回复列表的屏蔽词过滤发生在取数阶段，一整页可能被删空；那种空页不代表
  /// 到底，需要继续往后翻，否则会漏掉后面的内容。其它列表维持默认值。
  int get emptyPageLimit => 1;

  int _emptyPageStreak = 0;

  @override
  Future<void> queryData([bool isRefresh = true]) async {
    if (isLoading || (!isRefresh && isEnd)) return;
    isLoading = true;
    final LoadingState<R> res = await customGetData();
    if (res case Success(:final response)) {
      if (!customHandleResponse(isRefresh, res)) {
        final dataList = getDataList(response);
        if (dataList == null || dataList.isEmpty) {
          if (++_emptyPageStreak >= emptyPageLimit) {
            isEnd = true;
          }
          if (isRefresh) {
            loadingState.value = Success(dataList);
          } else if (hasFooter) {
            loadingState.refresh();
          }
          if (isEnd) {
            isLoading = false;
            return;
          }
          // 这一页只是被过滤空了，继续翻下一页；page 不推进会重复请求同一页
          page++;
          isLoading = false;
          return;
        }
        _emptyPageStreak = 0;
        handleListResponse(dataList);
        if (isRefresh) {
          checkIsEnd(dataList.length);
          loadingState.value = Success(dataList);
        } else if (loadingState.value case Success(:final response)) {
          response!.addAll(dataList);
          checkIsEnd(response.length);
          loadingState.refresh();
        }
      }
      page++;
    } else {
      if (isRefresh && !handleError(res is Error ? res.errMsg : null)) {
        loadingState.value = res as Error;
      }
    }
    isLoading = false;
  }

  @override
  Future<void> onRefresh() {
    page = 1;
    isEnd = false;
    _emptyPageStreak = 0;
    return super.onRefresh();
  }

  @override
  Future<void> onReload() {
    loadingState.value = LoadingState<List<T>?>.loading();
    return super.onReload();
  }
}
