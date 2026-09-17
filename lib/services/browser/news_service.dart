import 'package:http/http.dart' as http;
import 'package:get/get.dart';
import 'package:xml/xml.dart';
import '../../controllers/chat_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../core/constants.dart';
import '../hive_service.dart';

class NewsItem {
  final String title;
  final String link;
  final String pubDate;
  String summary = '';

  NewsItem({required this.title, required this.link, required this.pubDate});
}

class NewsService extends GetxService {
  final RxList<NewsItem> news = <NewsItem>[].obs;
  final RxBool isLoading = false.obs;

  static const String rssUrl = 'https://news.google.com/rss/search?q=artificial+intelligence&hl=en-US&gl=US&ceid=US:en';

  Future<void> fetchNews({bool force = false}) async {
    final settings = Get.find<SettingsController>();
    final hive = Get.find<HiveService>();
    final lastFetch = hive.getSetting<int>(AppConstants.keyBrowserNewsLastFetch) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Fetch once per hour unless forced
    if (!force && (now - lastFetch < 3600000) && news.isNotEmpty) return;

    isLoading.value = true;
    try {
      final categories = settings.browserNewsCategories.join('+OR+');
      final query = Uri.encodeComponent(categories.isEmpty ? 'artificial intelligence' : categories);
      final url = 'https://news.google.com/rss/search?q=$query&hl=en-US&gl=US&ceid=US:en';
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final items = document.findAllElements('item').take(5);
        
        final List<NewsItem> fetched = [];
        for (var node in items) {
          fetched.add(NewsItem(
            title: node.findElements('title').first.innerText,
            link: node.findElements('link').first.innerText,
            pubDate: node.findElements('pubDate').first.innerText,
          ));
        }
        
        news.assignAll(fetched);
        await hive.setSetting(AppConstants.keyBrowserNewsLastFetch, now);
        
        // Generate summaries in background
        _summarizeAll();
      }
    } catch (e) {
      print('[NewsService] Error fetching news: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _summarizeAll() async {
    for (var item in news) {
      if (item.summary.isNotEmpty) continue;
      item.summary = await _summarizeHeadline(item.title);
      news.refresh();
    }
  }

  Future<String> _summarizeHeadline(String title) async {
    try {
      // Silent one-shot teaser via the active engine (cloud or local).
      // Falls back to a trimmed headline when no engine is available.
      final teaser = await Get.find<ChatController>().askOnce(
        'Write a single short teaser sentence (max 15 words) for this news headline. Return ONLY the sentence:\n\n$title',
        maxTokens: 60,
        source: 'news',
      );
      if (teaser != null && teaser.trim().isNotEmpty) return teaser.trim();
      return 'Latest update on AI: ${title.split(' - ').first}';
    } catch (_) {
      return '';
    }
  }
}
