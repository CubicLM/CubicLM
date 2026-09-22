/// Add/edit MCP server bottom sheet.
///
/// Split from `explore_skills_mcp_tabs.dart` - behavior is unchanged.
/// Contains: existing, McpServerSheet(), createState(), _nameCtrl, _urlCtrl, _tokenCtrl, true, false, false
///   initState(), dispose(), _validateUrl(), _save(), build()
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/colors.dart';
import '../services/mcp/mcp_config.dart';
import '../services/mcp/mcp_registry_service.dart';
import '../theme/design_tokens.dart';

/// Add/edit bottom sheet for one MCP server. Shared entry point for
/// server management (Explore list; Settings links here).
class McpServerSheet extends StatefulWidget {
  final McpConfig? existing;
  const McpServerSheet({super.key, this.existing});

  @override
  State<McpServerSheet> createState() => _McpServerSheetState();
}

class _McpServerSheetState extends State<McpServerSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _tokenCtrl;
  bool _obscure = true;
  bool _saving = false;
  bool _testing = false;

  McpRegistryService get _reg => Get.find<McpRegistryService>();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _urlCtrl = TextEditingController(text: e?.url ?? '');
    _tokenCtrl = TextEditingController();
    if (e != null) {
      _reg.getToken(e.id).then((v) {
        if (mounted && v != null) _tokenCtrl.text = v;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  String? _validateUrl(String url) {
    if (url.isEmpty) return 'Please enter your MCP server URL';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return 'Must be http(s)://â€¦';
    }
    return null;
  }

  Future<void> _save({bool andTest = false}) async {
    final name = _nameCtrl.text.trim().isEmpty
        ? 'Custom MCP'
        : _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    final bad = _validateUrl(url);
    if (bad != null) {
      Get.snackbar('Invalid URL', bad, snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (andTest) {
      setState(() => _testing = true);
    } else {
      setState(() => _saving = true);
    }
    try {
      final existing = widget.existing;
      final token = _tokenCtrl.text.trim();
      final cfg = McpConfig(
        id: existing?.id ?? '',
        name: name,
        url: url,
        transport: McpConfig.inferTransport(url),
        authType:
            token.isEmpty ? McpAuthType.none : McpAuthType.bearer,
        enabled: existing?.enabled ?? false,
      );
      await _reg.saveConfig(cfg).then((savedId) async {
        await _reg.setToken(savedId, token);
        if (andTest) {
          try {
            await _reg.testConnection(savedId);
            Get.snackbar('Connected', 'Server responded',
                snackPosition: SnackPosition.BOTTOM,
                backgroundColor: AppColors.success,
                colorText: Colors.white);
          } catch (e) {
            Get.snackbar('Connection failed', '$e',
                snackPosition: SnackPosition.BOTTOM,
                backgroundColor: AppColors.error,
                colorText: Colors.white,
                duration: const Duration(seconds: 4));
          }
        } else {
          Get.snackbar('Saved', 'MCP server saved',
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: AppColors.success,
              colorText: Colors.white);
          if (mounted) Navigator.pop(context);
        }
      });
    } catch (e) {
      Get.snackbar('Save failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _testing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final editing = widget.existing != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceLight : Dt.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(editing ? 'Edit MCP server' : 'Add MCP server',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                      labelText: 'Server name',
                      hintText: 'My MCP Server',
                      prefixIcon:
                          const Icon(LucideIcons.tag, size: 18),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true)),
              const SizedBox(height: 12),
              TextField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                      labelText: 'Server URL (http/s)',
                      hintText: 'https://mcp.example.com/mcp',
                      prefixIcon:
                          const Icon(LucideIcons.link2, size: 18),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true)),
              const SizedBox(height: 12),
              TextField(
                  controller: _tokenCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                      labelText: 'Bearer token (optional)',
                      hintText: 'Paste API key / token',
                      prefixIcon:
                          const Icon(LucideIcons.keyRound, size: 18),
                      suffixIcon: IconButton(
                          icon: Icon(
                              _obscure
                                  ? LucideIcons.eyeOff
                                  : LucideIcons.eye,
                              size: 18),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true)),
              const SizedBox(height: 4),
              Text('Token stored in secure storage, never in Hive.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: Theme.of(context).hintColor)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: FilledButton.icon(
                        onPressed:
                            _saving ? null : () => _save(),
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(LucideIcons.save, size: 16),
                        label: Text(_saving ? 'Savingâ€¦' : 'Save',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        style: FilledButton.styleFrom(
                            backgroundColor: Dt.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 10)))),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                    onPressed: _testing
                        ? null
                        : () => _save(andTest: true),
                    icon: const Icon(LucideIcons.activity, size: 16),
                    label: Text(_testing ? 'Testingâ€¦' : 'Test',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Dt.accent,
                        side: BorderSide(
                            color:
                                Dt.accent.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10))),
              ]),
            ],
          ),
        ),
      ),
    );
  }

}
