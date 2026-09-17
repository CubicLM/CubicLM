import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app_log_service.dart';
import 'hive_service.dart';

/// Persistent user-fact memory with full CRUD and enable/disable toggle.
class MemoryService extends GetxService {
  late Box<String> _memoryBox;
  static const String boxName = 'user_memory';
  static const String _kEnabledKey = 'memory_enabled';

  /// Reactive list of `{'key': timestampKey, 'fact': text}`.
  final memories = <Map<String, String>>[].obs;

  /// Whether memory injection is enabled.
  final isEnabled = true.obs;

  Future<MemoryService> init() async {
    _memoryBox = await Hive.openBox<String>(boxName);
    _loadAll();
    // Restore enabled state from settings.
    try {
      final hive = Get.find<HiveService>();
      isEnabled.value =
          hive.getSetting<bool>(_kEnabledKey, defaultValue: true) ?? true;
    } catch (_) {}
    return this;
  }

  void _loadAll() {
    final list = <Map<String, String>>[];
    for (final key in _memoryBox.keys) {
      final fact = _memoryBox.get(key);
      if (fact != null && fact.trim().isNotEmpty) {
        list.add({'key': key.toString(), 'fact': fact});
      }
    }
    // Newest first.
    list.sort((a, b) => b['key']!.compareTo(a['key']!));
    memories.assignAll(list);
  }

  int get memoryCount => memories.length;

  List<String> getAllMemories() => _memoryBox.values.toList();

  /// Returns memories with keys and parsed timestamps for the UI.
  List<({String key, String fact, DateTime createdAt})> getMemoriesWithKeys() {
    return memories.map((m) {
      final ms = int.tryParse(m['key'] ?? '') ?? 0;
      return (
        key: m['key']!,
        fact: m['fact']!,
        createdAt: DateTime.fromMillisecondsSinceEpoch(ms),
      );
    }).toList();
  }

  Future<void> addMemory(String fact) async {
    if (fact.trim().isEmpty) return;
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await _memoryBox.put(key, fact.trim());
    _loadAll();
    Get.find<AppLogService>()
        .info('New memory stored: $fact', category: LogCategory.system);
  }

  Future<void> updateMemory(String key, String newFact) async {
    if (newFact.trim().isEmpty) return;
    await _memoryBox.put(key, newFact.trim());
    _loadAll();
  }

  Future<void> deleteMemory(String key) async {
    await _memoryBox.delete(key);
    _loadAll();
  }

  Future<void> clearMemories() async {
    await _memoryBox.clear();
    _loadAll();
  }

  Future<void> toggleEnabled(bool value) async {
    isEnabled.value = value;
    try {
      await Get.find<HiveService>().setSetting(_kEnabledKey, value);
    } catch (_) {}
  }

  /// Injects memories into the system prompt (only if enabled).
  String injectMemories(String basePrompt) {
    if (!isEnabled.value) return basePrompt;
    final all = getAllMemories();
    if (all.isEmpty) return basePrompt;

    final buffer = StringBuffer(basePrompt);
    buffer.writeln('\n\n[User Context & Information]');
    for (final m in all) {
      buffer.writeln('- $m');
    }
    return buffer.toString();
  }
}
