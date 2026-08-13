import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:easy_memory/services/data_change_notifier.dart';
import 'package:easy_memory/services/device_config.dart';

void main() {
  group('DeviceConfig.defaultLabel', () {
    test('returns a non-empty, readable default on every platform', () {
      final label = DeviceConfig.defaultLabel();
      expect(label, isNotEmpty);
      // 平台可读名永远不会退化成 Android 的 "localhost"。
      expect(label, isNot('localhost'));
    });
  });

  group('DataChangeNotifier', () {
    test('notifies listeners on notifyDataChanged', () {
      var calls = 0;
      void listener() => calls++;

      DataChangeNotifier.instance.addListener(listener);
      DataChangeNotifier.instance.notifyDataChanged();
      DataChangeNotifier.instance.notifyDataChanged();
      DataChangeNotifier.instance.removeListener(listener);

      expect(calls, 2);

      // 移除后不再收到通知。
      DataChangeNotifier.instance.notifyDataChanged();
      expect(calls, 2);
    });

    test('listeners that call notifyListeners do not deadlock', () {
      // notifyListeners is synchronous; reentrancy is safe in ChangeNotifier.
      var inner = false;
      void listener() {
        if (!inner) {
          inner = true;
          DataChangeNotifier.instance.notifyDataChanged();
        }
      }

      DataChangeNotifier.instance.addListener(listener);
      DataChangeNotifier.instance.notifyDataChanged();
      DataChangeNotifier.instance.removeListener(listener);
      expect(inner, true);
    });
  });

  test('kIsWeb still resolvable (foundation import sanity)', () {
    expect(kIsWeb, isA<bool>());
  });
}