import 'dart:isolate';
import 'dart:math' as math;

import 'rope.dart';

class LineSummary {
  final double height;
  final int lines;
  final bool isFolded;

  const LineSummary({
    required this.height,
    required this.lines,
    required this.isFolded,
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

const _isolateThreshold = 200000; // code units

/// Bracket-based fold ranges. Brackets inside strings and comments are not
/// excluded, so replace this with tree-sitter/LSP folds when available.
///
/// Small documents are scanned on the calling isolate. Larger ones are
/// scanned on a background isolate so the UI thread is not blocked.
Future<List<RustFoldRange>> foldsComputeAll({required Rope rope}) async {
  final text = rope.getText();
  if (text.length < _isolateThreshold) return _foldsFromText(text);
  return Isolate.run(() => _foldsFromText(text));
}

List<RustFoldRange> _foldsFromText(String text) {
  const closers = {0x7b: 0x7d, 0x5b: 0x5d, 0x28: 0x29}; // { [ (
  final result = <RustFoldRange>[];
  final stack = <(int closer, int line)>[];
  var line = 0;

  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == 10) {
      line++;
      continue;
    }
    final closer = closers[unit];
    if (closer != null) {
      stack.add((closer, line));
    } else if ((unit == 0x7d || unit == 0x5d || unit == 0x29) &&
        stack.isNotEmpty &&
        stack.last.$1 == unit) {
      final start = stack.removeLast().$2;
      if (line > start) {
        result.add(RustFoldRange(startLine: start, endLine: line));
      }
    }
  }
  result.sort((a, b) => a.startLine.compareTo(b.startLine));
  return result;
}

/// Offset of the bracket matching the one at [targetOffset], or -1.
/// Scans in 4 KB slices and gives up after [maxScan] code units.
int foldsFindMatchingBracket({
  required Rope rope,
  required int targetOffset,
  int maxScan = 100000,
}) {
  const open = {0x28: 0x29, 0x5b: 0x5d, 0x7b: 0x7d};
  const close = {0x29: 0x28, 0x5d: 0x5b, 0x7d: 0x7b};
  const chunk = 4096;

  final c = rope.codeUnitAt(targetOffset);
  final forward = open.containsKey(c);
  final match = forward ? open[c] : close[c];
  if (match == null) return -1;

  var depth = 0;
  if (forward) {
    final limit = math.min(rope.length, targetOffset + maxScan);
    for (var base = targetOffset; base < limit; base += chunk) {
      final text = rope.slice(base, math.min(base + chunk, limit));
      for (var i = 0; i < text.length; i++) {
        final u = text.codeUnitAt(i);
        if (u == c) {
          depth++;
        } else if (u == match && --depth == 0) {
          return base + i;
        }
      }
    }
  } else {
    final floor = math.max(0, targetOffset - maxScan);
    for (var end = targetOffset + 1; end > floor; end -= chunk) {
      final start = math.max(floor, end - chunk);
      final text = rope.slice(start, end);
      for (var i = text.length - 1; i >= 0; i--) {
        final u = text.codeUnitAt(i);
        if (u == c) {
          depth++;
        } else if (u == match && --depth == 0) {
          return start + i;
        }
      }
    }
  }
  return -1;
}

/// Indent info for visible lines. Blank (whitespace-only) lines are skipped.
/// Tabs advance to the next tab stop, so tab-indented files get correct
/// levels.
List<GuideBlock> guidesComputeViewport({
  required Rope rope,
  required int firstVisible,
  required int lastVisible,
  required int tabSize,
}) {
  final first = math.max(0, firstVisible);
  final last = math.min(lastVisible, rope.lineCount - 1);
  if (first > last) return const [];

  final tab = math.max(1, tabSize);
  final lines = rope.lineRange(first, last + 1);
  final blocks = <GuideBlock>[];

  for (var i = 0; i < lines.length; i++) {
    final text = lines[i];
    var column = 0;
    var j = 0;
    for (; j < text.length; j++) {
      final unit = text.codeUnitAt(j);
      if (unit == 0x20) {
        column++;
      } else if (unit == 0x09) {
        column += tab - (column % tab);
      } else {
        break;
      }
    }
    if (j == text.length || column == 0) continue; // blank or unindented

    final line = first + i;
    blocks.add(
      GuideBlock(
        startLine: line,
        endLine: line,
        indentLevel: column ~/ tab,
        leadingSpaces: column,
      ),
    );
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

  void pushLine({required double height, required bool isFolded}) =>
      _insertBlock(_root.summary.lines, _LineBlock(height, isFolded));

  void insertLine({
    required int lineIdx,
    required double height,
    required bool isFolded,
  }) => _insertBlock(lineIdx, _LineBlock(height, isFolded));

  void _insertBlock(int index, _LineBlock block) {
    final split = _root.insert(index.clamp(0, _root.summary.lines), block);
    if (split != null) _root = _LayoutInternal([_root, split]);
  }

  void removeLine({required int lineIdx}) {
    if (_root.summary.lines == 0) return;
    _root.remove(lineIdx.clamp(0, _root.summary.lines - 1));
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
    required int lineCount,
    required double height,
    Set<int> foldedLines = const {},
  }) {
    if (lineCount <= 0) {
      _root = _LayoutLeaf();
      return;
    }

    final leaves = <_LayoutNode>[];
    for (var start = 0; start < lineCount; start += _LayoutLeaf._capacity) {
      final end = math.min(start + _LayoutLeaf._capacity, lineCount);
      leaves.add(
        _LayoutLeaf([
          for (var line = start; line < end; line++)
            _LineBlock(height, foldedLines.contains(line)),
        ]),
      );
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

  int lenLines() => _root.summary.lines;

  void updateLine({
    required int lineIdx,
    required double height,
    required bool isFolded,
  }) => _root.update(lineIdx, _LineBlock(height, isFolded));

  double totalHeight() => _root.summary.height;

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
    final total = _root.summary.lines;
    final summaries = <LineSummary>[];
    for (var i = range.firstLine; i <= range.lastLine && i < total; i++) {
      final line = _root.lineAt(i);
      final height = line.folded
          ? 0.0
          : (line.height == 0 ? fallbackLineHeight : line.height);
      summaries.add(
        LineSummary(height: height, lines: 1, isFolded: line.folded),
      );
    }
    return ViewportFrame(
      firstLine: range.firstLine,
      lastLine: range.lastLine,
      firstLineY: range.firstLineY,
      lines: summaries,
    );
  }
}

class _LineBlock {
  final double height;
  final bool folded;

  const _LineBlock(this.height, this.folded);

  double get visibleHeight => folded ? 0 : height;
}

class _LayoutSummary {
  final double height;
  final int lines;

  const _LayoutSummary(this.height, this.lines);

  static const zero = _LayoutSummary(0, 0);

  _LayoutSummary operator +(_LayoutSummary other) =>
      _LayoutSummary(height + other.height, lines + other.lines);
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
    var height = 0.0;
    for (final line in lines) {
      height += line.visibleHeight;
    }
    _cachedSummary = _LayoutSummary(height, lines.length);
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
    return const _LayoutSeek(0, 0);
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
    for (var i = 0; i < children.length - 1; i++) {
      if (offset <= children[i].summary.lines) {
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
  _LayoutSeek seekHeight(double offset) {
    var remaining = offset;
    var y = 0.0;
    var line = 0;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final summary = child.summary;
      if (remaining < summary.height || i == children.length - 1) {
        final result = child.seekHeight(remaining);
        return _LayoutSeek(line + result.line, y + result.offset);
      }
      remaining -= summary.height;
      y += summary.height;
      line += summary.lines;
    }
    return const _LayoutSeek(0, 0);
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
