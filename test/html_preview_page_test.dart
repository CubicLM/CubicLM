import 'package:cubiclm/widgets/html_preview_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HtmlPreviewPage.fileNameFor', () {
    test('slugifies titles', () {
      expect(HtmlPreviewPage.fileNameFor('Snake Game'),
          'snake_game.html');
      expect(HtmlPreviewPage.fileNameFor('  My Cool Game!! v2  '),
          'my_cool_game_v2.html');
    });

    test('falls back for empty titles', () {
      expect(HtmlPreviewPage.fileNameFor(''), 'preview.html');
      expect(HtmlPreviewPage.fileNameFor('!!!'), 'preview.html');
    });

    test('caps length at 40 chars + extension', () {
      final name = HtmlPreviewPage.fileNameFor(
          'a very long game title that goes on and on forever');
      expect(name.endsWith('.html'), isTrue);
      expect(name.length, lessThanOrEqualTo(45));
    });

    test('strips unsafe filesystem characters', () {
      final name =
          HtmlPreviewPage.fileNameFor('game: "final"/v1\\?.html');
      expect(RegExp(r'^[a-z0-9_]+\.html$').hasMatch(name), isTrue);
    });
  });
}
