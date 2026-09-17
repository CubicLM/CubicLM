import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../controllers/browser_controller.dart';
import '../../theme/design_tokens.dart';
import '../../utils/export_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class BrowserFilesView extends StatefulWidget {
  const BrowserFilesView({super.key});

  @override
  State<BrowserFilesView> createState() => _BrowserFilesViewState();
}

class _BrowserFilesViewState extends State<BrowserFilesView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final BrowserController _browser = Get.find<BrowserController>();
  final RxList<ExportedFile> _downloadedFiles = <ExportedFile>[].obs;
  final RxBool _isLoading = false.obs;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    _isLoading.value = true;
    try {
      final files = await ExportFile.listAllFiles();
      _downloadedFiles.assignAll(files);
    } catch (_) {}
    _isLoading.value = false;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Dt.canvasDark : Dt.canvas,
      appBar: AppBar(
        title: Text('Downloads & Files', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Offline Pages'),
            Tab(text: 'Videos'),
            Tab(text: 'Documents'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOfflinePages(isDark),
          _buildFilesByCategory(['.mp4', '.mkv', '.webm', '.mov'], isDark),
          _buildFilesByCategory(['.pdf', '.txt', '.docx', '.pptx'], isDark),
        ],
      ),
    );
  }

  Widget _buildOfflinePages(bool isDark) {
    return Obx(() {
      if (_browser.offlinePages.isEmpty) {
        return _emptyState('No saved pages yet.');
      }
      return ListView.builder(
        itemCount: _browser.offlinePages.length,
        itemBuilder: (context, i) {
          final p = _browser.offlinePages[i];
          final title = p['title'] ?? '';
          final url = p['url'] ?? '';
          final path = p['path'] ?? '';
          return ListTile(
            leading: const Icon(LucideIcons.fileText),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(LucideIcons.trash2, size: 18),
              onPressed: () => _browser.deleteOfflinePage(i),
            ),
            onTap: () => _openFile(path, isWebArchive: true),
          );
        },
      );
    });
  }

  Widget _buildFilesByCategory(List<String> extensions, bool isDark) {
    return Obx(() {
      final filtered = _downloadedFiles.where((f) {
        final ext = '.${f.name.split('.').last.toLowerCase()}';
        return extensions.contains(ext);
      }).toList();

      if (_isLoading.value) return const Center(child: CircularProgressIndicator());
      if (filtered.isEmpty) return _emptyState('No files found.');

      return ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (context, i) {
          final f = filtered[i];
          return ListTile(
            leading: Icon(_iconForExt(f.name)),
            title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${f.sizeLabel} • ${f.dateLabel}'),
            trailing: IconButton(
              icon: const Icon(LucideIcons.trash2, size: 18),
              onPressed: () async {
                if (await ExportFile.deleteFile(f.path)) {
                  _refreshFiles();
                }
              },
            ),
            onTap: () => _openFile(f.path),
          );
        },
      );
    });
  }

  Widget _emptyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.folderOpen, size: 48, color: Dt.accent.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(message, style: GoogleFonts.plusJakartaSans(color: Colors.grey)),
        ],
      ),
    );
  }

  IconData _iconForExt(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['mp4', 'mkv', 'webm', 'mov'].contains(ext)) return LucideIcons.video;
    if (['pdf'].contains(ext)) return LucideIcons.fileText;
    if (['jpg', 'png', 'jpeg'].contains(ext)) return LucideIcons.image;
    return LucideIcons.file;
  }

  Future<void> _openFile(String path, {bool isWebArchive = false}) async {
    if (path.isEmpty) return;
    final ext = '.${path.split('.').last.toLowerCase()}';
    
    if (isWebArchive) {
      // Reload in browser
      _browser.addTab(url: 'file://$path');
      Get.back(); // Close files view
      return;
    }

    if (['.mp4', '.mkv', '.webm', '.mov'].contains(ext)) {
      Get.to(() => _InAppPlayer(filePath: path));
      return;
    }

    try {
      final uri = Uri.file(path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        Get.snackbar('Error', 'Could not open file.');
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to launch file viewer.');
    }
  }
}

class _InAppPlayer extends StatelessWidget {
  final String filePath;
  const _InAppPlayer({required this.filePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(filePath.split(Platform.pathSeparator).last,
            style: GoogleFonts.plusJakartaSans(fontSize: 14)),
      ),
      body: Center(
        child: InAppWebView(
          initialData: InAppWebViewInitialData(
            data: '''
              <!DOCTYPE html>
              <html>
              <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                  body { margin: 0; background: black; display: flex; align-items: center; justify-content: center; height: 100vh; }
                  video { width: 100%; max-height: 100vh; }
                </style>
              </head>
              <body>
                <video controls autoplay>
                  <source src="file://$filePath" type="video/mp4">
                  Your browser does not support the video tag.
                </video>
              </body>
              </html>
            ''',
          ),
          initialSettings: InAppWebViewSettings(
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,
          ),
        ),
      ),
    );
  }
}
