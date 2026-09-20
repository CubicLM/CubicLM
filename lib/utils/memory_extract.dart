/// Offline, model-free memory helpers for persistent conversation
/// memory (ROM, not RAM): fact extraction from user turns, keyword
/// search terms, and relevance ranking. No network — keyword scoring
/// fused with trigram-vector semantics (`semantic_vectors.dart`;
/// still no model download). Pure — unit tested.
library;

import 'semantic_vectors.dart';

/// Common English stopwords skipped when building search keywords.
const Set<String> _stopwords = {
  'about',
  'after',
  'again',
  'among',
  'because',
  'before',
  'being',
  'between',
  'could',
  'does',
  'doing',
  'down',
  'during',
  'each',
  'from',
  'further',
  'have',
  'having',
  'here',
  'into',
  'more',
  'most',
  'other',
  'over',
  'same',
  'should',
  'some',
  'such',
  'than',
  'that',
  'then',
  'there',
  'these',
  'they',
  'this',
  'those',
  'through',
  'under',
  'using',
  'very',
  'want',
  'were',
  'what',
  'when',
  'where',
  'which',
  'while',
  'with',
  'would',
  'your',
};

/// Splits [text] into search keywords. Unicode-aware (keeps Bangla
/// script), drops stopwords and short tokens.
List<String> extractKeywords(String text, {int max = 10}) {
  final out = <String>[];
  for (final raw
      in text.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))) {
    final w = raw.trim();
    if (w.isEmpty || _stopwords.contains(w)) continue;
    final ascii = w.codeUnits.every((c) => c < 128);
    if (ascii && w.length < 4) continue;
    if (!ascii && w.length < 2) continue;
    if (!out.contains(w)) out.add(w);
    if (out.length >= max) break;
  }
  return out;
}

class _FactPattern {
  final RegExp re;
  final String Function(Match m) build;
  const _FactPattern(this.re, this.build);
}

String _cap(String s, [int max = 120]) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.length <= max) return t;
  return '${t.substring(0, max).trim()}…';
}

/// States that look like "I am a <role>" but aren't durable facts.
const Set<String> _notRoles = {
  'happy',
  'sad',
  'tired',
  'good',
  'fine',
  'ok',
  'okay',
  'sick',
  'busy',
  'free',
  'ready',
  'sure',
  'glad',
  'sorry',
  'hungry',
  'bored',
  'excited',
  'alone',
  'here',
  'there',
  'back',
  'done',
};

/// Verb forms that mean the capture is an activity, not an identity.
const Set<String> _activityVerbs = {
  'going',
  'doing',
  'trying',
  'looking',
  'thinking',
  'working',
  'eating',
  'sleeping',
  'watching',
  'playing',
  'reading',
  'writing',
  'talking',
  'walking',
  'running',
  'sitting',
  'waiting',
  'coming',
};

/// Cleans an "I am a(n) X" capture, returning '' unless X is a durable
/// role (rejects moods like "happy" and activities like "going...").
String _roleCore(String capture) {
  final c = _cap(capture, 40);
  if (c.isEmpty) return '';
  final first = c.split(' ').first.toLowerCase();
  if (_notRoles.contains(first)) return '';
  final words = c.toLowerCase().split(' ');
  if (words.any(_activityVerbs.contains)) return '';
  return c;
}

final List<_FactPattern> _factPatterns = [
  // "my name is Abir" / "amar nam Abir"
  _FactPattern(
      RegExp(
          r'''(?:my name is|i am called|amar nam(?: holo)?)\s+([^\n,.!?;]{1,40})''',
          caseSensitive: false),
      (m) => 'User\'s name is ${_cap(m.group(1)!)}'),
  // "I am a student" (durable roles only — moods and activities
  // like "happy" / "going to market" are rejected).
  _FactPattern(
      RegExp(r'''\bi am (a|an) ([a-z][^\n,.!?;]{1,30})''',
          caseSensitive: false),
      (m) {
        final role = _roleCore(m.group(2)!);
        if (role.isEmpty) return '';
        return 'User is ${m.group(1)} $role';
      }),
  // "my project/app is (called) X" / "amar project (ta) (holo) X"
  _FactPattern(
      RegExp(
          r'''(?:my\s+(?:project|app|company)\s+(?:is\s+(?:called\s+)?|:\s*)|amar\s+project(?:\s+ta)?\s+(?:holo\s+)?)([^\n,.!?;]{1,50})''',
          caseSensitive: false),
      (m) => 'User\'s project: ${_cap(m.group(1)!)}'),
  // "I'm building/working on X" / "ami X banacchi"
  _FactPattern(
      RegExp(
          r'''(?:i am |i'm )(?:building|working on|making|developing)\s+([^\n,.!?;]{1,60})''',
          caseSensitive: false),
      (m) => 'User is building: ${_cap(m.group(1)!)}'),
  _FactPattern(
      RegExp(r'''ami\s+([^\n,.!?;]{1,60}?)\s+bana(?:cchi|চ্ছি)''',
          caseSensitive: false),
      (m) => 'User is building: ${_cap(m.group(1)!)}'),
  // "I live in X" / "I'm from X"
  _FactPattern(
      RegExp(
          r'''(?:i live in|i'm from|i am from)\s+([^\n,.!?;]{1,40})''',
          caseSensitive: false),
      (m) => 'User lives in / is from ${_cap(m.group(1)!)}'),
  // "my favorite X is Y" / "my favourite X is Y"
  _FactPattern(
      RegExp(
          r'''\bmy favo[u]?rite\s+([a-z]+\s+is\s+[^\n,.!?;]{1,50})''',
          caseSensitive: false),
      (m) => 'User\'s favorite ${_cap(m.group(1)!)}'),
  // "remember (that) X" — explicit instruction, keep verbatim-ish
  _FactPattern(
      RegExp(r'''\bremember(?: that)?\s+([^\n]{4,140})''',
          caseSensitive: false),
      (m) => 'Remember: ${_cap(m.group(1)!, 140)}'),
];

/// Extracts durable user facts from a user turn. Conservative by
/// design (the Memory page lets users delete). Max 3 candidates.
List<String> extractFacts(String userText) {
  final out = <String>[];
  if (userText.trim().length < 8) return out;
  for (final p in _factPatterns) {
    for (final m in p.re.allMatches(userText)) {
      try {
        final fact = p.build(m).trim();
        if (fact.length < 6 || fact.length > 160) continue;
        if (!out.any((e) => e.toLowerCase() == fact.toLowerCase())) {
          out.add(fact);
        }
      } catch (_) {}
      if (out.length >= 3) return out;
    }
    if (out.length >= 3) break;
  }
  return out;
}

/// Scores one fact against query keywords (substring hits).
int memoryScore(String fact, List<String> keywords) {
  final low = fact.toLowerCase();
  var score = 0;
  for (final k in keywords) {
    if (k.isEmpty) continue;
    var idx = 0;
    var n = 0;
    while (n < 5) {
      idx = low.indexOf(k, idx);
      if (idx < 0) break;
      n++;
      idx += k.length;
    }
    score += n;
  }
  return score;
}

/// Topic id for contradiction replacement (same topic = new fact
/// supersedes old ones). '' means keep multiples (builds, remembrances).
String factTopic(String fact) {
  if (fact.startsWith("User's name is")) return 'name';
  if (fact.startsWith("User's project:")) return 'project';
  if (fact.startsWith('User lives in')) return 'live';
  if (fact.startsWith('User is a ') || fact.startsWith('User is an ')) {
    return 'role';
  }
  if (fact.startsWith("User's favorite")) {
    final parts = fact.split(' ');
    if (parts.length > 2) return 'fav:${parts[2].toLowerCase()}';
    return 'fav';
  }
  return '';
}

/// Cuts [text] to a window around the first keyword hit instead of the
/// head, so the recalled snippet shows WHY it matched. Word-boundary
/// trimmed with … affixes. Pure — unit tested.
String centeredSnippet(String text, List<String> keywords, int maxChars) {
  final t = text.trim();
  if (t.length <= maxChars) return t;
  final low = t.toLowerCase();
  var hit = -1;
  for (final k in keywords) {
    if (k.isEmpty) continue;
    final i = low.indexOf(k.toLowerCase());
    if (i >= 0 && (hit < 0 || i < hit)) hit = i;
  }
  if (hit < 0) {
    var cut = t.substring(0, maxChars);
    final sp = cut.lastIndexOf(' ');
    if (sp > maxChars - 40) cut = cut.substring(0, sp);
    return '$cut…';
  }
  // Center the hit (~1/3 context before, ~2/3 after) instead of
  // starting the window at it — otherwise the match itself falls
  // outside and the snippet shows unrelated filler.
  var start = hit - (maxChars ~/ 3);
  if (start < 0) start = 0;
  var end = start + maxChars;
  if (end > t.length) {
    end = t.length;
    start = end - maxChars < 0 ? 0 : end - maxChars;
  }
  var cut = t.substring(start, end);
  final firstSp = cut.indexOf(' ');
  if (start > 0 && firstSp >= 0 && firstSp < 30) {
    cut = cut.substring(firstSp + 1);
  }
  final lastSp = cut.lastIndexOf(' ');
  if (end < t.length && lastSp > cut.length - 40) {
    cut = cut.substring(0, lastSp);
  }
  final prefix = start > 0 ? '…' : '';
  final suffix = end < t.length ? '…' : '';
  return '$prefix$cut$suffix';
}

/// Ranks stored facts for [query]: keyword hits first (dominant),
/// trigram-vector semantics reranks and rescues paraphrases with zero
/// shared keywords (cosine ≥ threshold); then most recent (facts are
/// newest-first already when passed that way), filling at most
/// [maxChars]. Empty query → most recent fill.
List<String> rankFacts(
  List<String> facts, {
  required String query,
  int maxChars = 600,
  int maxItems = 5,
}) {
  if (facts.isEmpty) return [];
  final kws = extractKeywords(query);
  // No keywords → pure recency (unchanged legacy path).
  if (kws.isEmpty) {
    final picked = <String>[];
    var chars = 0;
    for (final f in facts) {
      if (picked.length >= maxItems) break;
      if (chars + f.length > maxChars) continue;
      picked.add(f);
      chars += f.length;
    }
    return picked;
  }
  final qv = semanticVector(query);
  final idx = facts.asMap();
  final scored = idx.entries.map((e) {
    final kw = memoryScore(e.value, kws);
    final sem = cosineSimilarity(qv, semanticVector(e.value));
    return (
      fact: e.value,
      fused: fusedRelevance(keywordScore: kw, cosine: sem),
      rescued: kw == 0 && sem >= semanticRescueThreshold,
      order: e.key
    );
  }).toList();
  // Relevance desc; ties keep recency order (stable by index).
  scored.sort((a, b) {
    final c = b.fused.compareTo(a.fused);
    if (c != 0) return c;
    return a.order.compareTo(b.order);
  });
  final picked = <String>[];
  var chars = 0;
  for (final e in scored) {
    if (picked.length >= maxItems) break;
    // Skip keyword-misses unless semantics rescued them.
    if (e.fused <= 0 && !e.rescued) break;
    final f = e.fact;
    if (chars + f.length > maxChars) continue;
    picked.add(f);
    chars += f.length;
  }
  return picked;
}
