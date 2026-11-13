import 'dart:ui';
import 'dart:math' as math;

import 'controller.dart';
import 'syntax_highlighter.dart';

import 'package:material_ui/material_ui.dart';

class MiniMapPainter extends CustomPainter {
  final bool lineWrap;
  final Color bgColor;
  final double fontSize, lineHeight;
  final String? fontFamily;
  final TextDirection textDirection;
  final ScrollController scrollCtrl;
  final CodeForgeController controller;
  final SyntaxHighlighter highlighter;
  final Color selectionColor;
  final Listenable selectionRepaint;
  final Listenable diagnosticsRepaint;

  List<(int, int)> _folds = const [];
  List<(int, int)> _blocks = const [];
  int _lineCount = 0;

  final Paint _paint = Paint();

  MiniMapPainter({
    required this.bgColor,
    required this.controller,
    required this.scrollCtrl,
    required this.lineWrap,
    required this.highlighter,
    this.fontFamily,
    this.fontSize = 1,
    this.textDirection = .ltr,
    this.lineHeight = 1,
    this.selectionColor = const Color(0x6E2195F3),
    required this.selectionRepaint,
    required this.diagnosticsRepaint,
  }) : super(
         repaint: Listenable.merge([
           scrollCtrl,
           selectionRepaint,
           diagnosticsRepaint,
         ]),
       );

  @override
  void paint(Canvas canvas, Size size) {
    if (!scrollCtrl.hasClients) return;

    final position = scrollCtrl.position;
    if (!position.hasViewportDimension || !position.hasContentDimensions) {
      return;
    }

    _paint.color = bgColor;
    canvas.drawPaint(_paint);

    _prepareLayout();
    if (_lineCount <= 0) return;

    final viewTop = scrollCtrl.offset;
    final viewBottom = viewTop + position.viewportDimension;
    final firstVisibleLine = _lineAtY(viewTop);
    final lastVisibleLine = math.min(_lineAtY(viewBottom), _lineCount - 1);

    double yOffset = _lineTop(firstVisibleLine);
    final diagnosticLines = _diagnosticLines(firstVisibleLine, lastVisibleLine);

    final selection = controller.selection;
    final hasSelection = selection.isValid && !selection.isCollapsed;
    final selStartLine = hasSelection
        ? controller.getLineAtOffset(selection.start)
        : -1;
    final selEndLine = hasSelection
        ? controller.getLineAtOffset(selection.end)
        : -1;

    for (int i = firstVisibleLine; i <= lastVisibleLine; i++) {
      if (_isFolded(i)) continue;

      final lineText = controller.getLineText(i);
      final paragraph = highlighter.buildMiniMapHighlight(
        i,
        lineText,
        ParagraphStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          fontWeight: .bold,
          height: lineHeight,
          textDirection: textDirection,
          textAlign: .start,
        ),
        fontSize,
        fontFamily,
      );

      _paintDiagnostic(canvas, size, yOffset, diagnosticLines[i]);
      if (hasSelection && i >= selStartLine && i <= selEndLine) {
        _paintSelection(
          canvas,
          size,
          i,
          yOffset,
          paragraph,
          lineText,
          selection,
          selStartLine,
          selEndLine,
        );
      }
      canvas.drawParagraph(paragraph, Offset(8, yOffset));
      yOffset += _lineAdvance(i);
    }
  }

  @override
  bool shouldRepaint(covariant MiniMapPainter oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.bgColor != bgColor ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.lineHeight != lineHeight ||
        oldDelegate.lineWrap != lineWrap ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.selectionColor != selectionColor ||
        oldDelegate.diagnosticsRepaint != diagnosticsRepaint ||
        oldDelegate.controller.selection != controller.selection;
  }

  void _prepareLayout() {
    _lineCount = controller.lineCount;

    final ranges = <(int, int)>[];
    for (final fold in controller.foldings.values) {
      if (fold == null || !fold.isFolded) continue;
      final s = fold.startIndex + 1;
      final e = fold.endIndex;
      if (e >= s) ranges.add((s, e));
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));

    final merged = <(int, int)>[];
    for (final r in ranges) {
      if (merged.isNotEmpty && r.$1 <= merged.last.$2 + 1) {
        if (r.$2 > merged.last.$2) {
          merged[merged.length - 1] = (merged.last.$1, r.$2);
        }
      } else {
        merged.add(r);
      }
    }
    _folds = merged;

    final blocks = <(int, int)>[];
    for (final b in controller.virtualRemovedBlocks) {
      if (b.lineCount > 0) blocks.add((b.afterLine, b.lineCount));
    }
    blocks.sort((a, b) => a.$1.compareTo(b.$1));
    _blocks = blocks;
  }

  int _hiddenBefore(int line) {
    var n = 0;
    for (final (s, e) in _folds) {
      if (s >= line) break;
      n += math.min(e, line - 1) - s + 1;
    }
    return n;
  }

  int _virtualBefore(int line) {
    var n = 0;
    for (final (after, count) in _blocks) {
      if (after >= line) break;
      n += count;
    }
    return n;
  }

  bool _isFolded(int line) {
    for (final (s, e) in _folds) {
      if (line < s) return false;
      if (line <= e) return true;
    }
    return false;
  }

  double _lineTop(int line) {
    if (line <= 0) return 0;
    return (line - _hiddenBefore(line) + _virtualBefore(line)) * lineHeight;
  }

  double _lineAdvance(int line) {
    var advance = _isFolded(line) ? 0.0 : lineHeight;
    for (final (after, count) in _blocks) {
      if (after > line) break;
      if (after == line) advance += count * lineHeight;
    }
    return advance;
  }

  int _lineAtY(double y) {
    final lineCount = _lineCount;
    if (lineCount <= 0) return 0;
    if (!y.isFinite || !lineHeight.isFinite || lineHeight <= 0) return 0;

    if (_folds.isEmpty && _blocks.isEmpty) {
      return (y / lineHeight).floor().clamp(0, lineCount - 1);
    }

    var lo = 0;
    var hi = lineCount - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_lineTop(mid) <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  Map<int, int> _diagnosticLines(int first, int last) {
    final lines = <int, int>{};
    for (final diagnostic in controller.diagnostics) {
      final startLine = diagnostic.range['start']?['line'];
      final endLine = diagnostic.range['end']?['line'];
      if (startLine is! int) continue;

      final lastLine = endLine is int && endLine >= startLine
          ? endLine
          : startLine;

      if (lastLine < first || startLine > last) continue;
      final from = math.max(startLine, first);
      final to = math.min(lastLine, last);

      for (var line = from; line <= to; line++) {
        final currentSeverity = lines[line];
        if (currentSeverity == null || diagnostic.severity < currentSeverity) {
          lines[line] = diagnostic.severity;
        }
      }
    }
    return lines;
  }

  void _paintDiagnostic(Canvas canvas, Size size, double y, int? severity) {
    if (severity == null) return;

    _paint.color = switch (severity) {
      1 => Colors.red,
      2 => Colors.orange,
      3 => Colors.blue,
      _ => Colors.grey,
    };
    canvas.drawRect(
      Rect.fromLTWH(math.max(size.width - 4, 0), y, 3, lineHeight),
      _paint,
    );
  }

  void _paintSelection(
    Canvas canvas,
    Size size,
    int line,
    double y,
    Paragraph paragraph,
    String lineText,
    TextSelection selection,
    int startLine,
    int endLine,
  ) {
    final lineStart = controller.getLineStartOffset(line);
    final lineLength = lineText.length;
    final startColumn = line == startLine ? selection.start - lineStart : 0;
    final endColumn = line == endLine ? selection.end - lineStart : lineLength;
    if (endColumn <= startColumn) return;

    final width = (paragraph.maxIntrinsicWidth + 2).clamp(0.0, size.width - 8);
    final left = 8 + width * startColumn / math.max(lineLength, 1);
    final right = 8 + width * endColumn / math.max(lineLength, 1);

    _paint.color = selectionColor;
    canvas.drawRect(
      Rect.fromLTRB(left, y, math.max(right, left + 1), y + lineHeight),
      _paint,
    );
  }
}
