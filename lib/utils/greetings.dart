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
/// Only the FIRST line of each segment names the user — repeating the
/// name in every line reads robotic. All lines stay ≤44 chars so the
/// single-line typewriter never wraps.
List<String> greetingsFor(DaySegment segment) {
  switch (segment) {
    case DaySegment.morning:
      return const [
        'Good morning, {name}. Exploring today?',
        'Morning! Fresh questions — shoot.',
        'Hi, good morning. What\u2019s up?',
        'Rise and shine. Dive into what?',
        'Morning. Coffee\u2019s on — ask away.',
        'Hey! What are we learning?',
        'New day. Figure out what?',
        'Morning! Untangle what today?',
      ];
    case DaySegment.afternoon:
      return const [
        'Good afternoon, {name}. Exploring?',
        'Hey! Next question?',
        'Midday curiosity — go on.',
        'Afternoon! What shall we solve?',
        'Good afternoon. Agenda?',
        'Slump or spark? Ask away!',
        'Solving what this noon?',
        'Pick any topic.',
      ];
    case DaySegment.evening:
      return const [
        'Good evening, {name}. Tonight\u2019s quest?',
        'Evening! Unwind with a question?',
        'What\u2019s sparking tonight?',
        'Evening edition. Ask!',
        'Evening! What\u2019s on your mind?',
        'Big or small — all welcome.',
        'Winding down? Ask anything.',
        'Today sparked what?',
      ];
    case DaySegment.night:
      return const [
        'Up late, {name}? Explore quietly.',
        'Good night! One more question?',
        'Night owl mode. Wondering what?',
        'Midnight oil? Ask away.',
        'It\u2019s late — deep questions.',
        'Night! What\u2019s buzzing?',
        'Late thoughts? I\u2019m listening.',
        'Night is young. Explore?',
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
