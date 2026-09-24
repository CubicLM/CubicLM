/// Time-based personalized greeting bank for the chat empty state.
/// Pure logic (no widgets): the typewriter lives in `empty_state.dart`.
/// Templates use `{name}` (first name); [fillGreeting] falls back to
/// "friend" when no profile name exists yet.
library;

/// Part of day driving which greetings show.
enum DaySegment { morning, afternoon, evening, night }

/// 05–12 morning, 12–17 afternoon, 17–21 evening, else night.
DaySegment segmentFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 12) return DaySegment.morning;
  if (h >= 12 && h < 17) return DaySegment.afternoon;
  if (h >= 17 && h < 21) return DaySegment.evening;
  return DaySegment.night;
}

/// Raw templates for a segment (8 each → 32 total).
List<String> greetingsFor(DaySegment segment) {
  switch (segment) {
    case DaySegment.morning:
      return const [
        'Good morning, {name}. What are we exploring today?',
        'Morning, {name}! Fresh day, fresh questions — shoot.',
        'Hi {name}, good morning. What\u2019s on your mind?',
        'Rise and shine, {name}. What shall we dive into?',
        'Good morning, {name}. Coffee\u2019s on — questions ready?',
        'Hey {name}, morning! What are we learning today?',
        'A new day, {name}. What do you want to figure out?',
        'Morning! {name}, what can I help you untangle today?',
      ];
    case DaySegment.afternoon:
      return const [
        'Good afternoon, {name}. What are we exploring?',
        'Hey {name}, afternoon! What\u2019s the next question?',
        'Hi {name}. Midday curiosity — I like it. Go on.',
        'Afternoon, {name}. What shall we work through?',
        'Good afternoon! {name}, what\u2019s on the agenda?',
        'Hey {name} — afternoon slump or afternoon spark? Ask away.',
        'Hi {name}, good afternoon. What are we solving?',
        'Afternoon, {name}! Pick a topic, any topic.',
      ];
    case DaySegment.evening:
      return const [
        'Good evening, {name}. What are we exploring tonight?',
        'Evening, {name}! Unwind with a good question?',
        'Hi {name}, good evening. What\u2019s sparking curiosity?',
        'Hey {name} — evening edition. What shall we explore?',
        'Good evening! {name}, teach me what you\u2019re wondering.',
        'Evening, {name}. Big questions or small ones — both welcome.',
        'Hi {name}. Winding down or gearing up? Ask me anything.',
        'Good evening, {name}. What did today make you curious about?',
      ];
    case DaySegment.night:
      return const [
        'Up late, {name}? Let\u2019s explore something quietly brilliant.',
        'Good night, {name} — one more question before sleep?',
        'Night owl mode, {name}. What are we wondering about?',
        'Hey {name}, burning the midnight oil? Ask away.',
        'It\u2019s late, {name} — perfect time for deep questions.',
        'Good night! {name}, what\u2019s keeping that mind busy?',
        'Late-night thoughts, {name}? I\u2019m all ears.',
        'Hey {name}. The night is young — what shall we explore?',
      ];
  }
}

/// Fill `{name}` with the first name, or "friend" when empty.
String fillGreeting(String template, String rawName) {
  final first = rawName.trim().split(RegExp(r'\s+')).firstWhere(
        (s) => s.isNotEmpty,
        orElse: () => '',
      );
  return template.replaceAll('{name}', first.isEmpty ? 'friend' : first);
}

/// Ready-to-type lines for right now.
List<String> greetingsNow(String rawName, DateTime now) => greetingsFor(
      segmentFor(now),
    ).map((t) => fillGreeting(t, rawName)).toList();
