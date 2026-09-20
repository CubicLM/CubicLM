/// Markdown citation-link builder with RAG + web-source chips.
///
/// Split from `chat_bubble.dart` - standalone class.
/// Contains: context, citations, webSources, itationLinkBuilder(), visitElementAfter()
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/web_source.dart';
import 'citation_chip.dart';

class CitationLinkBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  final List<Map<String, dynamic>>? citations;
  final List<WebSource>? webSources;

  CitationLinkBuilder(this.context, this.citations, this.webSources);

  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    final href = element.attributes['href'];
    if (href != null && href.startsWith('cite:')) {
      final index = int.tryParse(href.substring(5)) ?? 0;

      // Priority 1: Semantic citations (RAG)
      if (citations != null && index > 0 && index <= citations!.length) {
        final citation = citations![index - 1];
        return CitationChip(
          index: index,
          source: citation['source'] ?? 'Unknown Source',
          page: citation['pageNumber'],
        );
      }

      // Priority 2: Web sources
      if (webSources != null && index > 0 && index <= webSources!.length) {
        final src = webSources![index - 1];
        return CitationChip(
          index: index,
          source: src.title.isNotEmpty ? src.title : src.domain,
          url: src.url,
        );
      }

      return CitationChip(
        index: index,
        source: 'Source $index',
      );
    }
    return null;
  }
}
