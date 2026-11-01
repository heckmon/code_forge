import 'dart:ui';
import 'dart:math' as math;

import 'controller.dart';
import 'syntax_highlighter.dart';

import 'package:flutter/material.dart';

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

    canvas.drawPaint(Paint()..color = bgColor);

    final position = scrollCtrl.position;

    if (!position.hasViewportDimension || !position.hasContentDimensions) {
      return;
    }

    final lineCount = controller.lineCount;
    final viewTop = scrollCtrl.offset;
    final viewBottom = viewTop + position.viewportDimension;
    final firstVisibleLine = _findVisibleLineByYPosition(viewTop, lineHeight);
    final lastVisibleLine = _findVisibleLineByYPosition(viewBottom, lineHeight);
    double yOffset = _lineTop(firstVisibleLine);
    final diagnosticLines = _diagnosticLines();

    for (int i = firstVisibleLine; i <= lastVisibleLine && i < lineCount; i++) {
      if (_isFolded(i)) continue;
      final paragraph = highlighter.buildMiniMapHighlight(
        i,
        controller.getLineText(i),
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

      _paintDiagnostic(canvas, size, i, yOffset, diagnosticLines[i]);
      _paintSelection(canvas, size, i, yOffset, paragraph);
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
        oldDelegate.selectionColor != selectionColor ||
        oldDelegate.diagnosticsRepaint != diagnosticsRepaint ||
        oldDelegate.controller.selection != controller.selection;
  }

  Map<int, int> _diagnosticLines() {
    final lines = <int, int>{};
    for (final diagnostic in controller.diagnostics) {
      final startLine = diagnostic.range['start']?['line'];
      final endLine = diagnostic.range['end']?['line'];
      if (startLine is! int) continue;

      final lastLine = endLine is int && endLine >= startLine
          ? endLine
          : startLine;
      for (var line = startLine; line <= lastLine; line++) {
        final currentSeverity = lines[line];
        if (currentSeverity == null || diagnostic.severity < currentSeverity) {
          lines[line] = diagnostic.severity;
        }
      }
    }
    return lines;
  }

  void _paintDiagnostic(
    Canvas canvas,
    Size size,
    int line,
    double y,
    int? severity,
  ) {
    if (severity == null) return;

    final color = switch (severity) {
      1 => Colors.red,
      2 => Colors.orange,
      3 => Colors.blue,
      _ => Colors.grey,
    };
    canvas.drawRect(
      Rect.fromLTWH(math.max(size.width - 4, 0), y, 3, lineHeight),
      Paint()..color = color,
    );
  }

  int _findVisibleLineByYPosition(double y, double lineHeight) {
    final lineCount = controller.lineCount;
    if (lineCount <= 0) return 0;

    if (!y.isFinite || !lineHeight.isFinite || lineHeight <= 0) {
      return 0;
    }

    final hasActiveFolds = controller.foldings.values.any(
      (item) => item?.isFolded ?? false,
    );
    final hasVirtualBlocks = controller.virtualRemovedBlocks.isNotEmpty;

    if (!lineWrap && !hasActiveFolds && !hasVirtualBlocks) {
      return (y / lineHeight).floor().clamp(0, lineCount - 1);
    }

    var currentY = 0.0;
    for (int line = 0; line < lineCount; line++) {
      if (!_isFolded(line)) {
        if (currentY + lineHeight > y) return line;
        currentY += lineHeight;
      }

      for (final block in controller.virtualRemovedBlocks) {
        if (block.afterLine == line) {
          if (currentY + block.lineCount * lineHeight > y) return line;
          currentY += block.lineCount * lineHeight;
        }
      }
    }
    return lineCount - 1;
  }

  bool _isFolded(int line) {
    return controller.foldings.values.any(
      (fold) =>
          fold?.isFolded == true &&
          line > fold!.startIndex &&
          line <= fold.endIndex,
    );
  }

  double _lineTop(int lineIndex) {
    var top = 0.0;
    for (int line = 0; line < lineIndex; line++) {
      top += _lineAdvance(line);
    }
    return top;
  }

  double _lineAdvance(int line) {
    var advance = _isFolded(line) ? 0.0 : lineHeight;
    for (final block in controller.virtualRemovedBlocks) {
      if (block.afterLine == line) {
        advance += block.lineCount * lineHeight;
      }
    }
    return advance;
  }

  void _paintSelection(
    Canvas canvas,
    Size size,
    int line,
    double y,
    Paragraph paragraph,
  ) {
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final startLine = controller.getLineAtOffset(selection.start);
    final endLine = controller.getLineAtOffset(selection.end);
    if (line < startLine || line > endLine) return;

    final lineStart = controller.getLineStartOffset(line);
    final lineLength = controller.getLineText(line).length;
    final startColumn = line == startLine ? selection.start - lineStart : 0;
    final endColumn = line == endLine ? selection.end - lineStart : lineLength;
    if (endColumn <= startColumn) return;

    final width = (paragraph.maxIntrinsicWidth + 2).clamp(0.0, size.width - 8);
    final left = 8 + width * startColumn / math.max(lineLength, 1);
    final right = 8 + width * endColumn / math.max(lineLength, 1);
    canvas.drawRect(
      Rect.fromLTRB(left, y, math.max(right, left + 1), y + lineHeight),
      Paint()..color = selectionColor,
    );
  }
}
