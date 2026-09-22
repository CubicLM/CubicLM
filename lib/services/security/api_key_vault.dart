/// CubicLM Security — hardware-backed API key vault facade.
///
/// [SecureKeyStore] (flutter_secure_storage → Android Keystore / iOS
/// Keychain / Windows DPAPI) already holds the keys. This vault adds:
/// - a backend abstraction so key logic is unit-testable (memory backend),
/// - a one-shot migration helper for legacy plaintext maps,
/// - a single place for future Keystore-direct (AES-256-GCM) bridging.
///
/// No plaintext key may live in Hive after migration; the vault is the only
/// writer.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

/// Storage backend contract.
abstract class VaultBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}

/// Production backend: platform secure storage.
class SecureStorageBackend implements VaultBackend {
  final FlutterSecureStorage _storage;
  final String prefix;

  SecureStorageBackend(
      {FlutterSecureStorage? storage, this.prefix = 'clm_key_'})
      : _storage = storage ?? const FlutterSecureStorage();

  void _log(String op, Object e) {
    debugPrint('[ApiKeyVault] $op failed: $e');
  }

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: '$prefix$key');
    } catch (e) {
      _log('read($key)', e);
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      if (value.isEmpty) {
        await _storage.delete(key: '$prefix$key');
      } else {
        await _storage.write(key: '$prefix$key', value: value);
      }
    } catch (e) {
      _log('write($key)', e);
    }
  }

  @override
  Future<void> delete(String key) => write(key, '');

  @override
  Future<Map<String, String>> readAll() async {
    try {
      final all = await _storage.readAll();
      final out = <String, String>{};
      for (final e in all.entries) {
        if (e.key.startsWith(prefix)) {
          out[e.key.substring(prefix.length)] = e.value;
        }
      }
      return out;
    } catch (e) {
      _log('readAll', e);
      return {};
    }
  }
}

/// In-memory backend for unit tests (never touches platform channels).
class MemoryVaultBackend implements VaultBackend {
  final Map<String, String> _map = {};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      _map.remove(key);
    } else {
      _map[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async {
    _map.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(_map);
}

/// API key vault (registered in main deferred init).
class ApiKeyVault extends GetxService {
  final VaultBackend _backend;
  final Map<String, String> _cache = {};
  bool _loaded = false;

  ApiKeyVault({VaultBackend? backend})
      : _backend = backend ?? SecureStorageBackend();

  Future<ApiKeyVault> init() async {
    await refresh();
    return this;
  }

  /// Reload the in-memory cache from the backend.
  Future<void> refresh() async {
    try {
      _cache
        ..clear()
        ..addAll(await _backend.readAll());
      _loaded = true;
    } catch (_) {}
  }

  bool get isLoaded => _loaded;

  /// Read a key ('' when absent — never throws).
  String read(String key) => _cache[key] ?? '';

  bool has(String key) => read(key).isNotEmpty;

  /// Write a key (empty value deletes). Never throws.
  Future<void> put(String key, String value) async {
    final v = value.trim();
    if (v.isEmpty) {
      _cache.remove(key);
    } else {
      _cache[key] = v;
    }
    try {
      await _backend.write(key, v);
    } catch (_) {}
  }

  Future<void> delete(String key) => put(key, '');

  /// Migrate a legacy plaintext map (e.g. Hive leftovers) into the vault.
  /// Returns the number of keys migrated. Never throws.
  Future<int> migrateFromMap(Map<String, String> legacy) async {
    var moved = 0;
    for (final e in legacy.entries) {
      try {
        if (e.value.trim().isEmpty) continue;
        if (has(e.key)) continue;
        await put(e.key, e.value);
        moved++;
      } catch (_) {}
    }
    return moved;
  }
}
