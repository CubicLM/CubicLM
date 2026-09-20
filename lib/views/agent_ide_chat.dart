/// Chat pane, actions, templates, terminal colors.
///
/// Split from `agent_ide_view.dart` - behavior is unchanged.
/// Contains: _chatPane(), _actionButton(), _splitOrPreview(), _templateGrid(), _termColor()
part of 'agent_ide_view.dart';

extension _AgentIdeChat on _AgentIdeViewState {
  Widget _chatPane(BuildContext context, bool isDark) {
    return Obx(() {
      final planPending = c.pendingPlan.value != null;
      final hasDiffs = c.lastDiffs.isNotEmpty;
      final itemCount = c.transcript.length + 
          (planPending ? 1 : 0) + 
          (hasDiffs ? 1 : 0);

      if (itemCount == 0) {
        final hasProject = c.project.value != null;
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: hasProject
                ? Text(
                    'No conversation yet.\nDescribe the project above or ask for changes below — every exchange lands here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        height: 1.5,
                        color: Theme.of(context).hintColor),
                  )
                : _templateGrid(context, isDark),
          ),
        );
      }
      return ListView.builder(
        controller: _chatScroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: itemCount,
        itemBuilder: (_, i) {
          var idx = i;
          if (hasDiffs && idx == c.transcript.length + (planPending ? 1 : 0)) {
            return diffCard(context, isDark);
          }
          if (planPending && idx == c.transcript.length) {
            return planCard(context, isDark);
          }
          final m = c.transcript[idx];
          final role = m['role'];
          if (role == 'activity') {
            final steps = m['steps'] as List<Map<String, String>>?;
            return activityCard(context, isDark, steps: steps);
          }
          final user = role == 'user';
          return Align(
            alignment: user ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.85),
              decoration: BoxDecoration(
                color: user
                    ? Dt.accent
                    : (isDark ? AppColors.surface : const Color(0xFFFFFFFF)),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(user ? 16 : 4),
                  bottomRight: Radius.circular(user ? 4 : 16),
                ),
                border: !user && !isDark 
                    ? Border.all(color: Dt.hairline) 
                    : null,
                boxShadow: !user ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ] : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: m['text'] ?? '',
                    selectable: true,
                    extensionSet: md.ExtensionSet(
                      [const ComponentSyntax(), const ArchitectureSyntax(), ...md.ExtensionSet.gitHubFlavored.blockSyntaxes],
                      [...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
                    ),
                    builders: {
                      'component': ComponentElementBuilder(isDark: isDark),
                      'architecture': ArchitectureElementBuilder(
                        isDark: isDark,
                        onNodeClick: (name) => _openFileTab(name),
                      ),
                    },
                    styleSheet: MarkdownStyleSheet(
                      p: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          height: 1.5,
                          color: user
                              ? Colors.white
                              : (isDark ? AppColors.textPrimary : Dt.textPrimary)),
                      code: GoogleFonts.firaCode(
                          fontSize: 12,
                          backgroundColor: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.05)),
                      codeblockDecoration: BoxDecoration(
                        color: isDark ? Colors.black38 : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                      ),
                    ),
                  ),
                  if (!user && m['has_build'] == true) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _actionButton(
                          context,
                          isDark,
                          LucideIcons.eye,
                          'Preview',
                          () => _refresh(() => _tab = 'preview'),
                        ),
                        const SizedBox(width: 8),
                        _actionButton(
                          context,
                          isDark,
                          LucideIcons.fileCode,
                          'Code',
                          () => _refresh(() => _tab = 'files'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    });
  }

  Widget _actionButton(BuildContext context, bool isDark, IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : Dt.hairline,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Dt.accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textPrimary : Dt.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _splitOrPreview(BuildContext context, bool isDark) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (!isLandscape) {
      return _previewPane(context, isDark, c.revision.value);
    }
    return Row(children: [
      Expanded(
        flex: 3,
        child: _previewPane(context, isDark, c.revision.value),
      ),
      Container(
        width: 1,
        color: isDark ? Colors.white.withValues(alpha: 0.07) : Dt.hairline,
      ),
      Expanded(
        flex: 2,
        child: _filesPane(context, isDark),
      ),
    ]);
  }

  Widget _templateGrid(BuildContext context, bool isDark) {
    final templates = [
      const WebTemplate(
          'Landing Page',
          LucideIcons.rocket,
          'Marketing page with hero, features, CTA, footer',
          'Build a modern landing page with: hero section with gradient background and CTA button, features grid (3 cards with icons), testimonial section, email signup form, and footer with links. Use a professional color scheme (indigo/blue). Responsive layout.',
          'Single HTML'),
      const WebTemplate(
          'Dashboard',
          LucideIcons.layoutDashboard,
          'Admin panel with sidebar, charts, stats',
          'Build an admin dashboard with: left sidebar navigation (5 items with icons), top bar with search and user avatar, 4 stat cards (revenue, users, orders, growth), a line chart placeholder, a data table with 5 rows, and a dark sidebar with light content area. Use Tailwind-style colors.',
          'HTML + CSS + JS'),
      const WebTemplate(
          'Portfolio',
          LucideIcons.user,
          'Personal portfolio with projects and contact',
          'Build a personal portfolio site with: animated hero with name and title, about section with photo placeholder and bio, projects grid (4 project cards with images and tech tags), skills section with progress bars, contact form, and smooth scroll navigation. Dark theme with accent color.',
          'Single HTML'),
      const WebTemplate(
          'Blog',
          LucideIcons.fileText,
          'Blog with posts, sidebar, and categories',
          'Build a blog homepage with: header with site name and nav, featured post hero, 3 article cards with image/title/excerpt/date, sidebar with categories and recent posts, newsletter signup, and footer. Clean typography, warm color palette.',
          'HTML + CSS + JS'),
      const WebTemplate(
          'E-commerce',
          LucideIcons.shoppingCart,
          'Product grid with cart and filters',
          'Build a product listing page with: top nav with logo, search bar, and cart icon with badge, filter sidebar (category, price range), product grid (6 product cards with image, name, price, rating stars, add-to-cart button), and a mini cart dropdown. Modern clean design.',
          'HTML + CSS + JS'),
      const WebTemplate(
          'SaaS Page',
          LucideIcons.globe,
          'Product page with pricing tiers',
          'Build a SaaS product page with: sticky nav, hero with product mockup, 3-step how-it-works section, pricing table (3 tiers: Free/Pro/Enterprise with feature comparison), customer logos bar, FAQ accordion, and CTA footer. Gradient accents, professional look.',
          'Single HTML'),
    ];
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Start from a template',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).hintColor)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.6,
            ),
            itemCount: templates.length,
            itemBuilder: (_, i) {
              final t = templates[i];
              return GestureDetector(
                onTap: () {
                  _askCtrl.text = t.prompt;
                  _askFocus.requestFocus();
                  AppSnackbar.showTop(
                    'Template inserted',
                    'Framework: ${c.framework.value} — change it from the composer if needed.',
                    logHistory: false,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surface : const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Dt.hairline),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(t.icon, size: 16, color: Dt.accent),
                        const SizedBox(height: 6),
                        Text(t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(t.desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                color: Theme.of(context).hintColor)),
                      ]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Color _termColor(String line) {
    if (line.contains('✗')) return const Color(0xFFF48771);
    if (line.contains('✓')) return const Color(0xFFA6E3A1);
    if (line.contains('⚙')) return const Color(0xFFCBA6F7);
    if (line.contains('■')) return const Color(0xFFFAB387);
    if (line.startsWith('[') && line.contains('> ')) {
      return const Color(0xFF89DCEB);
    }
    return const Color(0xFFCDD6F4);
  }
}
