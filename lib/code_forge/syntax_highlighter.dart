import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:re_highlight/re_highlight.dart';

import '../LSP/lsp.dart';

class SemanticWordSpan {
  final int startChar;
  final int endChar;
  final String word;
  final TextStyle style;

  SemanticWordSpan({
    required this.startChar,
    required this.endChar,
    required this.word,
    required this.style,
  });
}

class HighlightedLine {
  final String text;
  final TextSpan? span;
  final int version;

  HighlightedLine(this.text, this.span, this.version);
}

class _SpanData {
  final String text;
  final String? scope;
  final List<_SpanData> children;

  _SpanData(this.text, this.scope, [this.children = const []]);
}

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
  final Map<int, List<SemanticWordSpan>> _lineSemanticSpans = {};
  final Map<String, TextSpan?> _lineSpanCache = {};
  bool _isEditing = false;
  int _version = 0;
  int _documentVersion = 0;
  static const int isolateThreshold = 500;
  int get documentVersion => _documentVersion;

  SyntaxHighlighter({
    required this.language,
    required this.editorTheme,
    this.baseTextStyle,
    this.languageId,
  }) {
    _langId = language.hashCode.toString();
    _highlight = Highlight();
    _highlight.registerLanguage(_langId, language);
    _semanticMapping = getSemanticMapping(languageId ?? '');
  }

  void updateSemanticTokens(List<LspSemanticToken> tokens, String fullText) {
    _lineSemanticSpans.clear();
    final lines = fullText.split('\n');

    for (final token in tokens) {
      if (token.line < lines.length) {
        final lineText = lines[token.line];
        final start = token.start.clamp(0, lineText.length);
        final end = (token.start + token.length).clamp(0, lineText.length);

        if (start < end) {
          final word = lineText.substring(start, end);
          final style = _resolveSemanticStyle(token.tokenTypeName);

          if (style != null && word.isNotEmpty) {
            final lineSpans = _lineSemanticSpans.putIfAbsent(
              token.line,
              () => [],
            );
            lineSpans.add(
              SemanticWordSpan(
                startChar: start,
                endChar: end,
                word: word,
                style: style,
              ),
            );
          }
        }
      }
    }

    for (final spans in _lineSemanticSpans.values) {
      spans.sort((a, b) => a.startChar.compareTo(b.startChar));
    }

    _isEditing = false;
    _lineSpanCache.clear();
    _mergedCache.clear();
    _grammarCache.clear();
    _version++;
  }

  void applyDocumentEdit(
    int editStart,
    int oldEnd,
    String insertedText,
    String fullText,
  ) {
    _documentVersion++;
    _isEditing = true;
    _version++;
  }

  void invalidateAll() {
    _grammarCache.clear();
    _mergedCache.clear();
    _documentVersion++;
    _version++;
  }

  void invalidateLines(Set<int> lines) {
    for (final line in lines) {
      _grammarCache.remove(line);
      _mergedCache.remove(line);
    }
    _version++;
  }

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

  TextSpan? getLineSpan(int lineIndex, String lineText) {
    if (_lineSpanCache.containsKey(lineText)) {
      return _lineSpanCache[lineText];
    }

    final grammarSpan = _highlightLine(lineText);

    if (_isEditing) {
      _lineSpanCache[lineText] = grammarSpan;
      return grammarSpan;
    }

    final semanticSpans = _lineSemanticSpans[lineIndex];
    final mergedSpan = _mergeGrammarAndSemantic(
      lineText,
      grammarSpan,
      semanticSpans,
    );

    _lineSpanCache[lineText] = mergedSpan;
    _mergedCache[lineIndex] = HighlightedLine(lineText, mergedSpan, _version);

    return mergedSpan;
  }

  TextSpan? _mergeGrammarAndSemantic(
    String lineText,
    TextSpan? grammarSpan,
    List<SemanticWordSpan>? semanticSpans,
  ) {
    if (lineText.isEmpty) {
      return grammarSpan;
    }

    if (semanticSpans == null || semanticSpans.isEmpty) {
      return grammarSpan;
    }

    final grammarSegments = <({String text, TextStyle? style})>[];
    _flattenGrammarSpan(grammarSpan, grammarSegments, baseTextStyle);

    final children = <TextSpan>[];
    int currentPos = 0;

    for (final semantic in semanticSpans) {
      final semanticStart = semantic.startChar.clamp(0, lineText.length);
      final semanticEnd = semantic.endChar.clamp(0, lineText.length);

      if (semanticStart > currentPos) {
        _addGrammarSegments(
          children,
          grammarSegments,
          currentPos,
          semanticStart,
          lineText,
        );
      }

      if (semanticStart < semanticEnd) {
        final actualText = lineText.substring(semanticStart, semanticEnd);

        final grammarStyle = _getStyleAtPosition(
          grammarSegments,
          semanticStart,
        );
        if (_isStringOrCommentStyle(grammarStyle)) {
          children.add(TextSpan(text: actualText, style: grammarStyle));
        } else {
          children.add(TextSpan(text: actualText, style: semantic.style));
        }
      }

      currentPos = semanticEnd;
    }

    if (currentPos < lineText.length) {
      _addGrammarSegments(
        children,
        grammarSegments,
        currentPos,
        lineText.length,
        lineText,
      );
    }

    if (children.isEmpty) {
      return grammarSpan;
    }

    if (children.length == 1) {
      return children.first;
    }

    return TextSpan(style: baseTextStyle, children: children);
  }

  void _flattenGrammarSpan(
    TextSpan? span,
    List<({String text, TextStyle? style})> segments,
    TextStyle? parentStyle,
  ) {
    if (span == null) return;

    final effectiveStyle = span.style ?? parentStyle;

    if (span.text != null && span.text!.isNotEmpty) {
      segments.add((text: span.text!, style: effectiveStyle));
    }

    if (span.children != null) {
      for (final child in span.children!) {
        if (child is TextSpan) {
          _flattenGrammarSpan(child, segments, effectiveStyle);
        }
      }
    }
  }

  void _addGrammarSegments(
    List<TextSpan> children,
    List<({String text, TextStyle? style})> grammarSegments,
    int startPos,
    int endPos,
    String lineText,
  ) {
    int segmentOffset = 0;
    int addedLength = 0;

    for (final segment in grammarSegments) {
      final segmentStart = segmentOffset;
      final segmentEnd = segmentOffset + segment.text.length;

      if (segmentEnd > startPos && segmentStart < endPos) {
        final overlapStart = segmentStart < startPos
            ? startPos - segmentStart
            : 0;
        final overlapEnd = segmentEnd > endPos
            ? segment.text.length - (segmentEnd - endPos)
            : segment.text.length;

        if (overlapEnd > overlapStart) {
          final text = segment.text.substring(overlapStart, overlapEnd);
          children.add(
            TextSpan(text: text, style: segment.style ?? baseTextStyle),
          );
          addedLength += text.length;
        }
      }

      segmentOffset = segmentEnd;

      if (segmentOffset >= endPos) break;
    }

    final expectedLength = endPos - startPos;
    if (addedLength < expectedLength) {
      final subStart = (startPos + addedLength).clamp(0, lineText.length);
      final subEnd = endPos.clamp(0, lineText.length);
      if (subEnd > subStart) {
        final remaining = lineText.substring(subStart, subEnd);
        if (remaining.isNotEmpty) {
          children.add(TextSpan(text: remaining, style: baseTextStyle));
        }
      }
    }
  }

  TextStyle? _getStyleAtPosition(
    List<({String text, TextStyle? style})> grammarSegments,
    int position,
  ) {
    int offset = 0;
    for (final segment in grammarSegments) {
      final segmentEnd = offset + segment.text.length;
      if (position >= offset && position < segmentEnd) {
        return segment.style;
      }
      offset = segmentEnd;
    }
    return baseTextStyle;
  }

  bool _isStringOrCommentStyle(TextStyle? style) {
    if (style == null) return false;

    final stringStyle = editorTheme['string'];
    final commentStyle = editorTheme['comment'];
    final numberStyle = editorTheme['number'];
    final regexpStyle = editorTheme['regexp'];
    final metaStringStyle = editorTheme['meta-string'];
    final styleColor = style.color;

    if (styleColor == null) return false;
    if (stringStyle?.color == styleColor) return true;
    if (commentStyle?.color == styleColor) return true;
    if (numberStyle?.color == styleColor) return true;
    if (regexpStyle?.color == styleColor) return true;
    if (metaStringStyle?.color == styleColor) return true;

    return false;
  }

  TextStyle? _resolveSemanticStyle(String? tokenTypeName) {
    if (tokenTypeName == null) return null;

    final hljsKeys = _semanticMapping[tokenTypeName];
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
    _lineSemanticSpans.clear();
    _lineSpanCache.clear();
  }
}

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
