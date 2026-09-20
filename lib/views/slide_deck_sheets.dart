/// Style, plus, theme, translate, data, and URL sheets/dialogs.
///
/// Split from `slide_deck_view.dart` - behavior is unchanged.
/// Contains: _showStyleAudienceSheet(), _optionRow(), _showPlusSheet(), _pickSourceFile(), _countStepper()
///   _pickInputImage(), _toggleSpeech(), _showThemePicker(), _pickLogo(), _showTranslateDialog()
///   _showLiveDataDialog(), _showUrlDialog(), _updateTheme()
part of 'slide_deck_view.dart';

extension _SlideDeckSheets on _SlideDeckViewState {
  void _showStyleAudienceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: DefaultTabController(
          length: 3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                labelColor: Dt.accent,
                unselectedLabelColor: Theme.of(context).hintColor,
                indicatorColor: Dt.accent,
                labelStyle:
                    GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
                tabs: const [
                  Tab(text: 'Slide Style'),
                  Tab(text: 'Target Audience'),
                  Tab(text: 'Visual Style'),
                ],
              ),
              SizedBox(
                height: 320,
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                      child: Obx(() => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final s in SlideDeckController.styles)
                                _optionRow(
                                  label: s,
                                  selected: c.style.value == s,
                                  onTap: () => c.style.value = s,
                                ),
                            ],
                          )),
                    ),
                    SingleChildScrollView(
                      child: Obx(() => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final a in _SlideDeckViewState._audiences)
                                _optionRow(
                                  label: a,
                                  selected: (c.audience.value.isEmpty
                                          ? 'General'
                                          : c.audience.value) ==
                                      a,
                                  onTap: () => c.audience.value =
                                      a == 'General' ? '' : a,
                                ),
                            ],
                          )),
                    ),
                    SingleChildScrollView(
                      child: Obx(() => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final vs in SlideDeckController.visualStyles)
                                _optionRow(
                                  label: vs,
                                  selected: c.visualStyle.value == vs,
                                  onTap: () => c.visualStyle.value = vs,
                                ),
                            ],
                          )),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One selectable row for the style/audience tabs.
  Widget _optionRow({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? Dt.accent : Dt.textPrimary)),
          ),
          if (selected)
            const Icon(LucideIcons.check, size: 18, color: Dt.accent),
        ]),
      ),
    );
  }

  /// + sheet: file source + AI research live here now (composer stays lean).
  void _showPlusSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Obx(() {
          final file = c.sourceFile.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  file != null ? LucideIcons.fileCheck : LucideIcons.filePlus,
                  color: file != null ? Dt.accent : Dt.textSecondary,
                ),
                title: Text(
                  file != null
                      ? file.path.split('/').last
                      : 'Add Source (PDF/Docx/Pptx)',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: file != null
                    ? const Text('.pptx imports instantly; others feed the AI')
                    : null,
                trailing: file != null
                    ? IconButton(
                        tooltip: 'Remove source',
                        icon: const Icon(LucideIcons.x,
                            size: 18, color: AppColors.error),
                        onPressed: () => c.setSourceFile(null),
                      )
                    : null,
                onTap: () => _pickSourceFile(),
              ),
              SwitchListTile(
                secondary: Icon(
                  LucideIcons.flaskConical,
                  color: c.useResearch.value
                      ? Dt.accent
                      : Dt.textSecondary,
                ),
                title: Text('AI Research',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle:
                    const Text('Fetch live sources before generating'),
                value: c.useResearch.value,
                activeThumbColor: Dt.accent,
                onChanged: (v) => c.useResearch.value = v,
              ),
              ListTile(
                leading: Obx(() => Icon(
                      c.inputImage.value != null
                          ? LucideIcons.badgeCheck
                          : LucideIcons.imagePlus,
                      color: c.inputImage.value != null
                          ? Dt.accent
                          : Dt.textSecondary,
                    )),
                title: Obx(() => Text(
                      c.inputImage.value != null
                          ? 'Sketch attached'
                          : 'Attach Sketch for Vision',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    )),
                subtitle: c.inputImage.value != null
                    ? const Text('AI will use this as visual reference')
                    : null,
                trailing: c.inputImage.value != null
                    ? IconButton(
                        tooltip: 'Remove sketch',
                        icon: const Icon(LucideIcons.x,
                            size: 18, color: AppColors.error),
                        onPressed: () => c.inputImage.value = null,
                      )
                    : null,
                onTap: () => _pickInputImage(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _pickSourceFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'txt', 'md', 'pptx'],
      );
      if (result != null && result.files.single.path != null) {
        c.setSourceFile(File(result.files.single.path!));
      }
    } catch (_) {}
  }

  /// Compact slide-count stepper.
  Widget _countStepper(BuildContext context, bool isDark) {
    final disabled = c.generating.value;
    return Container(
      height: Dt.pillHeight,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: Dt.pillMuted,
        borderRadius: BorderRadius.circular(Dt.pillHeight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: disabled ? null : () => c.setCount(c.slideCount.value - 1),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.remove,
                  size: 14,
                  color: disabled ? Dt.textPlaceholder : Dt.textPrimary),
            ),
          ),
          Text('${c.slideCount.value}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5, fontWeight: FontWeight.w800)),
          InkWell(
            onTap: disabled ? null : () => c.setCount(c.slideCount.value + 1),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.add,
                  size: 14,
                  color: disabled ? Dt.textPlaceholder : Dt.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact audience-targeting pill with common presets.
  Future<void> _pickInputImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(LucideIcons.image),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(LucideIcons.camera),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (source == null) return;
    try {
      final file = await ImagePicker().pickImage(source: source);
      if (file != null) {
        c.inputImage.value = File(file.path);
      }
    } catch (_) {}
  }

  void _toggleSpeech() async {
    if (!_isListening) {
      bool available = await _stt.initialize();
      if (available) {
        _refresh(() => _isListening = true);
        _stt.listen(onResult: (val) {
          _refresh(() {
            _topicCtrl.text = val.recognizedWords;
            c.topic.value = val.recognizedWords;
          });
        });
      }
    } else {
      _refresh(() => _isListening = false);
      _stt.stop();
    }
  }

  void _showThemePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Slide Deck Theme',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Instant — no AI re-generate, content untouched.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5, color: Theme.of(context).hintColor)),
            const SizedBox(height: 12),
            Obx(() => Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final t in SlideThemePresets.all)
                      _themePresetCard(ctx, t,
                          selected: c.theme.value.name == t.name),
                  ],
                )),
            const Divider(height: 24),
            Text('Brand Kit',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Obx(() => Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Dt.pillMuted,
                    borderRadius: BorderRadius.circular(8),
                    image: c.theme.value.logoBytes != null
                        ? DecorationImage(image: MemoryImage(Uint8List.fromList(c.theme.value.logoBytes!)))
                        : null,
                  ),
                  child: c.theme.value.logoBytes == null
                      ? const Icon(LucideIcons.image, size: 20)
                      : null,
                )),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _pickLogo,
                  icon: const Icon(LucideIcons.upload, size: 16),
                  label: const Text('Upload Logo'),
                ),
                if (c.theme.value.logoBytes != null)
                  IconButton(
                    onPressed: () => _updateTheme(logo: []),
                    icon: const Icon(LucideIcons.trash2, size: 16, color: AppColors.error),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLogo() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file != null) {
        final bytes = await file.readAsBytes();
        _updateTheme(logo: bytes.toList());
      }
    } catch (_) {}
  }

  void _showTranslateDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Translate Deck'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Target language (e.g. Spanish, Bengali)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                c.translateDeck(ctrl.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Translate'),
          ),
        ],
      ),
    );
  }

  void _showLiveDataDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Inject Live Data'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'What to find? (e.g. Apple stock price)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                c.injectLiveData(ctrl.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Inject'),
          ),
        ],
      ),
    );
  }

  void _showUrlDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate from URL'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'https://example.com/article'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                c.generateFromUrl(ctrl.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  void _updateTheme({List<int>? logo}) {
    final old = c.theme.value;
    c.theme.value = SlideDeckTheme(
      name: old.name,
      primaryColor: old.primaryColor,
      secondaryColor: old.secondaryColor,
      backgroundColor: old.backgroundColor,
      textColor: old.textColor,
      accentColor: old.accentColor,
      fontHeading: old.fontHeading,
      fontBody: old.fontBody,
      logoBytes: logo ?? old.logoBytes,
    );
  }
}
