/// Prompt templates for [ChatController]: built-ins, custom CRUD,
/// insertion and template search.
///
/// Part of `chat_controller.dart` (same library) — shares its imports
/// and private members. Split out so the controller file stays
/// navigable; behavior is unchanged.
/// Contains: ensureTemplatesLoaded(), static _defaultTemplates, insertTemplate(), addPromptTemplate()
///   deletePromptTemplate()
part of 'chat_controller.dart';

extension ChatControllerTemplates on ChatController {
  void ensureTemplatesLoaded() {
    if (_templatesLoaded) return;
    _templatesLoaded = true;
    try {
      final raw = _hive.getSetting<String>(ChatController._kTemplatesKey);
      if (raw == null || raw.isEmpty) {
        promptTemplates.assignAll(_defaultTemplates());
        unawaited(
            _hive.setSetting(ChatController._kTemplatesKey, jsonEncode(promptTemplates)));
      } else {
        final list = (jsonDecode(raw) as List)
            .whereType<Map>()
            .map((m) => {
                  'id': m['id']?.toString() ?? '',
                  'name': m['name']?.toString() ?? '',
                  'body': m['body']?.toString() ?? '',
                  'builtin': m['builtin']?.toString() ?? '',
                })
            .where((m) => (m['name'] ?? '').isNotEmpty)
            .toList();
        promptTemplates.assignAll(list.isEmpty ? _defaultTemplates() : list);
      }
    } catch (_) {
      promptTemplates.assignAll(_defaultTemplates());
    }
  }

  static List<Map<String, String>> _defaultTemplates() => const [
        // ── Coding (8) ──
        {'id': 'builtin-explain-code', 'name': 'Explain Code', 'body': 'Explain what this code does, step by step:\n\n', 'builtin': '1', 'category': 'Coding', 'description': 'Break down code logic into clear steps'},
        {'id': 'builtin-fix-bug', 'name': 'Fix a Bug', 'body': 'Find the bug in this code and fix it. Explain the cause first:\n\n', 'builtin': '1', 'category': 'Coding', 'description': 'Identify and fix bugs with root cause analysis'},
        {'id': 'builtin-code-review', 'name': 'Code Review', 'body': 'Review this code for bugs, performance issues, and best practices. Score readability 1-10:\n\n', 'builtin': '1', 'category': 'Coding', 'description': 'Professional code review with scoring'},
        {'id': 'builtin-write-tests', 'name': 'Write Tests', 'body': 'Write comprehensive unit tests for this code with edge cases:\n\n', 'builtin': '1', 'category': 'Coding', 'description': 'Generate unit tests with edge cases'},
        {'id': 'builtin-refactor', 'name': 'Refactor Code', 'body': 'Refactor this code to be cleaner, more maintainable, and follow SOLID principles:\n\n', 'builtin': '1', 'category': 'Coding', 'description': 'Clean up code following best practices'},
        {'id': 'builtin-convert-lang', 'name': 'Convert Language', 'body': 'Convert this code from one programming language to another. Preserve logic and use idiomatic patterns:\n\n', 'builtin': '1', 'category': 'Coding', 'description': 'Translate code between languages idiomatically'},
        {'id': 'builtin-document-code', 'name': 'Document Code', 'body': 'Add comprehensive documentation (docstrings, comments, README) to this code:\n\n', 'builtin': '1', 'category': 'Coding', 'description': 'Auto-generate documentation and comments'},
        {'id': 'builtin-debug-error', 'name': 'Debug Error', 'body': 'I got this error. Explain why it happened and how to fix it:\n\n', 'builtin': '1', 'category': 'Coding', 'description': 'Debug error messages with fix suggestions'},

        // ── Writing (6) ──
        {'id': 'builtin-mail', 'name': 'Write Email', 'body': 'Write a short polite email about this:\n\n', 'builtin': '1', 'category': 'Writing', 'description': 'Draft professional or casual emails'},
        {'id': 'builtin-blog-post', 'name': 'Blog Post', 'body': 'Write an engaging blog post about this topic. Include an intro, 3-5 main points, and a conclusion:\n\n', 'builtin': '1', 'category': 'Writing', 'description': 'Create structured blog posts with SEO hooks'},
        {'id': 'builtin-social-media', 'name': 'Social Media Post', 'body': 'Write an engaging social media post for this. Include relevant hashtags:\n\n', 'builtin': '1', 'category': 'Writing', 'description': 'Craft viral social media content'},
        {'id': 'builtin-cover-letter', 'name': 'Cover Letter', 'body': 'Write a compelling cover letter for this job position based on my background:\n\n', 'builtin': '1', 'category': 'Writing', 'description': 'Generate tailored cover letters'},
        {'id': 'builtin-product-desc', 'name': 'Product Description', 'body': 'Write a compelling product description that highlights features and benefits:\n\n', 'builtin': '1', 'category': 'Writing', 'description': 'Write sales-ready product copy'},
        {'id': 'builtin-meeting-notes', 'name': 'Meeting Notes', 'body': 'Organize these meeting notes into clear sections: Summary, Action Items, Decisions, and Next Steps:\n\n', 'builtin': '1', 'category': 'Writing', 'description': 'Structure messy notes into action items'},

        // ── Analysis (5) ──
        {'id': 'builtin-summarize', 'name': 'Summarize', 'body': 'Summarize this in 5 short bullet points:\n\n', 'builtin': '1', 'category': 'Analysis', 'description': 'Distill content into key bullet points'},
        {'id': 'builtin-compare', 'name': 'Compare & Contrast', 'body': 'Compare and contrast these two things. List similarities, differences, and a recommendation:\n\n', 'builtin': '1', 'category': 'Analysis', 'description': 'Side-by-side comparison with verdict'},
        {'id': 'builtin-pros-cons', 'name': 'Pros & Cons', 'body': 'List the pros and cons of this decision. Give a final recommendation:\n\n', 'builtin': '1', 'category': 'Analysis', 'description': 'Balanced analysis for decision-making'},
        {'id': 'builtin-swot', 'name': 'SWOT Analysis', 'body': 'Perform a SWOT analysis (Strengths, Weaknesses, Opportunities, Threats) for:\n\n', 'builtin': '1', 'category': 'Analysis', 'description': 'Strategic SWOT framework analysis'},
        {'id': 'builtin-data-analysis', 'name': 'Data Analysis', 'body': 'Analyze this data. Find patterns, outliers, and key insights. Suggest visualizations:\n\n', 'builtin': '1', 'category': 'Analysis', 'description': 'Extract insights and patterns from data'},

        // ── Creative (5) ──
        {'id': 'builtin-story', 'name': 'Story Writing', 'body': 'Write a short, engaging story with vivid imagery about:\n\n', 'builtin': '1', 'category': 'Creative', 'description': 'Craft stories with vivid imagery and pacing'},
        {'id': 'builtin-poetry', 'name': 'Poetry', 'body': 'Write a poem about this topic. Use metaphor and rhythm:\n\n', 'builtin': '1', 'category': 'Creative', 'description': 'Compose poems with literary devices'},
        {'id': 'builtin-lyrics', 'name': 'Song Lyrics', 'body': 'Write song lyrics with verse, chorus, and bridge about:\n\n', 'builtin': '1', 'category': 'Creative', 'description': 'Create song lyrics with structure'},
        {'id': 'builtin-brainstorm', 'name': 'Brainstorm Ideas', 'body': 'Brainstorm 10 creative and unique ideas for:\n\n', 'builtin': '1', 'category': 'Creative', 'description': 'Generate diverse creative ideas'},
        {'id': 'builtin-character', 'name': 'Character Creator', 'body': 'Create a detailed character profile with backstory, personality, motivations, and flaws for:\n\n', 'builtin': '1', 'category': 'Creative', 'description': 'Design rich fictional characters'},

        // ── Study (5) ──
        {'id': 'builtin-eli12', 'name': 'Explain Simply (ELI12)', 'body': 'Explain this like I am 12, with one everyday analogy and one example:\n\n', 'builtin': '1', 'category': 'Study', 'description': 'Simple explanations with analogies'},
        {'id': 'builtin-quiz-me', 'name': 'Quiz Me', 'body': 'Create a 10-question quiz about this topic with answers. Mix multiple-choice and short answer:\n\n', 'builtin': '1', 'category': 'Study', 'description': 'Generate quizzes for self-testing'},
        {'id': 'builtin-flashcards', 'name': 'Flashcards', 'body': 'Create 15 flashcards (front: question, back: answer) about:\n\n', 'builtin': '1', 'category': 'Study', 'description': 'Generate study flashcards'},
        {'id': 'builtin-study-plan', 'name': 'Study Plan', 'body': 'Create a structured study plan for learning this topic from beginner to advanced:\n\n', 'builtin': '1', 'category': 'Study', 'description': 'Build a learning roadmap'},
        {'id': 'builtin-concept-map', 'name': 'Concept Map', 'body': 'Create a concept map showing relationships between key ideas in this topic:\n\n', 'builtin': '1', 'category': 'Study', 'description': 'Map concept relationships visually'},

        // ── Business (4) ──
        {'id': 'builtin-biz-plan', 'name': 'Business Plan Outline', 'body': 'Create a business plan outline for this idea. Include market analysis, revenue model, and go-to-market strategy:\n\n', 'builtin': '1', 'category': 'Business', 'description': 'Structure a business plan framework'},
        {'id': 'builtin-marketing', 'name': 'Marketing Strategy', 'body': 'Create a marketing strategy with target audience, channels, messaging, and KPIs for:\n\n', 'builtin': '1', 'category': 'Business', 'description': 'Design a go-to-market plan'},
        {'id': 'builtin-pitch', 'name': 'Pitch Deck Script', 'body': 'Write a compelling pitch deck narrative (problem, solution, market, traction, ask) for:\n\n', 'builtin': '1', 'category': 'Business', 'description': 'Craft investor pitch narratives'},
        {'id': 'builtin-competitive', 'name': 'Competitive Analysis', 'body': 'Analyze the competitive landscape for this product/market. Include key players, differentiators, and gaps:\n\n', 'builtin': '1', 'category': 'Business', 'description': 'Map competitors and find gaps'},

        // ── Translation (3) ──
        {'id': 'builtin-translate', 'name': 'Translate BN↔EN', 'body': 'Translate this between Bangla and English. Keep it natural:\n\n', 'builtin': '1', 'category': 'Translation', 'description': 'Natural Bangla-English translation'},
        {'id': 'builtin-multi-translate', 'name': 'Multi-Language', 'body': 'Translate this text into 5 languages (Spanish, French, German, Japanese, Arabic):\n\n', 'builtin': '1', 'category': 'Translation', 'description': 'Translate into multiple languages at once'},
        {'id': 'builtin-localize', 'name': 'Localize Content', 'body': 'Localize this content for a different cultural context. Adapt idioms, references, and tone:\n\n', 'builtin': '1', 'category': 'Translation', 'description': 'Culturally adapt content for new markets'},

        // ── Productivity (4) ──
        {'id': 'builtin-daily-planner', 'name': 'Daily Planner', 'body': 'Create a structured daily plan for these tasks. Prioritize by importance and group similar work:\n\n', 'builtin': '1', 'category': 'Productivity', 'description': 'Organize your day with priorities'},
        {'id': 'builtin-todo-breakdown', 'name': 'Task Breakdown', 'body': 'Break this large task into small, actionable subtasks with time estimates:\n\n', 'builtin': '1', 'category': 'Productivity', 'description': 'Decompose big tasks into steps'},
        {'id': 'builtin-decision', 'name': 'Decision Matrix', 'body': 'Create a decision matrix to evaluate these options. Score each on key criteria:\n\n', 'builtin': '1', 'category': 'Productivity', 'description': 'Score options systematically'},
        {'id': 'builtin-meeting-agenda', 'name': 'Meeting Agenda', 'body': 'Create a focused meeting agenda with time allocations for these topics:\n\n', 'builtin': '1', 'category': 'Productivity', 'description': 'Structure meetings with time boxes'},
      ];

  void insertTemplate(String body) {
    final cur = textController.text;
    final clean = sanitizeUtf16(body);
    withoutPasteWatch(() {
      textController.text = cur.isEmpty ? clean : '$cur\n$clean';
    });
    try {
      textController.selection =
          TextSelection.collapsed(offset: textController.text.length);
    } catch (_) {}
    inputText.value = textController.text;
    try {
      composerFocusNode.requestFocus();
    } catch (_) {}
  }

  Future<void> addPromptTemplate(String name, String body, {String category = ''}) async {
    ensureTemplatesLoaded();
    promptTemplates.add({
      'id': _uuid.v4(),
      'name': name.trim(),
      'body': body,
      'builtin': '',
      'category': category,
      'description': '',
    });
    await _hive.setSetting(
        ChatController._kTemplatesKey, jsonEncode(promptTemplates.toList()));
  }

  Future<void> deletePromptTemplate(String id) async {
    ensureTemplatesLoaded();
    promptTemplates
        .removeWhere((t) => t['id'] == id && (t['builtin'] ?? '').isEmpty);
    await _hive.setSetting(
        ChatController._kTemplatesKey, jsonEncode(promptTemplates.toList()));
  }
}
