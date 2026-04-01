import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:re_highlight/re_highlight.dart';

import '../LSP/lsp.dart';
import 'textmate_sidecar.dart';

const bool _kDebugTextMate = bool.fromEnvironment(
  'CODEFORGE_DEBUG_TEXTMATE',
  defaultValue: false,
);

class SemanticWordSpan {
  final int startChar;
  final int endChar;
  final TextStyle style;

  SemanticWordSpan({
    required this.startChar,
    required this.endChar,
    required this.style,
  });
}

class HighlightedLine {
  final String text;
  final TextSpan? span;
  final int grammarVersion;
  final int semanticVersion;
  final int textMateEpoch;

  HighlightedLine(
    this.text,
    this.span, {
    required this.grammarVersion,
    required this.semanticVersion,
    required this.textMateEpoch,
  });
}

class _SpanData {
  final String text;
  final String? scope;
  final List<_SpanData> children;

  _SpanData(this.text, this.scope, [this.children = const []]);
}

class _TokenTypeSpan {
  final int startChar;
  final int endChar;
  final int tokenType;

  const _TokenTypeSpan({
    required this.startChar,
    required this.endChar,
    required this.tokenType,
  });
}

class SyntaxHighlighter {
  final Mode language;
  final List<Mode> extraLanguages;
  final Map<String, TextStyle> editorTheme;
  final TextStyle? baseTextStyle;
  final String? languageId;
  final String? filePath;
  final String? initialText;
  final void Function(Set<int> updatedLines)? onGrammarUpdated;
  late final String _langId;
  late final Highlight _highlight;
  late final Map<String, TextStyle> _resolvedTheme;
  late final List<Mode> _registeredExtraLanguages;
  late final Map<String, List<String>> _semanticMapping;
  final Map<int, HighlightedLine> _grammarCache = {};
  final Map<int, HighlightedLine> _mergedCache = {};
  final Map<int, List<SemanticWordSpan>> _lineSemanticSpans = {};
  final Map<int, List<_TokenTypeSpan>> _lineTokenTypes = {};
  bool _isEditing = false;
  int _grammarVersion = 0;
  int _semanticVersion = 0;
  int _documentVersion = 0;
  static const int isolateThreshold = 500;
  int get documentVersion => _documentVersion;

  final TextMateSidecarClient? _textMateClient = CodeForgeTextMate.client;
  bool _useTextMate = false;
  late final String _textMateDocId =
      filePath ?? 'memory:${identityHashCode(this)}';
  bool _textMateOpened = false;
  bool _textMateOpenInFlight = false;
  int _textMateEpoch = 0;
  int _textMateStaleFromLine = 1 << 30;
  final Set<int> _pendingTextMateLines = <int>{};
  final Map<int, String> _pendingTextMateLineTexts = <int, String>{};
  bool _textMateTokenizeScheduled = false;
  final Map<int, TextStyle> _textMateStyleCache = {};
  final Map<String, TextStyle> _textMateSemanticStyleCache = {};

  SyntaxHighlighter({
    required this.language,
    required this.editorTheme,
    this.baseTextStyle,
    this.languageId,
    this.extraLanguages = const [],
    this.filePath,
    this.initialText,
    this.onGrammarUpdated,
  }) {
    _langId = language.hashCode.toString();
    _resolvedTheme = _buildResolvedTheme(editorTheme);
    _highlight = Highlight();
    _highlight.registerLanguage(_langId, language);

    _registeredExtraLanguages = <Mode>[...extraLanguages];

    for (final lang in _registeredExtraLanguages) {
      _registerLanguageWithAliases(_highlight, lang);
    }

    _semanticMapping = getSemanticMapping(languageId ?? '');

    _useTextMate = _textMateClient != null && (filePath?.isNotEmpty ?? false);

    if (_useTextMate && (initialText != null)) {
      _ensureTextMateOpened(initialText!);
    }
  }

  void _ensureTextMateOpened(String fullText) {
    if (!_useTextMate) return;
    if (_textMateOpened || _textMateOpenInFlight) return;

    // If another editor instance already opened this document in the shared
    // sidecar process, reuse it (don’t reset state or clear prefetched caches).
    final existing = _textMateClient?.isDocumentOpen(_textMateDocId) ?? false;
    if (existing) {
      _textMateOpened = true;
      if (_kDebugTextMate) {
        debugPrint('[code_forge/textmate] reuse docId=$_textMateDocId');
      }
      return;
    }

    _textMateOpenInFlight = true;
    if (_kDebugTextMate) {
      debugPrint(
        '[code_forge/textmate] open docId=$_textMateDocId filePath=$filePath chars=${fullText.length}',
      );
    }
    unawaited(
      _textMateClient!
          .openDocument(
            docId: _textMateDocId,
            content: fullText,
            filePath: filePath,
          )
          .then((_) {
            _textMateOpened = true;
            if (_kDebugTextMate) {
              debugPrint('[code_forge/textmate] open ok docId=$_textMateDocId');
            }
          })
          .catchError((e) {
            // If the grammar can’t be resolved for this file, fall back to the built-in
            // (re_highlight) highlighter instead of surfacing async errors.
            _useTextMate = false;
            if (_kDebugTextMate) {
              debugPrint(
                '[code_forge/textmate] open failed; fallback to re_highlight. docId=$_textMateDocId filePath=$filePath err=$e',
              );
            }
          })
          .whenComplete(() {
            _textMateOpenInFlight = false;
            if (!_useTextMate) return;
            if (_pendingTextMateLines.isNotEmpty) {
              final line = _pendingTextMateLines.first;
              final text =
                  _pendingTextMateLineTexts[line] ?? _grammarCache[line]?.text;
              if (text != null) {
                _queueTextMateTokenize(line, text);
              }
            }
          }),
    );
  }

  void updateSemanticTokens(List<LspSemanticToken> tokens, String fullText) {
    // Keep the signature for compatibility, but avoid O(document) work.
    updateSemanticTokensFull(tokens);
  }

  void updateSemanticTokensFull(List<LspSemanticToken> tokens) {
    _lineSemanticSpans.clear();

    for (final token in tokens) {
      final style = _resolveSemanticStyle(token.tokenTypeName);
      if (style == null || token.length <= 0) continue;

      final lineSpans = _lineSemanticSpans.putIfAbsent(token.line, () => []);
      lineSpans.add(
        SemanticWordSpan(
          startChar: token.start,
          endChar: token.start + token.length,
          style: style,
        ),
      );
    }

    for (final spans in _lineSemanticSpans.values) {
      spans.sort((a, b) => a.startChar.compareTo(b.startChar));
    }

    _isEditing = false;
    _mergedCache.clear();
    _semanticVersion++;
  }

  void updateSemanticTokensRange(
    List<LspSemanticToken> tokens, {
    required int startLine,
    required int endLineExclusive,
  }) {
    if (startLine >= endLineExclusive) return;

    for (int line = startLine; line < endLineExclusive; line++) {
      _lineSemanticSpans.remove(line);
      _mergedCache.remove(line);
    }

    final touchedLines = <int>{};
    for (final token in tokens) {
      final line = token.line;
      if (line < startLine || line >= endLineExclusive) continue;

      final style = _resolveSemanticStyle(token.tokenTypeName);
      if (style == null || token.length <= 0) continue;

      final lineSpans = _lineSemanticSpans.putIfAbsent(line, () => []);
      lineSpans.add(
        SemanticWordSpan(
          startChar: token.start,
          endChar: token.start + token.length,
          style: style,
        ),
      );
      touchedLines.add(line);
    }

    for (final line in touchedLines) {
      _lineSemanticSpans[line]?.sort(
        (a, b) => a.startChar.compareTo(b.startChar),
      );
    }

    _isEditing = false;
  }

  void applyDocumentEdit(
    int editStart,
    int oldEnd,
    String insertedText,
    String fullText, {
    TextMateEdit? textMateEdit,
  }) {
    _documentVersion++;
    _isEditing = true;

    if (_useTextMate) {
      if (!_textMateOpened) {
        _ensureTextMateOpened(fullText);
        return;
      }

      if (_textMateOpenInFlight) return;

      if (textMateEdit != null) {
        // Tokenization state can affect subsequent lines (multi-line constructs).
        _textMateEpoch++;
        _textMateStaleFromLine = _textMateStaleFromLine < textMateEdit.startLine
            ? _textMateStaleFromLine
            : textMateEdit.startLine;

        unawaited(
          _textMateClient!
              .applyEdits(docId: _textMateDocId, edits: [textMateEdit])
              .catchError((_) {}),
        );
      } else {
        _textMateEpoch++;
        _textMateStaleFromLine = 0;
        unawaited(
          _textMateClient!
              .setDocumentText(docId: _textMateDocId, content: fullText)
              .catchError((_) {}),
        );
      }
    }
  }

  void invalidateAll() {
    _grammarCache.clear();
    _mergedCache.clear();
    _lineSemanticSpans.clear();
    _lineTokenTypes.clear();
    _documentVersion++;
    _grammarVersion++;
    _semanticVersion++;

    if (_useTextMate) {
      _textMateEpoch++;
      _textMateStaleFromLine = 0;
      _pendingTextMateLines.clear();
      _pendingTextMateLineTexts.clear();
      _textMateStyleCache.clear();
    }
  }

  void invalidateLines(Set<int> lines) {
    for (final line in lines) {
      _grammarCache.remove(line);
      _mergedCache.remove(line);
      _lineSemanticSpans.remove(line);
      _lineTokenTypes.remove(line);
    }
  }

  void invalidateRange(int startLine, int endLine) {
    for (int i = startLine; i <= endLine; i++) {
      _grammarCache.remove(i);
      _mergedCache.remove(i);
      _lineSemanticSpans.remove(i);
      _lineTokenTypes.remove(i);
    }
    final keysToRemove = _grammarCache.keys.where((k) => k > endLine).toList();
    for (final key in keysToRemove) {
      _grammarCache.remove(key);
      _mergedCache.remove(key);
      _lineSemanticSpans.remove(key);
      _lineTokenTypes.remove(key);
    }
  }

  /// Prefetch TextMate tokens for a line range (usually a viewport + buffer).
  ///
  /// This is intentionally best-effort: it avoids doing async work during paint,
  /// and it uses any already-cached sidecar tokens to build spans immediately.
  void prefetchTextMateTokens({
    required int startLine,
    required int endLineExclusive,
    required String Function(int lineIndex) getLineText,
  }) {
    if (!_useTextMate) return;
    if (endLineExclusive <= startLine) return;

    final safeStart = startLine < 0 ? 0 : startLine;
    final safeEnd = endLineExclusive <= safeStart
        ? safeStart
        : endLineExclusive;

    final updated = <int>{};

    for (int line = safeStart; line < safeEnd; line++) {
      final lineText = getLineText(line);
      final cached = _grammarCache[line];
      final isFresh =
          cached != null &&
          cached.text == lineText &&
          cached.grammarVersion == _grammarVersion &&
          (line < _textMateStaleFromLine ||
              cached.textMateEpoch == _textMateEpoch);
      if (isFresh) continue;

      // If the sidecar already has cached tokens for this line, build the span
      // immediately so the next paint can render it synchronously.
      final prefetched = _textMateClient?.peekCachedLineTokens(
        docId: _textMateDocId,
        line: line,
        lineText: lineText,
      );
      if (prefetched != null) {
        final span = _buildTextMateSpan(lineText, prefetched);
        _grammarCache[line] = HighlightedLine(
          lineText,
          span,
          grammarVersion: _grammarVersion,
          semanticVersion: 0,
          textMateEpoch: _textMateEpoch,
        );
        _mergedCache.remove(line);
        updated.add(line);
        continue;
      }

      _queueTextMateTokenize(line, lineText);
    }

    if (updated.isNotEmpty) {
      onGrammarUpdated?.call(updated);
    }
  }

  TextSpan? getLineSpan(int lineIndex, String lineText) {
    if (_useTextMate) {
      final cached = _grammarCache[lineIndex];
      if (cached != null &&
          cached.text == lineText &&
          cached.grammarVersion == _grammarVersion &&
          (lineIndex < _textMateStaleFromLine ||
              cached.textMateEpoch == _textMateEpoch)) {
        // Grammar span is ready; semantic merge can happen below.
      } else if (cached != null &&
          cached.text == lineText &&
          cached.grammarVersion == _grammarVersion) {
        // Stale (state may have changed due to an earlier edit). Keep the old span
        // visible, but schedule a re-tokenization for this line.
        _queueTextMateTokenize(lineIndex, lineText);
        return cached.span ?? TextSpan(text: lineText, style: baseTextStyle);
      } else {
        // If we have prefetched tokens (with line hashes), render synchronously.
        final prefetched = _textMateClient?.peekCachedLineTokens(
          docId: _textMateDocId,
          line: lineIndex,
          lineText: lineText,
        );
        if (prefetched != null) {
          final span = _buildTextMateSpan(lineText, prefetched);
          _grammarCache[lineIndex] = HighlightedLine(
            lineText,
            span,
            grammarVersion: _grammarVersion,
            semanticVersion: 0,
            textMateEpoch: _textMateEpoch,
          );
        } else {
          // Not ready for this text; schedule tokenization and render plain text for now.
          _queueTextMateTokenize(lineIndex, lineText);
          return TextSpan(text: lineText, style: baseTextStyle);
        }
      }
    }

    final mergedCached = _mergedCache[lineIndex];
    if (mergedCached != null &&
        mergedCached.text == lineText &&
        mergedCached.grammarVersion == _grammarVersion &&
        mergedCached.semanticVersion == _semanticVersion &&
        mergedCached.textMateEpoch == _textMateEpoch) {
      return mergedCached.span;
    }

    final grammarCached = _grammarCache[lineIndex];
    final grammarSpan =
        grammarCached != null &&
            grammarCached.text == lineText &&
            grammarCached.grammarVersion == _grammarVersion
        ? grammarCached.span
        : (_useTextMate ? grammarCached?.span : _highlightLine(lineText));
    _grammarCache[lineIndex] = HighlightedLine(
      lineText,
      grammarSpan,
      grammarVersion: _grammarVersion,
      semanticVersion: 0,
      textMateEpoch: _textMateEpoch,
    );

    if (_isEditing) {
      return grammarSpan;
    }

    final semanticSpans = _lineSemanticSpans[lineIndex];
    final mergedSpan = _mergeGrammarAndSemantic(
      lineText,
      lineIndex,
      grammarSpan,
      semanticSpans,
    );

    _mergedCache[lineIndex] = HighlightedLine(
      lineText,
      mergedSpan,
      grammarVersion: _grammarVersion,
      semanticVersion: _semanticVersion,
      textMateEpoch: _textMateEpoch,
    );

    return mergedSpan;
  }

  TextSpan? _mergeGrammarAndSemantic(
    String lineText,
    int lineIndex,
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
        final preserveGrammar = _useTextMate
            ? _isProtectedTokenType(lineIndex, semanticStart)
            : _isStringOrCommentStyle(grammarStyle) ||
                  _hasMeaningfulGrammarStyle(grammarStyle);
        children.add(
          TextSpan(
            text: actualText,
            style: preserveGrammar ? grammarStyle : semantic.style,
          ),
        );
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

  bool _hasMeaningfulGrammarStyle(TextStyle? style) {
    if (style == null) return false;

    final rootStyle = baseTextStyle ?? _resolvedTheme['root'];
    final rootColor = rootStyle?.color;

    if (style.color != null && rootColor != null && style.color != rootColor) {
      return true;
    }
    if (style.fontWeight != null && style.fontWeight != rootStyle?.fontWeight) {
      return true;
    }
    if (style.fontStyle != null && style.fontStyle != rootStyle?.fontStyle) {
      return true;
    }

    return false;
  }

  bool _isProtectedTokenType(int lineIndex, int position) {
    final spans = _lineTokenTypes[lineIndex];
    if (spans == null || spans.isEmpty) return false;
    for (final s in spans) {
      if (position < s.startChar) return false;
      if (position >= s.startChar && position < s.endChar) {
        return s.tokenType == 1 || s.tokenType == 2 || s.tokenType == 3;
      }
    }
    return false;
  }

  TextStyle? _resolveSemanticStyle(String? tokenTypeName) {
    if (tokenTypeName == null) return null;

    // When TextMate is enabled, we rely on the grammar for keywords/operators.
    // Applying LSP semantic colors for these tends to fight the theme and can
    // cause visible “wrong” recolors (e.g. blue → pink) depending on the server.
    if (_useTextMate && _shouldSkipSemanticTokenForTextMate(tokenTypeName)) {
      return null;
    }

    if (_useTextMate) {
      final roles = _textMateClient?.status?.themeRoles;
      if (roles != null && roles.isNotEmpty) {
        final role = _semanticRoleForTextMate(tokenTypeName);
        if (role != null) {
          final hex = roles[role] ?? roles['defaultForeground'];
          final color = _parseHexColor(hex);
          if (color != null) {
            final cacheKey = '$role:${color.toARGB32()}';
            return _textMateSemanticStyleCache.putIfAbsent(cacheKey, () {
              final base =
                  baseTextStyle ?? editorTheme['root'] ?? const TextStyle();
              return base.copyWith(color: color);
            });
          }
        }
      }
    }

    final hljsKeys = _semanticMapping[tokenTypeName];
    if (hljsKeys == null) return null;

    for (final key in hljsKeys) {
      final style = editorTheme[key];
      final styleFromResolved = _resolvedTheme[key];
      if (styleFromResolved != null) return styleFromResolved;
      if (style != null) return style;
    }

    return null;
  }

  bool _shouldSkipSemanticTokenForTextMate(String tokenTypeName) {
    switch (tokenTypeName) {
      case 'keyword':
      case 'modifier':
      case 'operator':
      case 'regexp':
      case 'decorator':
        return true;
      default:
        return false;
    }
  }

  String? _semanticRoleForTextMate(String tokenTypeName) {
    switch (tokenTypeName) {
      case 'parameter':
      case 'variable':
      case 'property':
      case 'field':
      case 'event':
        return 'variable';
      case 'function':
      case 'method':
        return 'function';
      case 'namespace':
      case 'type':
      case 'class':
      case 'interface':
      case 'enum':
      case 'struct':
      case 'typeParameter':
        return 'type';
      case 'enumMember':
      case 'constant':
      case 'macro':
        return 'constant';
      case 'keyword':
      case 'modifier':
      case 'operator':
        return 'keyword';
      case 'string':
        return 'string';
      case 'number':
        return 'number';
      case 'comment':
        return 'comment';
      default:
        return null;
    }
  }

  Color? _parseHexColor(String? hex) {
    if (hex == null) return null;
    final value = hex.trim();
    if (!value.startsWith('#')) return null;
    final raw = value.substring(1);
    try {
      if (raw.length == 6) {
        return Color(int.parse('FF$raw', radix: 16));
      }
      if (raw.length == 8) {
        return Color(int.parse(raw, radix: 16));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  TextSpan? _highlightLine(String lineText) {
    if (lineText.isEmpty) return null;

    try {
      final result = _highlight.highlight(code: lineText, language: _langId);
      final renderer = TextSpanRenderer(baseTextStyle, _resolvedTheme);
      result.render(renderer);
      var span = renderer.span;
      if (_isTsxOrJsx && _looksLikeJsxTagLine(lineText)) {
        span = _applyJsxTagFallback(lineText, span);
      }
      return span;
    } catch (e) {
      return TextSpan(text: lineText, style: baseTextStyle);
    }
  }

  bool get _isTsxOrJsx {
    final id = languageId?.toLowerCase().trim();
    return id == 'tsx' || id == 'jsx';
  }

  bool _looksLikeJsxTagLine(String line) {
    return RegExp(r'(^|[^A-Za-z0-9_])<\/?[A-Za-z]').hasMatch(line);
  }

  TextSpan? _applyJsxTagFallback(String lineText, TextSpan? span) {
    if (span == null || lineText.isEmpty) return span;

    final tagStyle =
        _resolvedTheme['tag'] ??
        _resolvedTheme['name'] ??
        _resolvedTheme['selector-tag'];
    if (tagStyle == null) return span;

    final grammarSegments = <({String text, TextStyle? style})>[];
    _flattenGrammarSpan(span, grammarSegments, baseTextStyle);

    final ranges = <({int start, int end})>[];
    final tagOpen = RegExp(
      r'(^|[^A-Za-z0-9_])<\/?\s*([A-Za-z][A-Za-z0-9:_-]*)',
    );

    for (final match in tagOpen.allMatches(lineText)) {
      final prefix = match.group(1) ?? '';
      final leadingStart = match.start + prefix.length;
      if (leadingStart < 0 || leadingStart >= lineText.length) continue;

      final nameGroup = match.group(2);
      if (nameGroup == null) continue;
      final nameStart = match.end - nameGroup.length;
      final nameEnd = match.end;

      ranges.add((
        start: leadingStart,
        end: (nameStart).clamp(leadingStart, lineText.length),
      ));
      ranges.add((start: nameStart, end: nameEnd));

      final closeIndex = lineText.indexOf('>', match.end);
      if (closeIndex != -1) {
        final beforeClose = closeIndex > 0 ? lineText[closeIndex - 1] : '';
        if (beforeClose == '/') {
          ranges.add((start: closeIndex - 1, end: closeIndex));
        }
        ranges.add((start: closeIndex, end: closeIndex + 1));
      }
    }

    if (ranges.isEmpty) return span;

    ranges.sort((a, b) => a.start.compareTo(b.start));

    final mergedRanges = <({int start, int end})>[];
    for (final range in ranges) {
      final start = range.start.clamp(0, lineText.length);
      final end = range.end.clamp(0, lineText.length);
      if (end <= start) continue;

      if (mergedRanges.isEmpty || start > mergedRanges.last.end) {
        mergedRanges.add((start: start, end: end));
      } else {
        final last = mergedRanges.removeLast();
        mergedRanges.add((
          start: last.start,
          end: end > last.end ? end : last.end,
        ));
      }
    }

    final children = <TextSpan>[];
    int current = 0;

    for (final range in mergedRanges) {
      if (range.start > current) {
        _addGrammarSegments(
          children,
          grammarSegments,
          current,
          range.start,
          lineText,
        );
      }

      final existing = _getStyleAtPosition(grammarSegments, range.start);
      final chosen = _hasMeaningfulGrammarStyle(existing) ? existing : tagStyle;
      final part = lineText.substring(range.start, range.end);
      if (part.isNotEmpty) {
        children.add(TextSpan(text: part, style: chosen));
      }
      current = range.end;
    }

    if (current < lineText.length) {
      _addGrammarSegments(
        children,
        grammarSegments,
        current,
        lineText.length,
        lineText,
      );
    }

    return TextSpan(style: baseTextStyle, children: children);
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
    if (_useTextMate) {
      // Tokenization is handled asynchronously by the sidecar and scheduled on demand.
      return;
    }

    final linesToProcess = <int, String>{};

    for (int i = startLine; i <= endLine; i++) {
      final lineText = getLineText(i);
      final cached = _grammarCache[i];
      if (cached == null ||
          cached.text != lineText ||
          cached.grammarVersion != _grammarVersion) {
        linesToProcess[i] = lineText;
      }
    }

    if (linesToProcess.isEmpty) return;

    if (linesToProcess.length < 50) {
      for (final entry in linesToProcess.entries) {
        final span = _highlightLine(entry.value);
        _grammarCache[entry.key] = HighlightedLine(
          entry.value,
          span,
          grammarVersion: _grammarVersion,
          semanticVersion: 0,
          textMateEpoch: _textMateEpoch,
        );
      }
      return;
    }

    final results = await compute(
      _highlightLinesInBackground,
      _BackgroundHighlightData(
        langId: _langId,
        lines: linesToProcess,
        languageMode: language,
        extraLanguages: _registeredExtraLanguages,
        theme: _resolvedTheme,
        baseStyle: baseTextStyle,
      ),
    );

    for (final entry in results.entries) {
      final spanData = entry.value;
      final textSpan = spanData != null ? _spanDataToTextSpan(spanData) : null;
      _grammarCache[entry.key] = HighlightedLine(
        linesToProcess[entry.key]!,
        textSpan,
        grammarVersion: _grammarVersion,
        semanticVersion: 0,
        textMateEpoch: _textMateEpoch,
      );
    }
  }

  TextSpan? _spanDataToTextSpan(_SpanData? data) {
    if (data == null) return null;

    final style = data.scope != null
        ? _resolvedTheme[data.scope]
        : baseTextStyle;

    if (data.children.isEmpty) {
      return TextSpan(text: data.text, style: style);
    }

    return TextSpan(
      text: data.text.isEmpty ? null : data.text,
      style: style,
      children: data.children.map((c) => _spanDataToTextSpan(c)!).toList(),
    );
  }

  Map<String, TextStyle> _buildResolvedTheme(Map<String, TextStyle> theme) {
    final resolved = Map<String, TextStyle>.from(theme);

    if (!resolved.containsKey('tag')) {
      final fallbackTagStyle = resolved['selector-tag'] ?? resolved['name'];
      if (fallbackTagStyle != null) {
        resolved['tag'] = fallbackTagStyle;
      }
    }

    return resolved;
  }

  void dispose() {
    _grammarCache.clear();
    _mergedCache.clear();
    _lineSemanticSpans.clear();
    _lineTokenTypes.clear();
  }

  void _queueTextMateTokenize(int lineIndex, String lineText) {
    if (!_useTextMate) return;

    _pendingTextMateLines.add(lineIndex);
    _pendingTextMateLineTexts[lineIndex] = lineText;
    if (!_textMateOpened || _textMateOpenInFlight) return;
    if (_textMateTokenizeScheduled) return;
    _textMateTokenizeScheduled = true;

    // Batch requests to avoid spawning one RPC per line during paint.
    scheduleMicrotask(() async {
      final sw = _kDebugTextMate ? (Stopwatch()..start()) : null;
      try {
        while (true) {
          if (_pendingTextMateLines.isEmpty) return;
          if (!_textMateOpened || _textMateOpenInFlight) return;

          final lines = _pendingTextMateLines.toList()..sort();
          _pendingTextMateLines.clear();

          if (_kDebugTextMate) {
            debugPrint(
              '[code_forge/textmate] tokenize pending=${lines.length} docId=$_textMateDocId',
            );
          }

          final updated = <int>{};
          final cacheable = <TextMateLineTokens>[];
          final lineHashes = <int, int>{};

          // Tokenize only the requested lines (grouped by contiguous ranges).
          // This avoids accidentally tokenizing huge spans when the pending set
          // contains far-apart lines (e.g., jump-to-definition).
          final ranges = <({int startLine, int endLineExclusive})>[];
          var rangeStart = lines.first;
          var prev = rangeStart;
          for (final line in lines.skip(1)) {
            if (line == prev + 1) {
              prev = line;
              continue;
            }
            ranges.add((startLine: rangeStart, endLineExclusive: prev + 1));
            rangeStart = line;
            prev = line;
          }
          ranges.add((startLine: rangeStart, endLineExclusive: prev + 1));

          const maxLinesPerRequest = 200;

          for (final range in ranges) {
            var chunkStart = range.startLine;
            while (chunkStart < range.endLineExclusive) {
              final chunkEnd = math.min(
                chunkStart + maxLinesPerRequest,
                range.endLineExclusive,
              );

              List<TextMateLineTokens> tokenLines;
              try {
                if (_kDebugTextMate) {
                  debugPrint(
                    '[code_forge/textmate] tokenizeLines docId=$_textMateDocId start=$chunkStart end=$chunkEnd',
                  );
                }
                tokenLines = await _textMateClient!.tokenizeLines(
                  docId: _textMateDocId,
                  startLine: chunkStart,
                  endLineExclusive: chunkEnd,
                );
              } catch (e) {
                if (_kDebugTextMate) {
                  debugPrint(
                    '[code_forge/textmate] tokenizeLines failed docId=$_textMateDocId start=$chunkStart end=$chunkEnd err=$e',
                  );
                }
                return;
              }

              for (final tl in tokenLines) {
                final line = tl.line;
                final requestedText =
                    _pendingTextMateLineTexts.remove(line) ??
                    _grammarCache[line]?.text;
                if (requestedText == null) continue;

                lineHashes[line] = requestedText.hashCode;
                cacheable.add(tl);

                final span = _buildTextMateSpan(requestedText, tl);
                _grammarCache[line] = HighlightedLine(
                  requestedText,
                  span,
                  grammarVersion: _grammarVersion,
                  semanticVersion: 0,
                  textMateEpoch: _textMateEpoch,
                );
                _mergedCache.remove(line); // force re-merge with semantics
                updated.add(line);
              }

              chunkStart = chunkEnd;
              // Yield so large prefetches don't monopolize the UI thread.
              if (chunkStart < range.endLineExclusive) {
                await Future<void>.delayed(Duration.zero);
              }
            }
          }

          if (updated.isNotEmpty) {
            if (cacheable.isNotEmpty) {
              try {
                _textMateClient?.cacheLineTokens(
                  docId: _textMateDocId,
                  lines: cacheable,
                  lineTextHashes: lineHashes,
                );
              } catch (_) {
                // ignore cache errors
              }
            }
            onGrammarUpdated?.call(updated);
          }

          // Loop again if new lines arrived while we were tokenizing.
        }
      } finally {
        _textMateTokenizeScheduled = false;
        if (_kDebugTextMate) {
          sw?.stop();
          debugPrint(
            '[code_forge/textmate] tokenize done docId=$_textMateDocId ms=${sw?.elapsedMilliseconds}',
          );
        }
      }
    });
  }

  TextSpan? _buildTextMateSpan(String lineText, TextMateLineTokens tl) {
    if (lineText.isEmpty) return null;

    final colorMap = _textMateClient?.colorMap ?? const <String>[];
    final tokens = tl.tokens;
    if (tokens.isEmpty) {
      return TextSpan(text: lineText, style: baseTextStyle);
    }

    // VS Code’s `colorMap` is effectively 1-based: index 0 is null.
    final defaultFgHex = colorMap.length > 1 ? colorMap[1] : '';

    final spans = <TextSpan>[];
    final typeSpans = <_TokenTypeSpan>[];

    for (int i = 0; i + 1 < tokens.length; i += 2) {
      final start = tokens[i];
      final metadata = tokens[i + 1];

      final nextStart = (i + 2 < tokens.length) ? tokens[i + 2] : tl.lineLength;
      final end = nextStart.clamp(0, lineText.length);
      final s = start.clamp(0, lineText.length);
      if (end <= s) continue;

      final tokenType = (metadata & 0x00000300) >> 8;
      final fontStyleBits = (metadata & 0x00007800) >> 11;
      final rawFgId = (metadata & 0x00FF8000) >> 15;
      final fgId = (rawFgId == 0 && defaultFgHex.isNotEmpty) ? 1 : rawFgId;

      final styleKey = (fgId << 8) | fontStyleBits;
      final cachedStyle = _textMateStyleCache[styleKey];
      final style =
          cachedStyle ??
          (() {
            Color? fg;
            if (fgId >= 0 && fgId < colorMap.length) {
              final hex = colorMap[fgId];
              if (hex.startsWith('#') && (hex.length == 7 || hex.length == 9)) {
                final normalized = hex.length == 7
                    ? 'FF${hex.substring(1)}'
                    : hex.substring(1);
                fg = Color(int.parse(normalized, radix: 16));
              }
            }

            TextStyle base =
                baseTextStyle ?? editorTheme['root'] ?? const TextStyle();
            if (fg == null &&
                defaultFgHex.startsWith('#') &&
                (defaultFgHex.length == 7 || defaultFgHex.length == 9)) {
              final normalized = defaultFgHex.length == 7
                  ? 'FF${defaultFgHex.substring(1)}'
                  : defaultFgHex.substring(1);
              base = base.copyWith(
                color: Color(int.parse(normalized, radix: 16)),
              );
            }
            if (fg != null) {
              base = base.copyWith(color: fg);
            }

            FontWeight? weight;
            FontStyle? fontStyle;
            TextDecoration? decoration;
            if ((fontStyleBits & 0x1) != 0) {
              fontStyle = FontStyle.italic;
            }
            if ((fontStyleBits & 0x2) != 0) {
              weight = FontWeight.bold;
            }
            if ((fontStyleBits & 0x4) != 0) {
              decoration = TextDecoration.underline;
            }
            if ((fontStyleBits & 0x8) != 0) {
              decoration = decoration == null
                  ? TextDecoration.lineThrough
                  : TextDecoration.combine([
                      decoration,
                      TextDecoration.lineThrough,
                    ]);
            }

            final ts = base.copyWith(
              fontStyle: fontStyle,
              fontWeight: weight,
              decoration: decoration,
            );
            _textMateStyleCache[styleKey] = ts;
            return ts;
          })();

      spans.add(TextSpan(text: lineText.substring(s, end), style: style));
      typeSpans.add(
        _TokenTypeSpan(startChar: s, endChar: end, tokenType: tokenType),
      );
    }

    _lineTokenTypes[tl.line] = typeSpans;

    if (spans.isEmpty) {
      return TextSpan(text: lineText, style: baseTextStyle);
    }
    if (spans.length == 1) return spans.first;
    return TextSpan(style: baseTextStyle, children: spans);
  }
}

class _BackgroundHighlightData {
  final String langId;
  final Map<int, String> lines;
  final Mode languageMode;
  final List<Mode> extraLanguages;
  final Map<String, TextStyle> theme;
  final TextStyle? baseStyle;

  _BackgroundHighlightData({
    required this.langId,
    required this.lines,
    required this.languageMode,
    required this.extraLanguages,
    required this.theme,
    this.baseStyle,
  });
}

Map<int, _SpanData?> _highlightLinesInBackground(
  _BackgroundHighlightData data,
) {
  final highlight = Highlight();
  highlight.registerLanguage(data.langId, data.languageMode);
  for (final lang in data.extraLanguages) {
    _registerLanguageWithAliases(highlight, lang);
  }

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

void _registerLanguageWithAliases(Highlight highlight, Mode language) {
  if (language.name == null) return;

  final normalizedName = language.name!.toLowerCase().trim();
  highlight.registerLanguage(normalizedName, language);

  for (final token in normalizedName.split(RegExp(r'[^a-z0-9_+#-]+'))) {
    if (token.isNotEmpty) {
      highlight.registerLanguage(token, language);
    }
  }

  for (final alias in language.aliases ?? const <String>[]) {
    final normalizedAlias = alias.toLowerCase();
    highlight.registerLanguage(normalizedAlias, language);
  }
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
