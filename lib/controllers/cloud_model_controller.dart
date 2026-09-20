import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../utils/app_snackbar.dart';
import '../services/app_log_service.dart';
import '../services/cloud/cloud_provider_registry.dart';
import '../services/cloud/model_health.dart';
import '../services/cloud_service.dart';
import '../services/hive_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import 'settings_controller.dart';
import '../models/cloud_provider_info.dart';
part 'cloud_providers.dart';
part 'cloud_models.dart';
part 'cloud_health.dart';
part 'cloud_sync_parse.dart';

class CloudModelController extends GetxController {
  final HiveService _hive = Get.find<HiveService>();
  final SettingsController _settings = Get.find<SettingsController>();

  static const _cachePrefix = 'cloud_model_cache_';
  static const _cacheTimePrefix = 'cloud_model_cache_time_';
  static const _workingUrlPrefix = 'cloud_model_working_url_';
  static const _discoveredProvidersKey = 'cloud_discovered_providers';
  static const _healthPrefix = 'cloud_model_health_';
  static const _autoHideKey = 'cloud_auto_hide_failed';
  static const _syncIntervalKey = 'cloud_sync_interval_hours';
  static const _lastAutoSyncKey = 'cloud_last_auto_sync';
  static const _keyTimePrefix = 'cloud_key_set_at_';
  static const _pinnedKey = 'cloud_pinned_providers';
  static const _sortModeKey = 'cloud_provider_sort';

  static const _knownCompanyIcons = <String, IconData>{
    'openai': Icons.auto_awesome,
    'anthropic': Icons.psychology_outlined,
    'google': Icons.diamond_outlined,
    'meta': Icons.tag,
    'meta-llama': Icons.tag,
    'mistral': Icons.water_outlined,
    'mistralai': Icons.water_outlined,
    'nvidia': Icons.memory_outlined,
    'deepseek': Icons.psychology_alt_outlined,
    'xiaomi': Icons.phone_android,
    'qwen': Icons.smart_toy_outlined,
    'microsoft': Icons.window,
    'cohere': Icons.workspaces_outlined,
    'alibaba': Icons.storefront_outlined,
    'amazon': Icons.shopping_bag_outlined,
    'huggingface': Icons.emoji_emotions_outlined,
    'ibm': Icons.computer_outlined,
    'databricks': Icons.analytics_outlined,
    'minimax': Icons.tune,
    '01': Icons.looks_one_outlined,
    'moonshot': Icons.nightlight_round,
    'zhipu': Icons.account_balance,
    'yi': Icons.hourglass_bottom,
    'dbrx': Icons.route,
    'command': Icons.record_voice_over,
    'gemma': Icons.diamond_outlined,
    'phi': Icons.science_outlined,
    'stability': Icons.photo_library_outlined,
    'midjourney': Icons.brush_outlined,
    'flux': Icons.flutter_dash_outlined,
  };

  static const _knownCompanyNames = <String, String>{
    'openai': 'OpenAI',
    'anthropic': 'Anthropic',
    'google': 'Google',
    'meta': 'Meta',
    'meta-llama': 'Meta Llama',
    'mistral': 'Mistral AI',
    'mistralai': 'Mistral AI',
    'nvidia': 'NVIDIA',
    'deepseek': 'DeepSeek',
    'xiaomi': 'Xiaomi',
    'qwen': 'Alibaba Qwen',
    'microsoft': 'Microsoft',
    'cohere': 'Cohere',
    'alibaba': 'Alibaba',
    'amazon': 'Amazon',
    'huggingface': 'Hugging Face',
    'ibm': 'IBM',
    'databricks': 'Databricks',
    'minimax': 'MiniMax',
    '01': '01.AI',
    'moonshot': 'Moonshot AI',
    'zhipu': 'Zhipu AI',
    'yi': '01.AI Yi',
    'gemma': 'Google Gemma',
    'phi': 'Microsoft Phi',
    'stability': 'Stability AI',
  };

  static const _defaultModelsByProvider = <String, List<String>>{
    'openrouter': [
      'openai/gpt-3.5-turbo',
      'openai/gpt-4o-mini',
      'openai/gpt-4o',
      'openai/gpt-4.1',
      'anthropic/claude-3.5-sonnet',
      'google/gemini-2.5-flash',
      'google/gemma-3-27b-it',
      'deepseek/deepseek-chat',
      'meta-llama/llama-3.1-8b-instruct',
      'meta-llama/llama-4-scout-17b-16e-instruct',
      'nvidia/nemotron-3-8b- ultra',
      'nvidia/llama-3.1-nemotron-70b-instruct',
      'xiaomi/mimo-2.5',
      'qwen/qwen3-235b-a22b',
      'microsoft/phi-4',
      'mistralai/mistral-small-3.1-24b-instruct',
    ],
    'openai': [
      'gpt-5.2',
      'gpt-5.1',
      'gpt-4.1',
      'gpt-4.1-mini',
      'gpt-4o',
      'gpt-4o-mini',
      'gpt-3.5-turbo',
      'gpt-3.5-turbo-16k',
      'o3',
      'o3-mini',
      'o4-mini',
    ],
    'deepseek': [
      'deepseek-v4-flash',
      'deepseek-v4-pro',
      'deepseek-chat',
      'deepseek-reasoner',
      'deepseek-coder',
    ],
    'google': [
      'gemini-2.5-flash',
      'gemini-2.5-pro',
      'gemini-2.0-flash',
      'gemini-2.0-flash-lite',
      'gemma-3-27b-it',
      'gemma-3-12b-it',
      'gemma-3-4b-it',
    ],
    'nvidia': [
      'meta/llama-3.1-8b-instruct',
      'meta/llama-3.1-70b-instruct',
      'meta/llama-3.3-70b-instruct',
      'meta/llama-4-scout-17b-16e-instruct',
      'mistralai/mixtral-8x7b-instruct-v0.1',
      'nvidia/llama-3.1-nemotron-70b-instruct',
      'nvidia/nemotron-3-8b-ultra',
      'nvidia/nemotron-mini-4b-instruct',
      'xiaomi/mimo-2.5',
      'qwen/qwen3-235b-a22b',
      'deepseek/deepseek-r1',
    ],
    'zai': [
      'glm-4.7-flash',
      'glm-4.5-flash',
      'glm-4.6v-flash',
      'glm-4.7-flashx',
      'glm-4.7',
      'glm-4.6',
      'glm-4.5',
      'glm-4.5-air',
      'glm-4-32b-0414-128k',
      'glm-5.3',
      'glm-5.2',
      'glm-5.1',
      'glm-5',
      'glm-5-turbo',
      'glm-5v-turbo',
      'glm-4.5v',
      'glm-4.6v',
      'glm-4.5x',
      'glm-4.5-airx',
      'glm-ocr',
      'glm-4.6v-flashx',
    ],
    'anthropic': [
      'claude-sonnet-4-5',
      'claude-opus-4-1',
      'claude-haiku-4-5',
      'claude-3-7-sonnet-latest',
      'claude-3-5-haiku-latest',
    ],
    'kimi': [
      'kimi-k2.6',
      'kimi-k2-turbo-preview',
      'kimi-k2-0905-preview',
      'moonshot-v1-128k',
    ],
    'groq': [
      'llama-3.3-70b-versatile',
      'llama-3.1-8b-instant',
      'meta-llama/llama-4-scout-17b-16e-instruct',
      'openai/gpt-oss-120b',
      'qwen/qwen3-32b',
      'deepseek-r1-distill-llama-70b',
      'moonshotai/kimi-k2-instruct',
      'gemma2-9b-it',
    ],
    'mistral': [
      'mistral-large-latest',
      'mistral-medium-latest',
      'mistral-small-latest',
      'magistral-medium-latest',
      'codestral-latest',
      'pixtral-large-latest',
      'ministral-8b-latest',
      'open-mistral-nemo',
    ],
    'together': [
      'meta-llama/Llama-3.3-70B-Instruct-Turbo',
      'meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo',
      'deepseek-ai/DeepSeek-V3',
      'Qwen/Qwen2.5-72B-Instruct-Turbo',
      'mistralai/Mixtral-8x7B-Instruct-v0.1',
      'lgai/exaone-3-5-32b-instruct',
    ],
    'xai': [
      'grok-4',
      'grok-4-fast',
      'grok-code-fast-1',
      'grok-3',
      'grok-3-mini',
      'grok-2-vision-1212',
    ],
    'perplexity': [
      'sonar-pro',
      'sonar',
      'sonar-reasoning-pro',
      'sonar-deep-research',
    ],
    'cerebras': [
      'llama-3.3-70b',
      'llama3.1-8b',
      'qwen-3-32b',
      'gpt-oss-120b',
    ],
    'fireworks': [
      'accounts/fireworks/models/llama-v3p3-70b-instruct',
      'accounts/fireworks/models/deepseek-v3',
      'accounts/fireworks/models/qwen2p5-72b-instruct',
      'accounts/fireworks/models/mixtral-8x22b-instruct',
    ],
    'cohere': [
      'command-a-03-2025',
      'command-r-plus-08-2024',
      'command-r-08-2024',
      'aya-expanse-8b',
    ],
    'huggingface': [
      'meta-llama/Llama-3.3-70B-Instruct',
      'deepseek-ai/DeepSeek-V3',
      'Qwen/Qwen2.5-72B-Instruct',
      'mistralai/Mistral-Small-24B-Instruct-2501',
      'moonshotai/Kimi-K2-Instruct',
    ],
    'xkiro': [
      'openai/gpt-5.2',
      'anthropic/claude-sonnet-4.6',
      'google/gemini-3-flash-preview',
      'deepseek/deepseek-v3.2',
      'z-ai/glm-4.7',
      'qwen/qwen3.7-max',
    ],
    'tokenrouter': [
      'openai/gpt-5.2',
      'anthropic/claude-opus-4.8',
      'z-ai/glm-5.3',
      'deepseek/deepseek-v4-pro',
      'xiaomi/mimo-v2.5',
      'nvidia/nemotron-3-super-120b-a12b',
      'moonshotai/kimi-k2.6',
      'minimax/minimax-m2.7',
    ],
    'agentrouter': [
      'claude-opus-4-8',
      'deepseek-r1',
      'glm-4.5-air',
      'gpt-4o',
    ],
    'orcarouter': [
      'orcarouter/auto',
      'openai/gpt-4o-mini',
      'anthropic/claude-sonnet-4.6',
      'google/gemini-2.5-pro',
      'kimi/kimi-k2.6',
    ],
    'apinex': [
      'gpt-4o',
      'claude-sonnet-4-6',
      'gemini-2.5-flash',
      'deepseek-chat',
    ],
  };

  final allProviders = <CloudProviderInfo>[].obs;

  List<CloudProviderInfo> get providers => allProviders;

  final modelsByProvider = <String, List<String>>{}.obs;
  final fetchedAtByProvider = <String, DateTime>{}.obs;
  final isLoadingProvider = <String, bool>{}.obs;
  final errorByProvider = <String, String>{}.obs;
  final searchByProvider = <String, String>{}.obs;
  final companyFilterByProvider = <String, String>{}.obs;
  final freeFirstByProvider = <String, bool>{}.obs;
  final modelTagsByProvider = <String, Map<String, List<String>>>{}.obs;

  /// Liveness per provider+model (online/failed/untested).
  final modelHealthByProvider =
      <String, Map<String, ModelHealth>>{}.obs;

  /// Test-all progress: provider → done count / total count.
  final testingByProvider = <String, bool>{}.obs;
  final testDoneByProvider = <String, int>{}.obs;
  final testTotalByProvider = <String, int>{}.obs;

  /// Hide failed models from lists when true (persisted).
  final autoHideFailed = false.obs;

  /// Auto-sync cadence in hours (persisted, 1–168, default 24).
  final modelSyncIntervalHours = 24.obs;

  /// Pinned provider ids, pin order (persisted). Keyed providers only.
  final pinnedProviders = <String>[].obs;

  /// Provider list sort: 'time' (key-set oldest first) or 'name' (A–Z).
  final providerSortMode = 'time'.obs;
  final customProviderError = ''.obs;
  final providerSearchQuery = ''.obs;
  final _dynamicActiveModel = <String, String>{}.obs;

  final customNameController = TextEditingController();
  final customBaseUrlController = TextEditingController();
  final customApiKeyController = TextEditingController();
  final customModelController = TextEditingController();

  /// Models found by the last successful verification, per provider.
  final verifiedModelCountByProvider = <String, int>{}.obs;

  final _testCancel = <String, bool>{};

  @override
  void onInit() {
    super.onInit();
    autoHideFailed.value =
        _hive.getSetting<bool>(CloudModelController._autoHideKey) ?? false;
    modelSyncIntervalHours.value =
        _clampInterval(_hive.getSetting<int>(_syncIntervalKey));
    final sort = _hive.getSetting<String>(_sortModeKey);
    providerSortMode.value = (sort == 'name') ? 'name' : 'time';
    try {
      final pins = _hive.getSetting<List>(_pinnedKey);
      if (pins != null) {
        pinnedProviders.assignAll(pins.whereType<String>());
      }
    } catch (_) {}
    _initProviders();
    if (!providers.any((provider) => provider.id == activeProvider)) {
      _settings.setCloudProvider('openrouter');
    }
    for (final provider in providers) {
      _loadCachedModels(provider.id);
      ensureDefaultModels(provider.id);
      // Restore persisted dynamic provider model selection.
      if (!_isBuiltInProvider(provider.id) && provider.id != 'custom') {
        final saved = _hive.getSetting<String>(_dynamicKey(provider.id));
        if (saved != null && saved.isNotEmpty) {
          _dynamicActiveModel[provider.id] = saved;
        }
      }
      // Ensure the active model is always visible in the list (prevents fallback to first model after restart).
      final active = activeModelFor(provider.id);
      if (active.isNotEmpty && !(modelsByProvider[provider.id]?.contains(active) ?? false)) {
        modelsByProvider[provider.id] = [...(modelsByProvider[provider.id] ?? []), active];
      }
      _loadHealth(provider.id);
    }
    _syncCustomControllers();
    Future.microtask(maybeAutoSync);
  }

  @override
  void onClose() {
    customNameController.dispose();
    customBaseUrlController.dispose();
    customApiKeyController.dispose();
    customModelController.dispose();
    super.onClose();
  }




  void _loadCachedModels(String provider) {
    if (apiKeyFor(provider).isEmpty) return;
    final raw = _hive.getSetting<List>('$_cachePrefix$provider');
    if (raw != null) {
      modelsByProvider[provider] = raw.whereType<String>().toList();
    }
    final rawTime = _hive.getSetting<String>('$_cacheTimePrefix$provider');
    if (rawTime != null) {
      final parsed = DateTime.tryParse(rawTime);
      if (parsed != null) fetchedAtByProvider[provider] = parsed;
    }
  }

  void _syncCustomControllers() {
    customNameController.text = _settings.customCloudName.value;
    customBaseUrlController.text = _settings.customCloudBaseUrl.value;
    customApiKeyController.text = _settings.customCloudKey.value;
    customModelController.text = _settings.customCloudModel.value;
  }

  String _shortBody(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 280) return compact;
    return '${compact.substring(0, 280)}...';
  }
}
