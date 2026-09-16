/// CubicLM error diagnostics — power-ups for System Logs rows.
///
/// Flutter's own `debugCreator` line truncates the ancestor chain at 12
/// entries (`DebugCreator.toString` → `debugGetCreatorChain(12)` — the ⋯
/// that makes pasted rows unfixable), and many errors (e.g. GetX lint
/// rows) carry an `ErrorDescription` context with no element at all.
/// These helpers recover the FULL untruncated widget path by walking the
/// live element tree, scanning both `details.context` and every
/// `informationCollector` node (the creator node hides there).
///
/// Pure Flutter (no app services) — fully unit-testable. Never throws.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Max ancestors kept in a widget path (nearest first).
const maxChainAncestors = 80;

/// Max stack frames kept in a logged row before collapsing the tail.
const maxLoggedFrames = 60;

/// Full untruncated ancestor widget path for a framework error, nearest
/// first (e.g. `Row ← _LocalModelCard ← ModelView ← ...`). Private widget
/// names survive, so the exact file widget is identifiable from a pasted
/// log row. Falls back to a reason string (never empty, never throws).
String fullCreatorChain(
  FlutterErrorDetails details, [
  Iterable<DiagnosticsNode>? infoNodes,
]) {
  try {
    var tried = 'context=${details.context?.runtimeType ?? 'null'}';
    Element? el = resolveElement(details.context?.value);
    if (el == null) {
      Iterable<DiagnosticsNode>? nodes = infoNodes;
      try {
        nodes ??= details.informationCollector?.call();
      } catch (_) {
        nodes = null;
      }
      if (nodes != null) {
        for (final node in nodes) {
          el = resolveElement(node) ?? resolveElement(node.value);
          if (el != null) {
            tried = 'collector:${node.runtimeType}';
            break;
          }
        }
      }
    }
    if (el == null) return 'unresolved ($tried)';
    final parts = <String>[_elementLabel(el)];
    el.visitAncestorElements((a) {
      if (parts.length >= maxChainAncestors) return false;
      parts.add(_elementLabel(a));
      return true;
    });
    return parts.join(' ← ');
  } catch (_) {
    return 'unresolved (walk threw)';
  }
}

/// Unwrap Element ← DebugCreator ← RenderObject.debugCreator ←
/// DiagnosticsNode.value (recursive — the context shape differs per
/// error kind). Never throws.
Element? resolveElement(Object? node, [int depth = 0]) {
  try {
    if (node == null || depth > 4) return null;
    if (node is Element) return node;
    if (node is DebugCreator) return node.element;
    if (node is RenderObject) {
      return resolveElement(node.debugCreator, depth + 1);
    }
    if (node is DiagnosticsNode) {
      return resolveElement(node.value, depth + 1);
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// `runtimeType` plus key when present (keys disambiguate list items).
String elementLabel(Element e) {
  try {
    final k = e.widget.key;
    if (k == null) return e.widget.runtimeType.toString();
    return '${e.widget.runtimeType} key=$k';
  } catch (_) {
    try {
      return e.widget.runtimeType.toString();
    } catch (_) {
      return 'Element';
    }
  }
}

String _elementLabel(Element e) => elementLabel(e);

/// Screen environment layout errors depend on: logical size, DPR,
/// text scaler, orientation, platform. Context-free (safe mid-build).
/// Never throws.
String diagnosticEnv() {
  try {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    if (dispatcher.views.isEmpty) return 'view: unavailable';
    final v = dispatcher.views.first;
    final w = v.physicalSize.width / v.devicePixelRatio;
    final h = v.physicalSize.height / v.devicePixelRatio;
    final orient = w >= h ? 'landscape' : 'portrait';
    return 'window: ${w.toStringAsFixed(0)}x${h.toStringAsFixed(0)} logical '
        '($orient), dpr: ${v.devicePixelRatio}, '
        'textScale: ${dispatcher.textScaleFactor}, '
        'platform: ${defaultTargetPlatform.name}';
  } catch (_) {
    return 'view: unavailable';
  }
}

/// Collapse giant stacks (GetX rows ship 500+ mount frames) to the first
/// [maxFrames] `#N` lines plus a `[... N more frames]` marker. Crash
/// reporters still receive the full `details`; only the logged row is
/// trimmed so copy/paste stays usable. Never throws.
String trimStack(StackTrace? stack, {int maxFrames = maxLoggedFrames}) {
  try {
    if (stack == null) return 'No stack';
    final lines = stack.toString().split('\n');
    final head = lines.takeWhile((l) => !l.startsWith('#')).toList();
    final frames = lines.where((l) => l.startsWith('#')).toList();
    if (frames.length <= maxFrames) return stack.toString().trimRight();
    final kept = [...head, ...frames.take(maxFrames)];
    return '${kept.join('\n')}\n[... ${frames.length - maxFrames} more frames]';
  } catch (_) {
    return 'No stack';
  }
}
