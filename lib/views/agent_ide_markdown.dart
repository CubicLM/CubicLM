/// Markdown extensions for the Agent IDE: architecture diagrams and
/// component blocks with interactive builders.
///
/// Split from `agent_ide_view.dart` — standalone classes, no shared
/// state. Behavior is unchanged.
/// Contains: RegExp(), ArchitectureSyntax(), parse(), isDark, Function(), rchitectureElementBuilder()
///   visitElementAfter(), _buildNode(), RegExp(), ComponentSyntax(), parse(), isDark
///   omponentElementBuilder(), visitElementAfter()
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:markdown/markdown.dart' as md;

import 'cubicweb/component_card.dart';

class ArchitectureSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^<architecture>');

  const ArchitectureSyntax();

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    final childLines = <String>[];
    while (!parser.isDone && !parser.current.content.contains('</architecture>')) {
      childLines.add(parser.current.content);
      parser.advance();
    }
    if (!parser.isDone) parser.advance();
    return md.Element('architecture', [])
      ..children!.add(md.Text(childLines.join('\n')));
  }
}

class ArchitectureElementBuilder extends MarkdownElementBuilder {
  final bool isDark;
  final Function(String) onNodeClick;
  ArchitectureElementBuilder({required this.isDark, required this.onNodeClick});

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.blueAccent.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.gitBranch, size: 16, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Text('INTERACTIVE ARCHITECTURE', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Colors.blueAccent)),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: lines.map((line) {
              if (line.contains('->')) {
                final parts = line.split('->');
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildNode(parts[0].trim().replaceAll('[', '').replaceAll(']', '')),
                    const Icon(LucideIcons.arrowRight, size: 12, color: Colors.grey),
                    _buildNode(parts[1].trim().replaceAll('[', '').replaceAll(']', '')),
                  ],
                );
              }
              return _buildNode(line.trim().replaceAll('[', '').replaceAll(']', ''));
            }).toList(),
          ),
          const SizedBox(height: 8),
          const Text('Tap a component to open its code', style: TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildNode(String name) {
    return InkWell(
      onTap: () => onNodeClick(name),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? Colors.black26 : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Text(
          name,
          style: GoogleFonts.firaCode(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueAccent),
        ),
      ),
    );
  }
}

class ComponentSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^<component name="([^"]+)">');

  const ComponentSyntax();

  @override
  md.Node parse(md.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content)!;
    final name = match.group(1)!;
    parser.advance();
    final childLines = <String>[];
    while (!parser.isDone && !parser.current.content.contains('</component>')) {
      childLines.add(parser.current.content);
      parser.advance();
    }
    if (!parser.isDone) parser.advance();
    return md.Element('component', [])
      ..attributes['name'] = name
      ..children!.add(md.Text(childLines.join('\n')));
  }
}

class ComponentElementBuilder extends MarkdownElementBuilder {
  final bool isDark;
  ComponentElementBuilder({required this.isDark});

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final name = element.attributes['name'] ?? 'Component';
    final code = element.textContent;
    return ComponentPromotionCard(name: name, code: code, isDark: isDark);
  }
}
