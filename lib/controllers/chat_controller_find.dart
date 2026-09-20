/// Find-in-page and history search for [ChatController].
///
/// Part of `chat_controller.dart` (same library) — shares its imports
/// and private members. Split out so the controller file stays
/// navigable; behavior is unchanged.
/// Contains: findKeyFor(), toggleFind(), updateFind(), _updateFindAsync(), stepFind(), jumpToFindMatch()
///   openHistorySearch()
part of 'chat_controller.dart';

extension ChatControllerFind on ChatController {
  GlobalKey findKeyFor(String id) => _findKeys.putIfAbsent(id, GlobalKey.new);

  void toggleFind(bool open) {
    findActive.value = open;
    if (!open) {
      findQuery.value = '';
      findMatches.clear();
      findIndex.value = 0;
      findController.clear();
    }
  }

  void updateFind(String q) {
    unawaited(_updateFindAsync(q));
  }

  Future<void> _updateFindAsync(String q) async {
    final gen = ++_findGen;
    final needle = q.trim().toLowerCase();
    findQuery.value = needle;
    if (needle.isEmpty) {
      findMatches.clear();
      findIndex.value = 0;
      return;
    }
    List<String> scan() => messages
        .where((m) =>
            '${m.content} ${m.fileName ?? ''}'.toLowerCase().contains(needle))
        .map((m) => m.id)
        .toList();
    findMatches.value = scan();
    var pages = 0;
    while (findMatches.isEmpty &&
        hasOlderMessages.value &&
        pages < 5 &&
        gen == _findGen) {
      pages++;
      await loadOlderMessages();
      if (gen != _findGen) return;
      findMatches.value = scan();
    }
    if (gen != _findGen) return;
    findIndex.value = 0;
    if (findMatches.isNotEmpty) jumpToFindMatch(0);
  }

  void stepFind(int dir) {
    if (findMatches.isEmpty) return;
    findIndex.value =
        (findIndex.value + dir + findMatches.length) % findMatches.length;
    jumpToFindMatch(findIndex.value);
  }

  void jumpToFindMatch(int i) {
    if (i < 0 || i >= findMatches.length) return;
    final ctx = _findKeys[findMatches[i]]?.currentContext;
    if (ctx == null) return;
    try {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.3,
      );
    } catch (_) {}
  }

  void openHistorySearch() {
    try {
      chatScaffoldKey?.currentState?.openDrawer();
    } catch (_) {}
    Future.delayed(const Duration(milliseconds: 350), () {
      try {
        historySearchFocus.requestFocus();
      } catch (_) {}
    });
  }
}
