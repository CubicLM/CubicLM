import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'device_info_apps_row.dart';

/// Memoized app list: filtering/sorting over the full snapshot runs
/// ONLY when the source identity, search query, sort mode, or filter
/// changes — never per tick or per unrelated rebuild.
///
/// Cache key: identical(apps) + query + sortMode + filter. The parent
/// shell passes the static snapshot once (outside any ticking Obx);
/// local filter/search state lives here via plain setState/props, so
/// the 2s paintVersion/ramHistory/battLive ticks never retrigger it.
///
/// Rendering is always [ListView.builder] (never a Column with
/// hundreds of children) so only visible rows build icons/layout.
class MemoizedAppList extends StatefulWidget {
  /// Static snapshot from the controller (read once after loading).
  final List<Map<String, dynamic>> apps;

  /// 0 user, 1 system, 2 all.
  final int filter;

  /// Search query (case-insensitive substring over label + package).
  /// Defaults to '' (no filtering) to preserve original behavior.
  final String query;

  /// 0 = original order, 1 = name A–Z, 2 = size descending.
  /// Defaults to 0 to preserve original behavior.
  final int sortMode;

  final void Function(Map<String, dynamic> app) onTapApp;

  const MemoizedAppList({
    super.key,
    required this.apps,
    required this.filter,
    required this.onTapApp,
    this.query = '',
    this.sortMode = 0,
  });

  @override
  State<MemoizedAppList> createState() => _MemoizedAppListState();
}

class _MemoizedAppListState extends State<MemoizedAppList> {
  List<Map<String, dynamic>>? _lastSource;
  String? _lastQuery;
  int? _lastSort;
  int? _lastFilter;
  List<Map<String, dynamic>> _cached = const [];

  List<Map<String, dynamic>> _filtered() {
    if (identical(widget.apps, _lastSource) &&
        widget.query == _lastQuery &&
        widget.sortMode == _lastSort &&
        widget.filter == _lastFilter) {
      return _cached;
    }
    final q = widget.query.trim().toLowerCase();
    final out = <Map<String, dynamic>>[];
    for (final a in widget.apps) {
      final isSystem = a['isSystem'] == true;
      if (widget.filter == 0 && isSystem) continue;
      if (widget.filter == 1 && !isSystem) continue;
      if (q.isNotEmpty) {
        final label = '${a['label'] ?? ''}'.toLowerCase();
        final pkg = '${a['package'] ?? ''}'.toLowerCase();
        if (!label.contains(q) && !pkg.contains(q)) continue;
      }
      out.add(a);
    }
    if (widget.sortMode == 1) {
      out.sort((a, b) =>
          '${a['label'] ?? a['package'] ?? ''}'.compareTo(
              '${b['label'] ?? b['package'] ?? ''}'));
    } else if (widget.sortMode == 2) {
      out.sort((a, b) => (((b['apkBytes'] as num?)?.toInt() ?? 0))
          .compareTo((a['apkBytes'] as num?)?.toInt() ?? 0));
    }
    _lastSource = widget.apps;
    _lastQuery = widget.query;
    _lastSort = widget.sortMode;
    _lastFilter = widget.filter;
    _cached = out;
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered();
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No apps in this filter.',
            style: GoogleFonts.plusJakartaSans(
                color: Theme.of(context).hintColor)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final row = Map<String, dynamic>.from(items[i]);
        return AppListRow(
            app: row, onTap: () => widget.onTapApp(row));
      },
    );
  }
}
