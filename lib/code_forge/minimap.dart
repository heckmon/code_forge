import 'dart:ui';

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
  }) : super(repaint: scrollCtrl);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPaint(Paint()..color = bgColor);

    final lineCount = controller.lineCount;
    final viewTop = scrollCtrl.offset;
    final viewBottom = viewTop + scrollCtrl.position.viewportDimension;
    final firstVisibleLine = _findVisibleLineByYPosition(viewTop, lineHeight);
    final lastVisibleLine = _findVisibleLineByYPosition(viewBottom, lineHeight);
    double y_offset = firstVisibleLine * lineHeight;

    for (int i = firstVisibleLine; i <= lastVisibleLine && i < lineCount; i++) {
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

      canvas.drawParagraph(paragraph, Offset(8, y_offset));
      y_offset += lineHeight;
    }
  }

  @override
  bool shouldRepaint(covariant MiniMapPainter oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.bgColor != bgColor ||
        oldDelegate.fontSize != fontSize;
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

    if (lineWrap && !hasActiveFolds && !hasVirtualBlocks) {
      //TODO
    }

    if (!lineWrap && !hasActiveFolds && hasVirtualBlocks) {
      //TODO
    }

    if (!lineWrap && hasActiveFolds) {
      //TODO
    }

    return lineCount - 1;
  }
}
