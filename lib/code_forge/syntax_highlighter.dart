import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:re_highlight/re_highlight.dart';

import '../LSP/lsp.dart';

/// Cached highlighting result for a single line
class HighlightedLine {
  final String text;
  final TextSpan? span;
  final int version;

  HighlightedLine(this.text, this.span, this.version);
}

/// Serializable span data for isolate communication
class _SpanData {
  final String text;
  final String? scope;
  final List<_SpanData> children;

  _SpanData(this.text, this.scope, [this.children = const []]);
}

/// List of semantic token type names (must match sematicMap['tokenTypes'] order)
final List<String> _semanticTokenTypes = (sematicMap['tokenTypes'] as List)
    .cast<String>();

/// Efficient syntax highlighter with caching, LSP semantic tokens, and optional isolate support
class SyntaxHighlighter {
  final Mode language;
  final Map<String, TextStyle> editorTheme;
  final TextStyle? baseTextStyle;
  final String? languageId;
  late final String _langId;
  late final Highlight _highlight;
  late final Map<String, List<String>> _semanticMapping;
  final Map<int, HighlightedLine> _grammarCache = {};
  final Map<int, HighlightedLine> _mergedCache = {};
  List<LspSemanticToken> _semanticTokens = [];
  List<int> _lineOffsets = [0];

  int _version = 0;
  static const int isolateThreshold = 500;
  VoidCallback? onHighlightComplete;

  SyntaxHighlighter({
    required this.language,
    required this.editorTheme,
    this.baseTextStyle,
    this.languageId,
    this.onHighlightComplete,
  }) {
    _langId = language.hashCode.toString();
    _highlight = Highlight();
    _highlight.registerLanguage(_langId, language);
    _semanticMapping = getSemanticMapping(languageId ?? '');
  }

  /// Update semantic tokens from LSP (call after getSemanticTokensFull or getSemanticTokensRange)
  void updateSemanticTokens(List<LspSemanticToken> tokens, String fullText) {
    _semanticTokens = tokens;
    _updateLineOffsets(fullText);
    _mergedCache.clear(); // Force re-merge
    _version++;
    onHighlightComplete?.call();
  }

  void _updateLineOffsets(String text) {
    _lineOffsets = [0];
    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      _lineOffsets.add(
        _lineOffsets.last + lines[i].length + 1,
      ); // +1 for newline
    }
  }

  /// Mark all lines as dirty (full rehighlight needed)
  void invalidateAll() {
    _grammarCache.clear();
    _mergedCache.clear();
    _version++;
  }

  /// Mark specific lines as dirty
  void invalidateLines(Set<int> lines) {
    for (final line in lines) {
      _grammarCache.remove(line);
      _mergedCache.remove(line);
    }
    _version++;
  }

  /// Mark a range of lines as dirty (for insertions/deletions)
  void invalidateRange(int startLine, int endLine) {
    for (int i = startLine; i <= endLine; i++) {
      _grammarCache.remove(i);
      _mergedCache.remove(i);
    }
    final keysToRemove = _grammarCache.keys.where((k) => k > endLine).toList();
    for (final key in keysToRemove) {
      _grammarCache.remove(key);
      _mergedCache.remove(key);
    }
    _version++;
  }

  /// Get highlighted TextSpan for a line, using cache if available
  /// This returns merged grammar + semantic highlighting
  TextSpan? getLineSpan(int lineIndex, String lineText) {
    final mergedCached = _mergedCache[lineIndex];
    if (mergedCached != null &&
        mergedCached.text == lineText &&
        mergedCached.version == _version) {
      return mergedCached.span;
    }

    TextSpan? grammarSpan;
    final grammarCached = _grammarCache[lineIndex];
    if (grammarCached != null && grammarCached.text == lineText) {
      grammarSpan = grammarCached.span;
    } else {
      grammarSpan = _highlightLine(lineText);
      _grammarCache[lineIndex] = HighlightedLine(
        lineText,
        grammarSpan,
        _version,
      );
    }

    TextSpan? mergedSpan;
    if (_semanticTokens.isNotEmpty && lineText.isNotEmpty) {
      mergedSpan = _applySemanticTokensToLine(lineIndex, lineText, grammarSpan);
    } else {
      mergedSpan = grammarSpan;
    }

    _mergedCache[lineIndex] = HighlightedLine(lineText, mergedSpan, _version);
    return mergedSpan;
  }

  TextSpan? _applySemanticTokensToLine(
    int lineIndex,
    String lineText,
    TextSpan? grammarSpan,
  ) {
    if (lineText.isEmpty) return grammarSpan;

    final lineTokens = _semanticTokens
        .where((t) => t.line == lineIndex)
        .toList();
    if (lineTokens.isEmpty) return grammarSpan;

    final styles = List<TextStyle?>.filled(lineText.length, null);
    if (grammarSpan != null) {
      _collectStyles(grammarSpan, styles, 0, grammarSpan.style);
    }

    final defaultColor = editorTheme['root']?.color ?? Colors.white;

    for (final token in lineTokens) {
      final semanticStyle = _resolveSemanticStyle(token.typeIndex);
      if (semanticStyle == null) continue;

      final start = token.start;
      final end = (token.start + token.length).clamp(0, lineText.length);

      for (int i = start; i < end && i < styles.length; i++) {
        final currentStyle = styles[i];
        if (currentStyle == null ||
            currentStyle.color == null ||
            currentStyle.color == defaultColor) {
          styles[i] = semanticStyle;
        }
      }
    }

    return _buildSpanFromStyles(lineText, styles);
  }

  int _collectStyles(
    TextSpan span,
    List<TextStyle?> styles,
    int offset,
    TextStyle? parentStyle,
  ) {
    final effectiveStyle = span.style ?? parentStyle;

    if (span.text != null) {
      for (
        int i = 0;
        i < span.text!.length && offset + i < styles.length;
        i++
      ) {
        styles[offset + i] = effectiveStyle;
      }
      offset += span.text!.length;
    }

    if (span.children != null) {
      for (final child in span.children!) {
        if (child is TextSpan) {
          offset = _collectStyles(child, styles, offset, effectiveStyle);
        }
      }
    }

    return offset;
  }

  TextSpan _buildSpanFromStyles(String text, List<TextStyle?> styles) {
    if (text.isEmpty) return TextSpan(style: baseTextStyle);

    final children = <TextSpan>[];
    int start = 0;

    while (start < text.length) {
      final currentStyle = styles[start];
      int end = start + 1;

      while (end < text.length && _stylesEqual(styles[end], currentStyle)) {
        end++;
      }

      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: currentStyle ?? baseTextStyle,
        ),
      );

      start = end;
    }

    if (children.length == 1) {
      return children.first;
    }

    return TextSpan(style: baseTextStyle, children: children);
  }

  bool _stylesEqual(TextStyle? a, TextStyle? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.color == b.color &&
        a.fontWeight == b.fontWeight &&
        a.fontStyle == b.fontStyle;
  }

  TextStyle? _resolveSemanticStyle(int typeIndex) {
    if (typeIndex < 0 || typeIndex >= _semanticTokenTypes.length) return null;

    final tokenType = _semanticTokenTypes[typeIndex];
    final hljsKeys = _semanticMapping[tokenType];
    if (hljsKeys == null) return null;

    for (final key in hljsKeys) {
      final style = editorTheme[key];
      if (style != null) return style;
    }

    return null;
  }

  TextSpan? _highlightLine(String lineText) {
    if (lineText.isEmpty) return null;

    try {
      final result = _highlight.highlight(code: lineText, language: _langId);
      final renderer = TextSpanRenderer(baseTextStyle, editorTheme);
      result.render(renderer);
      return renderer.span;
    } catch (e) {
      return TextSpan(text: lineText, style: baseTextStyle);
    }
  }

  /// Build a ui.Paragraph for a line with syntax highlighting
  ui.Paragraph buildHighlightedParagraph(
    int lineIndex,
    String lineText,
    ui.ParagraphStyle paragraphStyle,
    double fontSize,
    String? fontFamily, {
    double? width,
  }) {
    final span = getLineSpan(lineIndex, lineText);
    final builder = ui.ParagraphBuilder(paragraphStyle);

    if (span == null || lineText.isEmpty) {
      final style = _getUiTextStyle(null, fontSize, fontFamily);
      builder.pushStyle(style);
      builder.addText(lineText.isEmpty ? ' ' : lineText);
      final p = builder.build();
      p.layout(ui.ParagraphConstraints(width: width ?? double.infinity));
      return p;
    }

    _addTextSpanToBuilder(builder, span, fontSize, fontFamily);

    final p = builder.build();
    p.layout(ui.ParagraphConstraints(width: width ?? double.infinity));
    return p;
  }

  void _addTextSpanToBuilder(
    ui.ParagraphBuilder builder,
    TextSpan span,
    double fontSize,
    String? fontFamily,
  ) {
    final style = _textStyleToUiStyle(span.style, fontSize, fontFamily);
    builder.pushStyle(style);

    if (span.text != null) {
      builder.addText(span.text!);
    }

    if (span.children != null) {
      for (final child in span.children!) {
        if (child is TextSpan) {
          _addTextSpanToBuilder(builder, child, fontSize, fontFamily);
        }
      }
    }

    builder.pop();
  }

  ui.TextStyle _textStyleToUiStyle(
    TextStyle? style,
    double fontSize,
    String? fontFamily,
  ) {
    final baseStyle = style ?? baseTextStyle ?? editorTheme['root'];

    return ui.TextStyle(
      color: baseStyle?.color ?? editorTheme['root']?.color ?? Colors.black,
      fontSize: fontSize,
      fontFamily: fontFamily,
      fontWeight: baseStyle?.fontWeight,
      fontStyle: baseStyle?.fontStyle,
    );
  }

  ui.TextStyle _getUiTextStyle(
    String? className,
    double fontSize,
    String? fontFamily,
  ) {
    final themeStyle = className != null ? editorTheme[className] : null;
    final baseStyle = themeStyle ?? baseTextStyle ?? editorTheme['root'];

    return ui.TextStyle(
      color: baseStyle?.color ?? editorTheme['root']?.color ?? Colors.black,
      fontSize: fontSize,
      fontFamily: fontFamily,
      fontWeight: baseStyle?.fontWeight,
      fontStyle: baseStyle?.fontStyle,
    );
  }

  /// Pre-highlight visible lines asynchronously (for smoother scrolling)
  /// Note: This only does grammar-based highlighting. Call updateSemanticTokens separately.
  Future<void> preHighlightLines(
    int startLine,
    int endLine,
    String Function(int) getLineText,
  ) async {
    final linesToProcess = <int, String>{};

    for (int i = startLine; i <= endLine; i++) {
      final lineText = getLineText(i);
      final cached = _grammarCache[i];
      if (cached == null ||
          cached.text != lineText ||
          cached.version != _version) {
        linesToProcess[i] = lineText;
      }
    }

    if (linesToProcess.isEmpty) return;

    if (linesToProcess.length < 50) {
      for (final entry in linesToProcess.entries) {
        final span = _highlightLine(entry.value);
        _grammarCache[entry.key] = HighlightedLine(entry.value, span, _version);
      }
      onHighlightComplete?.call();
      return;
    }

    final results = await compute(
      _highlightLinesInBackground,
      _BackgroundHighlightData(
        langId: _langId,
        lines: linesToProcess,
        languageMode: language,
        theme: editorTheme,
        baseStyle: baseTextStyle,
      ),
    );

    for (final entry in results.entries) {
      final spanData = entry.value;
      final textSpan = spanData != null ? _spanDataToTextSpan(spanData) : null;
      _grammarCache[entry.key] = HighlightedLine(
        linesToProcess[entry.key]!,
        textSpan,
        _version,
      );
    }

    onHighlightComplete?.call();
  }

  TextSpan? _spanDataToTextSpan(_SpanData? data) {
    if (data == null) return null;

    final style = data.scope != null ? editorTheme[data.scope] : baseTextStyle;

    if (data.children.isEmpty) {
      return TextSpan(text: data.text, style: style);
    }

    return TextSpan(
      text: data.text.isEmpty ? null : data.text,
      style: style,
      children: data.children.map((c) => _spanDataToTextSpan(c)!).toList(),
    );
  }

  void dispose() {
    _grammarCache.clear();
    _mergedCache.clear();
    _semanticTokens.clear();
  }
}

/// Data class for background highlighting
class _BackgroundHighlightData {
  final String langId;
  final Map<int, String> lines;
  final Mode languageMode;
  final Map<String, TextStyle> theme;
  final TextStyle? baseStyle;

  _BackgroundHighlightData({
    required this.langId,
    required this.lines,
    required this.languageMode,
    required this.theme,
    this.baseStyle,
  });
}

Map<int, _SpanData?> _highlightLinesInBackground(
  _BackgroundHighlightData data,
) {
  final highlight = Highlight();
  highlight.registerLanguage(data.langId, data.languageMode);

  final results = <int, _SpanData?>{};

  for (final entry in data.lines.entries) {
    final lineIndex = entry.key;
    final lineText = entry.value;

    if (lineText.isEmpty) {
      results[lineIndex] = null;
      continue;
    }

    try {
      final result = highlight.highlight(code: lineText, language: data.langId);
      final renderer = TextSpanRenderer(data.baseStyle, data.theme);
      result.render(renderer);
      final span = renderer.span;
      results[lineIndex] = span != null ? _textSpanToSpanData(span) : null;
    } catch (e) {
      results[lineIndex] = _SpanData(lineText, null);
    }
  }

  return results;
}

/// Convert TextSpan to serializable span data
_SpanData _textSpanToSpanData(TextSpan span) {
  final children = <_SpanData>[];

  if (span.children != null) {
    for (final child in span.children!) {
      if (child is TextSpan) {
        children.add(_textSpanToSpanData(child));
      }
    }
  }

  String? scope;

  return _SpanData(span.text ?? '', scope, children);
}
