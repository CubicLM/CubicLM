/// NavigatorObserver that records every route push/pop (pages, dialogs,
/// bottom sheets) into the log service route trail. Split from `app_log_service.dart`.
///
/// Behavior is unchanged.
/// Contains: labelOf(), _record(), didPush(), didPop(), didReplace()
library;

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'app_log_service.dart';

/// NavigatorObserver that records every route push/pop (pages, dialogs,
/// bottom sheets) into the log service's route trail. Sheets never call
/// trackScreen, so this is what names the open sheet when a layout row
/// fires. Zero log rows — only the bounded trail buffer. Never throws.
class LogRouteObserver extends NavigatorObserver {
  /// Friendly label: `_GetModalBottomSheet<dynamic>` → `BottomSheet`,
  /// `DialogRoute<T>` → `Dialog`, named pages keep their route name.
  static String labelOf(Route? route) {
    try {
      if (route == null) return 'null';
      final name = route.settings.name;
      var t = route.runtimeType.toString();
      // Strip generics: _GetModalBottomSheet<dynamic> → _GetModalBottomSheet
      final tick = t.indexOf('<');
      if (tick >= 0) t = t.substring(0, tick);
      String label;
      if (t.contains('ModalBottomSheet')) {
        label = 'BottomSheet';
      } else if (t.contains('Dialog')) {
        label = 'Dialog';
      } else if (t.contains('PopupMenu')) {
        label = 'PopupMenu';
      } else if (t.startsWith('_')) {
        label = t;
      } else {
        label = t
            .replaceAll('GetPageRoute', 'Page')
            .replaceAll('MaterialPageRoute', 'Page')
            .replaceAll('CupertinoPageRoute', 'Page');
      }
      if (name != null && name.isNotEmpty && name != '/') {
        label = '$label($name)';
      }
      return label;
    } catch (_) {
      return 'route';
    }
  }

  void _record(String arrow, Route? route) {
    try {
      if (Get.isRegistered<AppLogService>()) {
        Get.find<AppLogService>().trailRoute('$arrow ${labelOf(route)}');
      }
    } catch (_) {}
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    _record('→', route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _record('←', route);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    _record('→', newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
