import 'package:flutter/foundation.dart';

/// 全局数据变更通知器。
///
/// 任何写库操作完成后（同步、扫描、导入等）调用 [notifyDataChanged]，
/// 首页 / 查询页等页面监听后重新加载数据。
class DataChangeNotifier extends ChangeNotifier {
  DataChangeNotifier._();

  static final DataChangeNotifier instance = DataChangeNotifier._();

  void notifyDataChanged() => notifyListeners();
}