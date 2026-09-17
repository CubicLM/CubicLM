import 'package:cubiclm/services/browser/browser_download_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildRangeHeader', () {
    test('formats byte offset', () {
      expect(buildRangeHeader(0), 'bytes=0-');
      expect(buildRangeHeader(1024), 'bytes=1024-');
    });
  });

  group('parseContentRangeTotal', () {
    test('parses complete length', () {
      expect(parseContentRangeTotal('bytes 0-1023/2048'), 2048);
      expect(parseContentRangeTotal('bytes 1024-2047/4096'), 4096);
    });

    test('returns null for unknown or malformed', () {
      expect(parseContentRangeTotal(null), isNull);
      expect(parseContentRangeTotal(''), isNull);
      expect(parseContentRangeTotal('bytes 0-99/*'), isNull);
      expect(parseContentRangeTotal('garbage'), isNull);
    });
  });

  group('BrowserDownload model', () {
    test('progress clamps and labels', () {
      final d = BrowserDownload(
        id: '1',
        url: 'https://example.com/f.zip',
        fileName: 'f.zip',
        initialReceived: 512,
        initialTotal: 1024,
      );
      expect(d.progress, 0.5);
      expect(d.progressLabel, contains('/'));
      expect(d.isActive, isTrue); // default status is queued
    });

    test('queued counts as active, paused as resumable', () {
      final q = BrowserDownload(id: 'a', url: 'https://x', fileName: 'a');
      expect(q.isActive, isTrue);
      expect(q.isResumable, isFalse);

      final p = BrowserDownload(
        id: 'b',
        url: 'https://x',
        fileName: 'b',
        initialStatus: BrowserDownloadStatus.paused,
      );
      expect(p.isActive, isFalse);
      expect(p.isResumable, isTrue);

      final f = BrowserDownload(
        id: 'c',
        url: 'https://x',
        fileName: 'c',
        initialStatus: BrowserDownloadStatus.failed,
      );
      expect(f.isResumable, isTrue);
    });

    test('unknown total shows bytes only', () {
      final d = BrowserDownload(
        id: '1',
        url: 'https://x',
        fileName: 'a',
        initialReceived: 100,
      );
      expect(d.progress, 0);
      expect(d.progressLabel, '100B');
    });

    test('toJson/fromJson round-trip', () {
      final d = BrowserDownload(
        id: 'abc',
        url: 'https://example.com/v.mp4',
        fileName: 'v.mp4',
        mimeType: 'video/mp4',
        initialStatus: BrowserDownloadStatus.paused,
        initialReceived: 10,
        initialTotal: 100,
      );
      final back =
          BrowserDownload.fromJson(Map<String, dynamic>.from(d.toJson()));
      expect(back.id, 'abc');
      expect(back.url, 'https://example.com/v.mp4');
      expect(back.fileName, 'v.mp4');
      expect(back.mimeType, 'video/mp4');
      expect(back.status.value, BrowserDownloadStatus.paused);
      expect(back.received.value, 10);
      expect(back.total.value, 100);
    });

    test('in-flight jobs restore as paused', () {
      final d = BrowserDownload.fromJson({
        'id': 'x',
        'url': 'https://example.com/f',
        'fileName': 'f',
        'status': 'downloading',
      });
      expect(d.status.value, BrowserDownloadStatus.paused);
    });

    test('bad status restores as failed', () {
      final d = BrowserDownload.fromJson({
        'id': 'x',
        'url': 'https://example.com/f',
        'fileName': 'f',
        'status': 'nope',
      });
      expect(d.status.value, BrowserDownloadStatus.failed);
    });
  });
}
