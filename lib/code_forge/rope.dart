import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A run of text with a single resolved direction. Offsets are UTF-16 code
/// units, matching [TextSelection], [String.length] and LSP positions.
class BiDiSegment {
  final int start;
  final int end;
  final TextDirection direction;

  const BiDiSegment({
    required this.start,
    required this.end,
    required this.direction,
  });
}

class SelectionState {
  final int baseOffset;
  final int extentOffset;

  const SelectionState({required this.baseOffset, required this.extentOffset});
}

/// A persistent (immutable-node) B-tree rope indexed in UTF-16 code units.
///
/// Design notes
/// * All offsets and lengths are UTF-16 code units, so they line up with
///   Flutter's `TextSelection`/`TextPosition`, `String.length` and LSP.
///   Leaf boundaries never split a surrogate pair. Callers must not pass an
///   offset that lands in the middle of a pair.
/// * Nodes are immutable. An edit copies only the O(log n) nodes on the path
///   and shares the rest, so [copy] is O(1) and the `*Immutable` helpers cost
///   O(log n). Cheap snapshots make undo history simple.
/// * Every node caches length, newline count and strong RTL/LTR counts, so
///   line seeks and [textDirection] are O(log n) / O(1).
/// * Deletes merge underfull siblings so the tree does not degrade.
///
/// Only `\n` counts as a line break. `\r` before `\n` is stripped from line
/// text. Normalise lone `\r` on load if you need to support old Mac files.
///
/// Complexity (n = document length, k = result size):
///   insert/delete/replace      O(log n + leaf size)
///   getLineStartOffset etc.    O(log n + leaf size)
///   slice / lineRange          O(log n + k)
///   getText / lineLengths      O(n)  (export, save, stats only)
class Rope {
  static const _leafCapacity = 1024;
  static const _nodeCapacity = 32;
  static const _minLeaf = _leafCapacity ~/ 4;
  static const _minNode = _nodeCapacity ~/ 4;
  static const _loadChunk = _leafCapacity * 3 ~/ 4;
  static const _insertChunk = _leafCapacity ~/ 2;

  _Node _root;
  SelectionState _selection = const SelectionState(
    baseOffset: 0,
    extentOffset: 0,
  );

  Rope([String initialText = '']) : _root = _Node.fromText(initialText);

  Rope._fromRoot(this._root, this._selection);

  Rope get core => this;
  int get length => _root.length;
  int get lineCount => _root.newlines + 1;

  /// O(1): nodes are immutable, so the snapshot shares the whole tree.
  Rope copy() => Rope._fromRoot(_root, _selection);

  Rope insertImmutable(int position, String text) {
    final result = copy();
    result.insert(position, text);
    return result;
  }

  Rope deleteImmutable(int start, int end) {
    final result = copy();
    result.delete(start, end);
    return result;
  }

  /// Appends [other] leaf by leaf. Never materialises either document.
  Rope concatImmutable(Rope other) {
    final result = copy();
    other._root.forEachLeaf((leaf) => result.insert(result.length, leaf));
    return result;
  }

  /// Both halves share structure with this rope. [position] must not be in
  /// the middle of a surrogate pair.
  (Rope, Rope) splitImmutable(int position) {
    if (position < 0 || position > length) {
      throw RangeError('Invalid position: $position for length $length');
    }
    final left = copy()..delete(position, length);
    final right = copy()..delete(0, position);
    left.setSelection(selection);
    right.setSelection(selection);
    return (left, right);
  }

  TextSelection get selection => TextSelection(
    baseOffset: _selection.baseOffset,
    extentOffset: _selection.extentOffset,
  );

  void setSelection(TextSelection value) {
    _selection = SelectionState(
      baseOffset: value.baseOffset.clamp(0, length),
      extentOffset: value.extentOffset.clamp(0, length),
    );
  }

  /// Replaces `[start, end)` with [replacement] and remaps the selection.
  SelectionState replaceRangeAndUpdateSelection({
    required int start,
    required int end,
    required String replacement,
    required bool preserveOldCursor,
    required int oldBase,
    required int oldExtent,
  }) {
    final safeStart = start.clamp(0, length);
    final safeEnd = end.clamp(safeStart, length);
    final removedLength = safeEnd - safeStart;
    final replacementLength = replacement.length;

    replace(safeStart, safeEnd, replacement);

    int mapOffset(int offset) {
      if (offset <= safeStart) return offset;
      if (offset >= safeEnd) return offset + replacementLength - removedLength;
      return safeStart + math.min(offset - safeStart, replacementLength);
    }

    final endOffset = safeStart + replacementLength;
    final total = length;
    _selection = SelectionState(
      baseOffset: (preserveOldCursor ? mapOffset(oldBase) : endOffset).clamp(
        0,
        total,
      ),
      extentOffset: (preserveOldCursor ? mapOffset(oldExtent) : endOffset)
          .clamp(0, total),
    );
    return _selection;
  }

  /// O(n). Use for save/export only, never per keystroke.
  String getText() {
    final buffer = StringBuffer();
    _root.writeTo(buffer);
    return buffer.toString();
  }

  String substring(int start, [int? end]) => slice(start, end ?? length);

  String slice(int start, int end) {
    final safeStart = start.clamp(0, length);
    final safeEnd = end.clamp(safeStart, length);
    if (safeStart == safeEnd) return '';
    return _root.slice(safeStart, safeEnd);
  }

  /// UTF-16 code unit at [position], or -1 when out of range.
  int codeUnitAt(int position) {
    if (position < 0 || position >= length) return -1;
    return _root.codeUnitAt(position);
  }

  /// The character at [position]. Returns the whole pair for an astral
  /// character whose high surrogate sits at [position].
  String charAt(int position) {
    final unit = codeUnitAt(position);
    if (unit < 0) return '';
    if (_U.isHigh(unit)) {
      final next = codeUnitAt(position + 1);
      if (next >= 0 && _U.isLow(next)) {
        return String.fromCharCodes([unit, next]);
      }
    }
    return String.fromCharCode(unit);
  }

  void insert(int position, String text) {
    if (text.isEmpty) return;
    var offset = position.clamp(0, length);

    if (text.length <= _insertChunk) {
      _insertChunkAt(offset, text);
      return;
    }
    for (final chunk in _U.chunk(text, _insertChunk)) {
      _insertChunkAt(offset, chunk);
      offset += chunk.length;
    }
  }

  void _insertChunkAt(int offset, String chunk) {
    final (node, split) = _root.insert(offset, chunk);
    _root = split == null ? node : _Internal([node, split]);
  }

  void delete(int start, int end) {
    final safeStart = start.clamp(0, length);
    final safeEnd = end.clamp(safeStart, length);
    if (safeStart == safeEnd) return;

    var root = _root.remove(safeStart, safeEnd) ?? _Leaf('');
    while (root is _Internal && root.children.length == 1) {
      root = root.children.first;
    }
    _root = root;
  }

  void replace(int start, int end, String text) {
    delete(start, end);
    insert(start.clamp(0, length), text);
  }

  /// Lines `[startLine, endLine)` fetched with a single slice and split.
  /// Use this for viewport rendering, highlighting and gutters.
  List<String> lineRange(int startLine, int endLine) {
    final first = startLine.clamp(0, lineCount);
    final last = endLine.clamp(first, lineCount);
    if (first == last) return const [];

    final startOffset = getLineStartOffset(first);
    final endOffset = last >= lineCount
        ? length
        : getLineStartOffset(last) - 1; // exclude the newline ending last-1
    final parts = slice(startOffset, endOffset).split('\n');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.endsWith('\r')) parts[i] = part.substring(0, part.length - 1);
    }
    return parts;
  }

  @Deprecated('O(n) and not cached. Use lineRange for visible lines.')
  List<String> get cachedLines => lineRange(0, lineCount);

  @Deprecated('Renamed to lineRange.')
  List<String> cachedLinesRange(int startLine, int endLine) =>
      lineRange(startLine, endLine);

  /// Lazily yields lines in batches. Still O(n) if fully consumed.
  Iterable<String> get lines sync* {
    for (var line = 0; line < lineCount; line += 256) {
      yield* lineRange(line, line + 256);
    }
  }

  String getLineText(int lineIndex) {
    final start = getLineStartOffset(lineIndex);
    var end = findLineEnd(start);
    if (end > start && codeUnitAt(end - 1) == 13) end--;
    return slice(start, end);
  }

  int getLineAtOffset(int charOffset) =>
      _root.newlinesBefore(charOffset.clamp(0, length));

  int getLineStartOffset(int lineIndex) {
    final index = lineIndex.clamp(0, lineCount - 1);
    if (index == 0) return 0;
    return (_root.nthNewline(index - 1) + 1).clamp(0, length);
  }

  int findLineStart(int offset) => getLineStartOffset(getLineAtOffset(offset));

  int findLineEnd(int offset) =>
      _root.nextNewline(offset.clamp(0, length)) ?? length;

  /// Length of the line in code units, excluding `\n` and a preceding `\r`.
  int lineLengthAt(int lineIndex) {
    final start = getLineStartOffset(lineIndex);
    final end = findLineEnd(start);
    final lineLength = end - start;
    return lineLength > 0 && codeUnitAt(end - 1) == 13
        ? lineLength - 1
        : lineLength;
  }

  /// O(n). Length of every line in code units.
  List<int> lineLengths() {
    final lengths = <int>[];
    var current = 0;
    var previousWasCarriageReturn = false;

    _root.forEachLeaf((chunk) {
      for (var i = 0; i < chunk.length; i++) {
        final unit = chunk.codeUnitAt(i);
        if (unit == 10) {
          lengths.add(previousWasCarriageReturn ? current - 1 : current);
          current = 0;
          previousWasCarriageReturn = false;
        } else {
          current++;
          previousWasCarriageReturn = unit == 13;
        }
      }
    });
    lengths.add(previousWasCarriageReturn ? current - 1 : current);
    return lengths;
  }

  TextDirection get textDirection =>
      _root.rtl > _root.ltr ? TextDirection.rtl : TextDirection.ltr;

  bool get containsRtl => textDirection == TextDirection.rtl;
  bool get isRtl => containsRtl;
  bool get isLtr => !containsRtl;

  /// True when the document has both strong RTL and strong LTR text. O(1).
  bool get isMixed => _root.rtl > 0 && _root.ltr > 0;
  TextDirection get primaryDirection => textDirection;

  /// Direction runs for the whole document. O(n). Prefer
  /// [getBiDiSegmentsForLine] / [getBiDiSegmentsInRange] when rendering.
  List<BiDiSegment> get bidiSegments => getBiDiSegmentsInRange(0, length);

  List<BiDiSegment> getBiDiSegmentsForLine(int lineIndex) {
    final start = getLineStartOffset(lineIndex);
    return getBiDiSegmentsInRange(start, findLineEnd(start));
  }

  /// Splits `[start, end)` into runs of one strong direction. Neutral
  /// characters attach to the run before them (leading neutrals join the
  /// first run). Costs O(log n + range length).
  List<BiDiSegment> getBiDiSegmentsInRange(int start, int end) {
    final from = start.clamp(0, length);
    final to = end.clamp(from, length);
    if (from == to) return const [];

    final text = slice(from, to);
    final segments = <BiDiSegment>[];
    TextDirection? current;
    var runStart = 0;

    for (var i = 0; i < text.length; i++) {
      final direction = _U.strongDirection(text.codeUnitAt(i));
      if (direction == null) continue;
      if (current == null) {
        current = direction;
      } else if (direction != current) {
        segments.add(
          BiDiSegment(
            start: from + runStart,
            end: from + i,
            direction: current,
          ),
        );
        runStart = i;
        current = direction;
      }
    }
    segments.add(
      BiDiSegment(
        start: from + runStart,
        end: to,
        direction: current ?? TextDirection.ltr,
      ),
    );
    return segments;
  }

  List<(int start, int end)> getRtlSegments() => bidiSegments
      .where((segment) => segment.direction == TextDirection.rtl)
      .map((segment) => (segment.start, segment.end))
      .toList();

  String toStringWithBiDiControls() {
    final text = getText();
    if (!containsRtl) return text;
    return '${String.fromCharCode(0x202b)}$text${String.fromCharCode(0x202c)}';
  }
}

abstract final class _U {
  static bool isHigh(int c) => c >= 0xd800 && c <= 0xdbff;
  static bool isLow(int c) => c >= 0xdc00 && c <= 0xdfff;

  static bool isRtl(int c) =>
      (c >= 0x590 && c <= 0x8ff) || // Hebrew, Arabic, Syriac, Thaana, ...
      (c >= 0xfb1d && c <= 0xfdff) || // Hebrew/Arabic presentation forms A
      (c >= 0xfe70 && c <= 0xfeff) || // Arabic presentation forms B
      c == 0x200f; // RLM

  static bool isStrongLtr(int c) {
    if (c < 0x80) return (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);
    if (c < 0xc0 || c == 0xd7 || c == 0xf7) return false;
    if (isRtl(c)) return false;
    if (c >= 0x2000 && c <= 0x2bff) return false; // punctuation, symbols
    if (c >= 0x3000 && c <= 0x303f) return false; // CJK punctuation
    if (c >= 0xd800 && c <= 0xdfff) return false; // surrogates (emoji, etc.)
    return true;
  }

  static TextDirection? strongDirection(int c) {
    if (isRtl(c)) return TextDirection.rtl;
    if (isStrongLtr(c)) return TextDirection.ltr;
    return null;
  }

  /// Largest end <= [tentativeEnd] (or just past it) that does not split a
  /// surrogate pair.
  static int safeEnd(String s, int start, int tentativeEnd) {
    if (tentativeEnd >= s.length) return s.length;
    if (isHigh(s.codeUnitAt(tentativeEnd - 1)) &&
        isLow(s.codeUnitAt(tentativeEnd))) {
      return tentativeEnd - 1 > start ? tentativeEnd - 1 : tentativeEnd + 1;
    }
    return tentativeEnd;
  }

  static List<String> chunk(String text, int size) {
    final out = <String>[];
    var i = 0;
    while (i < text.length) {
      final end = safeEnd(text, i, math.min(i + size, text.length));
      out.add(text.substring(i, end));
      i = end;
    }
    return out;
  }
}

abstract class _Node {
  final int length;
  final int newlines;
  final int rtl;
  final int ltr;

  const _Node(this.length, this.newlines, this.rtl, this.ltr);

  factory _Node.fromText(String text) {
    if (text.isEmpty) return _Leaf('');
    var level = <_Node>[
      for (final chunk in _U.chunk(text, Rope._loadChunk)) _Leaf(chunk),
    ];
    while (level.length > 1) {
      final next = <_Node>[];
      for (var i = 0; i < level.length; i += Rope._nodeCapacity) {
        next.add(
          _Internal(
            level.sublist(i, math.min(i + Rope._nodeCapacity, level.length)),
          ),
        );
      }
      level = next;
    }
    return level.single;
  }

  /// Returns the replacement node and an optional right sibling if it split.
  (_Node, _Node?) insert(int index, String text);

  /// Removes `[start, end)` (local, already clamped and non-empty). Returns
  /// null when the node becomes empty.
  _Node? remove(int start, int end);

  String slice(int start, int end);
  int codeUnitAt(int index);
  int newlinesBefore(int offset);
  int nthNewline(int index);
  int? nextNewline(int offset);
  void writeTo(StringBuffer buffer);
  void forEachLeaf(void Function(String) callback);
}

class _Leaf extends _Node {
  final String value;

  factory _Leaf(String value) {
    var newlines = 0;
    var rtl = 0;
    var ltr = 0;
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit == 10) {
        newlines++;
        continue;
      }
      final direction = _U.strongDirection(unit);
      if (direction == TextDirection.rtl) {
        rtl++;
      } else if (direction == TextDirection.ltr) {
        ltr++;
      }
    }
    return _Leaf._(value, newlines, rtl, ltr);
  }

  _Leaf._(this.value, int newlines, int rtl, int ltr)
    : super(value.length, newlines, rtl, ltr);

  @override
  (_Node, _Node?) insert(int index, String text) {
    final combined = value.substring(0, index) + text + value.substring(index);
    if (combined.length <= Rope._leafCapacity) return (_Leaf(combined), null);

    var mid = combined.length >> 1;
    if (_U.isHigh(combined.codeUnitAt(mid - 1)) &&
        _U.isLow(combined.codeUnitAt(mid))) {
      mid = mid - 1 > 0 ? mid - 1 : mid + 1;
    }
    return (_Leaf(combined.substring(0, mid)), _Leaf(combined.substring(mid)));
  }

  @override
  _Node? remove(int start, int end) {
    if (start <= 0 && end >= length) return null;
    return _Leaf(value.substring(0, start) + value.substring(end));
  }

  @override
  String slice(int start, int end) => value.substring(start, end);

  @override
  int codeUnitAt(int index) => value.codeUnitAt(index);

  @override
  int newlinesBefore(int offset) {
    var count = 0;
    var pos = value.indexOf('\n');
    while (pos >= 0 && pos < offset) {
      count++;
      pos = value.indexOf('\n', pos + 1);
    }
    return count;
  }

  @override
  int nthNewline(int index) {
    var pos = -1;
    for (var i = 0; i <= index; i++) {
      pos = value.indexOf('\n', pos + 1);
      if (pos < 0) return length;
    }
    return pos;
  }

  @override
  int? nextNewline(int offset) {
    final pos = value.indexOf('\n', offset);
    return pos < 0 ? null : pos;
  }

  @override
  void writeTo(StringBuffer buffer) => buffer.write(value);

  @override
  void forEachLeaf(void Function(String) callback) => callback(value);
}

class _Internal extends _Node {
  final List<_Node> children;

  factory _Internal(List<_Node> children) {
    var length = 0;
    var newlines = 0;
    var rtl = 0;
    var ltr = 0;
    for (final child in children) {
      length += child.length;
      newlines += child.newlines;
      rtl += child.rtl;
      ltr += child.ltr;
    }
    return _Internal._(children, length, newlines, rtl, ltr);
  }

  _Internal._(this.children, int length, int newlines, int rtl, int ltr)
    : super(length, newlines, rtl, ltr);

  @override
  (_Node, _Node?) insert(int index, String text) {
    var offset = index;
    var childIndex = children.length - 1;
    for (var i = 0; i < children.length - 1; i++) {
      if (offset <= children[i].length) {
        childIndex = i;
        break;
      }
      offset -= children[i].length;
    }

    final (node, split) = children[childIndex].insert(offset, text);
    final updated = List<_Node>.of(children);
    updated[childIndex] = node;
    if (split != null) updated.insert(childIndex + 1, split);

    if (updated.length <= Rope._nodeCapacity) return (_Internal(updated), null);
    final mid = updated.length >> 1;
    return (
      _Internal(updated.sublist(0, mid)),
      _Internal(updated.sublist(mid)),
    );
  }

  @override
  _Node? remove(int start, int end) {
    final kept = <_Node>[];
    var cursor = 0;
    for (final child in children) {
      final childStart = cursor;
      final childEnd = childStart + child.length;
      cursor = childEnd;

      if (childEnd <= start || childStart >= end) {
        kept.add(child);
      } else if (start <= childStart && end >= childEnd) {
        continue;
      } else {
        final result = child.remove(
          math.max(start - childStart, 0),
          math.min(end - childStart, child.length),
        );
        if (result != null) kept.add(result);
      }
    }
    if (kept.isEmpty) return null;
    return _Internal(_mergeUnderfull(kept));
  }

  /// Merges adjacent underfull siblings of the same kind. All leaves sit at
  /// the same depth, so siblings are always the same type.
  static List<_Node> _mergeUnderfull(List<_Node> nodes) {
    if (nodes.length < 2) return nodes;
    final out = <_Node>[nodes.first];
    for (var i = 1; i < nodes.length; i++) {
      final a = out.last;
      final b = nodes[i];
      if (a is _Leaf && b is _Leaf) {
        final small = a.length < Rope._minLeaf || b.length < Rope._minLeaf;
        if (small && a.length + b.length <= Rope._leafCapacity) {
          out[out.length - 1] = _Leaf(a.value + b.value);
          continue;
        }
      } else if (a is _Internal && b is _Internal) {
        final small =
            a.children.length < Rope._minNode ||
            b.children.length < Rope._minNode;
        if (small &&
            a.children.length + b.children.length <= Rope._nodeCapacity) {
          out[out.length - 1] = _Internal([...a.children, ...b.children]);
          continue;
        }
      }
      out.add(b);
    }
    return out;
  }

  @override
  String slice(int start, int end) {
    final buffer = StringBuffer();
    var cursor = 0;
    for (final child in children) {
      final childEnd = cursor + child.length;
      if (childEnd > start && cursor < end) {
        buffer.write(
          child.slice(
            math.max(start - cursor, 0),
            math.min(end - cursor, child.length),
          ),
        );
      }
      cursor = childEnd;
      if (cursor >= end) break;
    }
    return buffer.toString();
  }

  @override
  int codeUnitAt(int index) {
    var offset = index;
    for (final child in children) {
      if (offset < child.length) return child.codeUnitAt(offset);
      offset -= child.length;
    }
    return -1;
  }

  @override
  int newlinesBefore(int offset) {
    var remaining = offset;
    var result = 0;
    for (final child in children) {
      if (remaining <= child.length) {
        return result + child.newlinesBefore(remaining);
      }
      remaining -= child.length;
      result += child.newlines;
    }
    return result;
  }

  @override
  int nthNewline(int index) {
    var remaining = index;
    var offset = 0;
    for (final child in children) {
      if (remaining < child.newlines) {
        return offset + child.nthNewline(remaining);
      }
      remaining -= child.newlines;
      offset += child.length;
    }
    return length;
  }

  @override
  int? nextNewline(int offset) {
    var cursor = 0;
    for (final child in children) {
      final childEnd = cursor + child.length;
      if (child.newlines > 0 && offset < childEnd) {
        final result = child.nextNewline(offset > cursor ? offset - cursor : 0);
        if (result != null) return cursor + result;
      }
      cursor = childEnd;
    }
    return null;
  }

  @override
  void writeTo(StringBuffer buffer) {
    for (final child in children) {
      child.writeTo(buffer);
    }
  }

  @override
  void forEachLeaf(void Function(String) callback) {
    for (final child in children) {
      child.forEachLeaf(callback);
    }
  }
}
