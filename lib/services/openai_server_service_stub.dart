import 'dart:async';

class OpenAiServerService {
  bool get isRunning => false;
  String? get localUrl => null;

  /// Mirrors the io implementation (always empty here).
  List<Map<String, dynamic>> get recentRequests => const [];

  /// Auto-generated bearer token when none was provided (io only).
  String? get activeApiKey => null;

  Future<void> start({
    int port = 8080,
    String? apiKey,
    void Function(String)? onLog,
  }) async {
    throw UnsupportedError('Local API server is not available on this platform.');
  }

  Future<void> stop() async {}
}
