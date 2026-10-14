import 'dart:math' as math;

import 'rope.dart';

class LineSummary {
  final BigInt lenChars;
  final double height;
  final BigInt lines;

  const LineSummary({
    required this.lenChars,
    required this.height,
    required this.lines,
  });
}

class RustFoldRange {
  final int startLine;
  final int endLine;

  const RustFoldRange({required this.startLine, required this.endLine});
}

class GuideBlock {
  final int startLine;
  final int endLine;
  final int indentLevel;
  final int leadingSpaces;

  const GuideBlock({
    required this.startLine,
    required this.endLine,
    required this.indentLevel,
    required this.leadingSpaces,
  });
}

class VisibleLineRange {
  final int firstLine;
  final int lastLine;
  final double firstLineY;

  const VisibleLineRange({
    required this.firstLine,
    required this.lastLine,
    required this.firstLineY,
  });
}

class ViewportFrame {
  final int firstLine;
  final int lastLine;
  final double firstLineY;
  final List<LineSummary> lines;

  const ViewportFrame({
    required this.firstLine,
    required this.lastLine,
    required this.firstLineY,
    required this.lines,
  });
}

Future<List<RustFoldRange>> foldsComputeAll({required Rope rope}) async {
  final result = <RustFoldRange>[];
  final stack = <(String, int)>[];
  final openToClose = {'{': '}', '[': ']', '(': ')'};
  final closeToOpen = {
    for (final entry in openToClose.entries) entry.value: entry.key,
  };
  for (var line = 0; line < rope.lineCount; line++) {
    final text = rope.getLineText(line);
    for (final char in text.split('')) {
      if (openToClose.containsKey(char)) {
        stack.add((char, line));
      } else if (closeToOpen.containsKey(char) && stack.isNotEmpty) {
        final index = stack.last.$1 == closeToOpen[char]
            ? stack.length - 1
            : -1;
        if (index >= 0) {
          final start = stack.removeLast().$2;
          if (line > start) {
            result.add(RustFoldRange(startLine: start, endLine: line));
          }
        }
      }
    }
  }
  result.sort((a, b) => a.startLine.compareTo(b.startLine));
  return result;
}

int foldsFindMatchingBracket({required Rope rope, required int targetOffset}) {
  final value = rope.charAt(targetOffset);
  const pairs = {'(': ')', '[': ']', '{': '}'};
  const reversePairs = {')': '(', ']': '[', '}': '{'};
  final forward = pairs[value];
  final backward = reversePairs[value];
  if (forward == null && backward == null) return -1;
  final step = forward != null ? 1 : -1;
  final expected = forward ?? backward!;
  var depth = 0;
  for (
    var offset = targetOffset;
    offset >= 0 && offset < rope.length;
    offset += step
  ) {
    final char = rope.charAt(offset);
    if (char == value) {
      depth++;
    } else if (char == expected) {
      depth--;
      if (depth == 0) return offset;
    }
  }
  return -1;
}

List<GuideBlock> guidesComputeViewport({
  required Rope rope,
  required BigInt firstVisible,
  required BigInt lastVisible,
  required BigInt tabSize,
}) {
  final blocks = <GuideBlock>[];
  for (
    var line = firstVisible.toInt();
    line <= lastVisible.toInt() && line < rope.lineCount;
    line++
  ) {
    final text = rope.getLineText(line);
    final leading = text.length - text.trimLeft().length;
    if (leading > 0) {
      blocks.add(
        GuideBlock(
          startLine: line,
          endLine: line,
          indentLevel: (leading / math.max(1, tabSize.toInt())).floor(),
          leadingSpaces: leading,
        ),
      );
    }
  }
  return blocks;
}

Future<List<String>> wordsExtract({required Rope rope}) async {
  return RegExp(
    r'[\p{L}\p{N}_]+',
    unicode: true,
  ).allMatches(rope.getText()).map((match) => match.group(0)!).toSet().toList();
}

class LayoutMap {
  static const _nodeCapacity = 32;
  _LayoutNode _root = _LayoutLeaf();

  void pushLine({
    required BigInt lenChars,
    required double height,
    required bool isFolded,
  }) {
    final split = _root.insert(
      _root.summary.lines,
      _LineBlock(lenChars.toInt(), height, isFolded),
    );
    if (split != null) _root = _LayoutInternal([_root, split]);
  }

  void insertLine({
    required BigInt lineIdx,
    required BigInt lenChars,
    required double height,
    required bool isFolded,
  }) {
    final index = lineIdx.toInt().clamp(0, _root.summary.lines);
    final split = _root.insert(
      index,
      _LineBlock(lenChars.toInt(), height, isFolded),
    );
    if (split != null) _root = _LayoutInternal([_root, split]);
  }

  void removeLine({required BigInt lineIdx}) {
    if (_root.summary.lines == 0) return;
    _root.remove(lineIdx.toInt().clamp(0, _root.summary.lines - 1));
    if (_root is _LayoutInternal &&
        (_root as _LayoutInternal).children.isEmpty) {
      _root = _LayoutLeaf();
    }
    while (_root is _LayoutInternal &&
        (_root as _LayoutInternal).children.length == 1) {
      _root = (_root as _LayoutInternal).children.single;
    }
  }

  void clear() => _root = _LayoutLeaf();

  void rebuild({
    required List<int> lineLengths,
    required double height,
    Set<int> foldedLines = const {},
  }) {
    final lineCount = lineLengths.length;
    if (lineCount <= 0) {
      _root = _LayoutLeaf();
      return;
    }

    final leaves = <_LayoutNode>[];
    for (var start = 0; start < lineCount; start += _LayoutLeaf._capacity) {
      final end = math.min(start + _LayoutLeaf._capacity, lineCount);
      final lines = <_LineBlock>[];
      for (var line = start; line < end; line++) {
        lines.add(
          _LineBlock(lineLengths[line], height, foldedLines.contains(line)),
        );
      }
      leaves.add(_LayoutLeaf(lines));
    }

    var level = leaves;
    while (level.length > _nodeCapacity) {
      final nextLevel = <_LayoutNode>[];
      for (var start = 0; start < level.length; start += _nodeCapacity) {
        nextLevel.add(
          _LayoutInternal(
            level.sublist(start, math.min(start + _nodeCapacity, level.length)),
          ),
        );
      }
      level = nextLevel;
    }
    _root = level.length == 1 ? level.single : _LayoutInternal(level);
  }

  BigInt lenLines() => BigInt.from(_root.summary.lines);

  void updateLine({
    required BigInt lineIdx,
    required BigInt lenChars,
    required double height,
    required bool isFolded,
  }) {
    _root.update(
      lineIdx.toInt(),
      _LineBlock(lenChars.toInt(), height, isFolded),
    );
  }

  double totalHeight() => _root.summary.height;

  int visualLineFromCharOffset({required BigInt charOffset}) {
    if (_root.summary.lines == 0) return 0;
    return _root.seekChars(charOffset.toInt()).line;
  }

  VisibleLineRange visibleRangeByHeight({
    required double viewTop,
    required double viewBottom,
  }) {
    if (_root.summary.lines == 0) {
      return const VisibleLineRange(firstLine: 0, lastLine: 0, firstLineY: 0);
    }
    final first = _root.seekHeight(math.max(0, viewTop));
    final last = _root.seekHeight(math.max(viewTop, viewBottom));
    final maxLine = _root.summary.lines - 1;
    return VisibleLineRange(
      firstLine: first.line.clamp(0, maxLine),
      lastLine: last.line.clamp(first.line, maxLine),
      firstLineY: first.offset,
    );
  }

  ViewportFrame buildViewportFrame({
    required double viewTop,
    required double viewBottom,
    required double fallbackLineHeight,
  }) {
    final range = visibleRangeByHeight(
      viewTop: viewTop,
      viewBottom: viewBottom,
    );
    final summaries = [
      for (
        var i = range.firstLine;
        i <= range.lastLine && i < _root.summary.lines;
        i++
      ) ...[
        () {
          final line = _root.lineAt(i);
          return LineSummary(
            lenChars: BigInt.from(line.lenChars),
            height: line.visibleHeight == 0
                ? fallbackLineHeight
                : line.visibleHeight,
            lines: BigInt.one,
          );
        }(),
      ],
    ];
    return ViewportFrame(
      firstLine: range.firstLine,
      lastLine: range.lastLine,
      firstLineY: range.firstLineY,
      lines: summaries,
    );
  }
}

class _LineBlock {
  final int lenChars;
  final double height;
  final bool folded;

  const _LineBlock(this.lenChars, this.height, this.folded);

  double get visibleHeight => folded ? 0 : height;
}

class _LayoutSummary {
  final int chars;
  final double height;
  final int lines;

  const _LayoutSummary(this.chars, this.height, this.lines);

  static const zero = _LayoutSummary(0, 0, 0);

  _LayoutSummary operator +(_LayoutSummary other) => _LayoutSummary(
    chars + other.chars,
    height + other.height,
    lines + other.lines,
  );
}

class _LayoutSeek {
  final int line;
  final double offset;

  const _LayoutSeek(this.line, this.offset);
}

abstract class _LayoutNode {
  _LayoutSummary get summary;

  _LayoutNode? insert(int index, _LineBlock block);
  void remove(int index);
  void update(int index, _LineBlock block);
  _LayoutSeek seekChars(int offset);
  _LayoutSeek seekHeight(double offset);
  _LineBlock lineAt(int index);
}

class _LayoutLeaf extends _LayoutNode {
  static const _capacity = LayoutMap._nodeCapacity;
  final List<_LineBlock> lines;
  late _LayoutSummary _cachedSummary;

  _LayoutLeaf([List<_LineBlock>? lines]) : lines = lines ?? [] {
    _refreshSummary();
  }

  void _refreshSummary() {
    var chars = 0;
    var height = 0.0;
    for (final line in lines) {
      chars += line.lenChars;
      height += line.visibleHeight;
    }
    _cachedSummary = _LayoutSummary(chars, height, lines.length);
  }

  @override
  _LayoutSummary get summary => _cachedSummary;

  @override
  _LayoutNode? insert(int index, _LineBlock block) {
    lines.insert(index.clamp(0, lines.length), block);
    if (lines.length <= _capacity) {
      _refreshSummary();
      return null;
    }
    final midpoint = lines.length ~/ 2;
    final right = _LayoutLeaf(lines.sublist(midpoint));
    lines.removeRange(midpoint, lines.length);
    _refreshSummary();
    return right;
  }

  @override
  void remove(int index) {
    if (index >= 0 && index < lines.length) lines.removeAt(index);
    _refreshSummary();
  }

  @override
  void update(int index, _LineBlock block) {
    if (index >= 0 && index < lines.length) lines[index] = block;
    _refreshSummary();
  }

  @override
  _LayoutSeek seekChars(int offset) {
    var remaining = offset;
    for (var i = 0; i < lines.length; i++) {
      if (remaining <= lines[i].lenChars) return _LayoutSeek(i, 0);
      remaining -= lines[i].lenChars;
    }
    return _LayoutSeek(lines.isEmpty ? 0 : lines.length - 1, 0);
  }

  @override
  _LayoutSeek seekHeight(double offset) {
    var remaining = offset;
    var y = 0.0;
    for (var i = 0; i < lines.length; i++) {
      final height = lines[i].visibleHeight;
      if (remaining < height || i == lines.length - 1) {
        return _LayoutSeek(i, y);
      }
      remaining -= height;
      y += height;
    }
    return _LayoutSeek(0, 0);
  }

  @override
  _LineBlock lineAt(int index) => lines[index];
}

class _LayoutInternal extends _LayoutNode {
  static const _capacity = LayoutMap._nodeCapacity;
  final List<_LayoutNode> children;
  late _LayoutSummary _cachedSummary;

  _LayoutInternal(this.children) {
    _refreshSummary();
  }

  void _refreshSummary() {
    var result = _LayoutSummary.zero;
    for (final child in children) {
      result += child.summary;
    }
    _cachedSummary = result;
  }

  @override
  _LayoutSummary get summary => _cachedSummary;

  @override
  _LayoutNode? insert(int index, _LineBlock block) {
    var offset = index;
    var childIndex = children.length - 1;
    for (var i = 0; i < children.length; i++) {
      if (offset <= children[i].summary.lines || i == children.length - 1) {
        childIndex = i;
        break;
      }
      offset -= children[i].summary.lines;
    }
    final split = children[childIndex].insert(offset, block);
    if (split != null) children.insert(childIndex + 1, split);
    _refreshSummary();
    if (children.length <= _capacity) return null;
    final midpoint = children.length ~/ 2;
    final right = _LayoutInternal(children.sublist(midpoint));
    children.removeRange(midpoint, children.length);
    _refreshSummary();
    return right;
  }

  @override
  void remove(int index) {
    var offset = index;
    for (var i = 0; i < children.length; i++) {
      final lines = children[i].summary.lines;
      if (offset < lines) {
        children[i].remove(offset);
        if (children[i].summary.lines == 0) children.removeAt(i);
        _refreshSummary();
        return;
      }
      offset -= lines;
    }
  }

  @override
  void update(int index, _LineBlock block) {
    var offset = index;
    for (final child in children) {
      if (offset < child.summary.lines) {
        child.update(offset, block);
        _refreshSummary();
        return;
      }
      offset -= child.summary.lines;
    }
  }

  @override
  _LayoutSeek seekChars(int offset) {
    var remaining = offset;
    var line = 0;
    for (final child in children) {
      final summary = child.summary;
      if (remaining <= summary.chars) {
        final result = child.seekChars(remaining);
        return _LayoutSeek(line + result.line, result.offset);
      }
      remaining -= summary.chars;
      line += summary.lines;
    }
    return _LayoutSeek(math.max(0, summary.lines - 1), 0);
  }

  @override
  _LayoutSeek seekHeight(double offset) {
    var remaining = offset;
    var y = 0.0;
    var line = 0;
    for (final child in children) {
      final summary = child.summary;
      if (remaining < summary.height || child == children.last) {
        final result = child.seekHeight(remaining);
        return _LayoutSeek(line + result.line, y + result.offset);
      }
      remaining -= summary.height;
      y += summary.height;
      line += summary.lines;
    }
    return _LayoutSeek(0, 0);
  }

  @override
  _LineBlock lineAt(int index) {
    var offset = index;
    for (final child in children) {
      if (offset < child.summary.lines) return child.lineAt(offset);
      offset -= child.summary.lines;
    }
    throw RangeError.index(index, this);
  }
}
