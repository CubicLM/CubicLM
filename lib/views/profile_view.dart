/// Profile page: avatar picker, editable name, profession chips,
/// member stats. Opened from the Settings header icon and the chat
/// sidebar identity footer.
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/chat_controller.dart';
import '../controllers/profile_controller.dart';
import 'hub/hub_widgets.dart';

/// Standalone profile page.
class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: const _ProfileBody(),
    );
  }
}

class _ProfileBody extends StatefulWidget {
  const _ProfileBody();

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> {
  final _nameCtrl = TextEditingController();
  bool _nameInit = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  ProfileController? get _profile {
    try {
      return Get.find<ProfileController>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveName() async {
    final p = _profile;
    if (p == null) return;
    final v = _nameCtrl.text.trim();
    if (v.isEmpty) {
      Get.snackbar('Name needed', 'Please enter your name first',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    await p.saveName(v);
    if (mounted) {
      Get.snackbar('Saved', 'Nice to meet you, $v',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2));
    }
  }

  void _openAvatarPicker(ProfileController p) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pick your avatar',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: ProfileController.avatars.length,
                itemBuilder: (_, i) {
                  final emoji = ProfileController.avatars[i];
                  final sel = p.avatar.value == emoji;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      p.setAvatar(emoji, p.avatarColor.value);
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: sel
                            ? Theme.of(context)
                                .primaryColor
                                .withValues(alpha: 0.15)
                            : Theme.of(context)
                                .hintColor
                                .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: sel
                            ? Border.all(
                                color: Theme.of(context).primaryColor,
                                width: 2)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              Text('Ring color',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (int i = 0;
                      i < ProfileController.avatarColors.length;
                      i++)
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        p.setAvatar(p.avatar.value, i);
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color:
                              Color(ProfileController.avatarColors[i]),
                          shape: BoxShape.circle,
                          border: p.avatarColor.value == i
                              ? Border.all(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  width: 2.5)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    if (p == null) return const SizedBox.shrink();
    return Obx(() {
      if (!_nameInit) {
        _nameCtrl.text = p.name.value;
        _nameInit = true;
      }
      final memberSince = p.setupAt.value > 0
          ? DateTime.fromMillisecondsSinceEpoch(p.setupAt.value)
          : null;
      final memberStr = memberSince == null
          ? '—'
          : '${memberSince.day}/${memberSince.month}/${memberSince.year}';
      int chatCount = 0;
      try {
        chatCount = Get.find<ChatController>().sessions.length;
      } catch (_) {}

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          // ── Avatar ──
          Center(
            child: Stack(
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(ProfileController
                            .avatarColors[p.safeAvatarColor])
                        .withValues(alpha: 0.18),
                    border: Border.all(
                      color: Color(ProfileController
                          .avatarColors[p.safeAvatarColor]),
                      width: 3,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(p.avatar.value,
                      style: const TextStyle(fontSize: 52)),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: InkWell(
                    onTap: () => _openAvatarPicker(p),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.pencil,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              p.hasName ? p.name.value : 'Welcome!',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          if (p.profession.value.isNotEmpty) ...[
            const SizedBox(height: 2),
            Center(
              child: Text(p.profession.value,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).hintColor)),
            ),
          ],
          const SizedBox(height: 24),
          // ── Name ──
          const HubSectionTitle('Your name'),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'e.g. Abir Hasan',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                onSubmitted: (_) => _saveName(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _saveName,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.all(14),
              ),
              child: const Icon(LucideIcons.check, size: 20),
            ),
          ]),
          const SizedBox(height: 20),
          // ── Profession ──
          const HubSectionTitle('I am a…'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final prof in ProfileController.professions)
                ChoiceChip(
                  label: Text(prof,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  selected: p.profession.value == prof,
                  onSelected: (_) => p.setProfession(prof),
                ),
            ],
          ),
          const SizedBox(height: 20),
          // ── Stats ──
          const HubSectionTitle('About'),
          _infoRow(context, LucideIcons.calendarDays, 'Member since',
              memberStr),
          _infoRow(context, LucideIcons.messageSquare, 'Chats', '$chatCount'),
          _infoRow(context, LucideIcons.user, 'Profession',
              p.profession.value.isEmpty ? 'Not set' : p.profession.value),
        ],
      );
    });
  }

  Widget _infoRow(
      BuildContext context, IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        ),
      ),
      child: Row(children: [
        Icon(icon, size: 17, color: Theme.of(context).primaryColor),
        const SizedBox(width: 12),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).hintColor)),
      ]),
    );
  }
}
