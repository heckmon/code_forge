import 'package:flutter/material.dart';

class BiDiSegment {
  final BigInt start;
  final BigInt end;
  final TextDirection direction;

  const BiDiSegment({
    required this.start,
    required this.end,
    required this.direction,
  });
}

class SelectionState {
  final BigInt baseOffset;
  final BigInt extentOffset;

  const SelectionState({required this.baseOffset, required this.extentOffset});
}

/// A high-fanout B-tree rope.
///
/// Leaves contain bounded Unicode chunks. Internal nodes cache character and
/// newline counts, allowing edits and line/character seeks to descend the tree
/// without materialising the document.
class Rope {
  static const _leafCapacity = 1024;
  static const _nodeCapacity = 32;
  late _RopeNode _root;
  SelectionState _selection = SelectionState(
    baseOffset: BigInt.zero,
    extentOffset: BigInt.zero,
  );

  Rope([String initialText = '']) {
    _root = _RopeNode.fromText(initialText);
  }

  Rope._fromRoot(this._root, this._selection);

  Rope get core => this;
  int get length => _root.charCount;
  int get lineCount => _root.newlineCount + 1;

  Rope copy() => Rope._fromRoot(_root.clone(), _selection);

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

  Rope concatImmutable(Rope other) {
    final result = copy();
    result.insert(length, other.getText());
    return result;
  }

  (Rope, Rope) splitImmutable(int position) {
    if (position < 0 || position > length) {
      throw RangeError('Invalid position: $position for length $length');
    }
    return (
      Rope._fromRoot(_root.range(0, position), _selection),
      Rope._fromRoot(_root.range(position, length), _selection),
    );
  }

  TextSelection get selection => TextSelection(
    baseOffset: _selection.baseOffset.toInt(),
    extentOffset: _selection.extentOffset.toInt(),
  );

  void setSelection(TextSelection value) {
    _selection = SelectionState(
      baseOffset: BigInt.from(value.baseOffset.clamp(0, length)),
      extentOffset: BigInt.from(value.extentOffset.clamp(0, length)),
    );
  }

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
    delete(safeStart, safeEnd);
    insert(safeStart, replacement);

    int mapOffset(int offset) {
      if (offset <= safeStart) return offset;
      if (offset >= safeEnd) {
        return (offset + replacement.runes.length - (safeEnd - safeStart))
            .clamp(0, length);
      }
      return (safeStart +
              (offset - safeStart).clamp(0, replacement.runes.length))
          .clamp(0, length);
    }

    final endOffset = safeStart + replacement.runes.length;
    _selection = SelectionState(
      baseOffset: BigInt.from(
        (preserveOldCursor ? mapOffset(oldBase) : endOffset).clamp(0, length),
      ),
      extentOffset: BigInt.from(
        (preserveOldCursor ? mapOffset(oldExtent) : endOffset).clamp(0, length),
      ),
    );
    return _selection;
  }

  String getText() => _root.text();

  String substring(int start, [int? end]) => slice(start, end ?? length);

  String slice(int start, int end) {
    final safeStart = start.clamp(0, length);
    final safeEnd = end.clamp(safeStart, length);
    return _root.slice(safeStart, safeEnd);
  }

  String charAt(int position) {
    if (position < 0 || position >= length) return '';
    return _root.charAt(position);
  }

  void insert(int position, String text) {
    if (text.isEmpty) return;
    final index = position.clamp(0, length);
    final runes = text.runes.toList();
    var offset = index;
    for (var start = 0; start < runes.length; start += _leafCapacity) {
      final chunk = String.fromCharCodes(runes.skip(start).take(_leafCapacity));
      final split = _root.insert(offset, chunk);
      if (split != null) {
        _root = _RopeNode.internal([_root, split]);
      }
      offset += chunk.runes.length;
    }
  }

  void delete(int start, int end) {
    final safeStart = start.clamp(0, length);
    final safeEnd = end.clamp(safeStart, length);
    if (safeStart == safeEnd) return;
    _root.remove(safeStart, safeEnd);
    if (_root is _RopeInternal && (_root as _RopeInternal).children.isEmpty) {
      _root = _RopeLeaf('');
    }
    while (_root is _RopeInternal &&
        (_root as _RopeInternal).children.length == 1) {
      _root = (_root as _RopeInternal).children.single;
    }
  }

  List<String> get cachedLines => cachedLinesRange(0, lineCount);

  List<String> cachedLinesRange(int startLine, int endLine) {
    final start = startLine.clamp(0, lineCount);
    final end = endLine.clamp(start, lineCount);
    return [for (var line = start; line < end; line++) getLineText(line)];
  }

  Iterable<String> get lines => cachedLines;

  String getLineText(int lineIndex) {
    final start = getLineStartOffset(lineIndex);
    var end = findLineEnd(start);
    if (end > start && charAt(end - 1) == '\r') end--;
    return slice(start, end);
  }

  int getLineAtOffset(int charOffset) {
    final offset = charOffset.clamp(0, length);
    return _root.newlinesBefore(offset);
  }

  int getLineStartOffset(int lineIndex) {
    final index = lineIndex.clamp(0, lineCount - 1);
    if (index == 0) return 0;
    return (_root.nthNewline(index - 1) + 1).clamp(0, length);
  }

  int findLineStart(int offset) => getLineStartOffset(getLineAtOffset(offset));

  int findLineEnd(int offset) {
    final start = offset.clamp(0, length);
    final newline = _root.nextNewline(start);
    return newline ?? length;
  }

  int lineLengthAt(int lineIndex) {
    final start = getLineStartOffset(lineIndex);
    final end = findLineEnd(start);
    final length = end - start;
    return length > 0 && charAt(end - 1) == '\r' ? length - 1 : length;
  }

  List<int> lineLengths() {
    final lengths = <int>[];
    var current = 0;
    var previousWasCarriageReturn = false;

    void consume(String chunk) {
      for (var i = 0; i < chunk.length; i++) {
        final codeUnit = chunk.codeUnitAt(i);
        if (codeUnit == 10) {
          lengths.add(previousWasCarriageReturn ? current - 1 : current);
          current = 0;
          previousWasCarriageReturn = false;
          continue;
        }
        current++;
        previousWasCarriageReturn = codeUnit == 13;
        if (codeUnit >= 0xd800 &&
            codeUnit <= 0xdbff &&
            i + 1 < chunk.length &&
            chunk.codeUnitAt(i + 1) >= 0xdc00 &&
            chunk.codeUnitAt(i + 1) <= 0xdfff) {
          i++;
        }
      }
    }

    _root.forEachLeaf(consume);
    lengths.add(previousWasCarriageReturn ? current - 1 : current);
    return lengths;
  }

  TextDirection get textDirection {
    var ltr = 0;
    var rtl = 0;
    _root.forEachChar((rune) {
      if ((rune >= 0x590 && rune <= 0x8ff) ||
          (rune >= 0xfb1d && rune <= 0xfdff)) {
        rtl++;
      } else if (String.fromCharCode(rune).trim().isNotEmpty) {
        ltr++;
      }
    });
    return rtl > ltr ? TextDirection.rtl : TextDirection.ltr;
  }

  bool get containsRtl => textDirection == TextDirection.rtl;
  bool get isRtl => containsRtl;
  bool get isLtr => !containsRtl;
  bool get isMixed => false;
  TextDirection get primaryDirection => textDirection;

  List<BiDiSegment> get bidiSegments => length == 0
      ? []
      : [
          BiDiSegment(
            start: BigInt.zero,
            end: BigInt.from(length),
            direction: textDirection,
          ),
        ];

  List<BiDiSegment> getBiDiSegmentsForLine(int lineIndex) =>
      getBiDiSegmentsInRange(
        getLineStartOffset(lineIndex),
        findLineEnd(getLineStartOffset(lineIndex)),
      );

  List<BiDiSegment> getBiDiSegmentsInRange(int start, int end) =>
      bidiSegments.where((segment) {
        return segment.end.toInt() > start && segment.start.toInt() < end;
      }).toList();

  List<(int start, int end)> getRtlSegments() => bidiSegments
      .where((segment) => segment.direction == TextDirection.rtl)
      .map((segment) => (segment.start.toInt(), segment.end.toInt()))
      .toList();

  String toStringWithBiDiControls() {
    final text = getText();
    if (!containsRtl) return text;
    return '${String.fromCharCode(0x202b)}$text'
        '${String.fromCharCode(0x202c)}';
  }
}

abstract class _RopeNode {
  _RopeNode();

  int charCount = 0;
  int newlineCount = 0;

  _RopeNode clone();
  String text();
  String slice(int start, int end);
  String charAt(int index);
  _RopeNode? insert(int index, String text);
  void remove(int start, int end);
  int newlinesBefore(int offset);
  int nthNewline(int index);
  int? nextNewline(int offset);
  void forEachChar(void Function(int) callback);
  void forEachLeaf(void Function(String) callback);

  factory _RopeNode.fromText(String text) {
    if (text.isEmpty) return _RopeLeaf('');
    final chunks = <_RopeNode>[];
    final runes = text.runes.toList();
    for (var i = 0; i < runes.length; i += Rope._leafCapacity) {
      chunks.add(
        _RopeLeaf(String.fromCharCodes(runes.skip(i).take(Rope._leafCapacity))),
      );
    }
    if (chunks.length == 1) return chunks.single;
    final roots = <_RopeNode>[];
    for (var i = 0; i < chunks.length; i += Rope._nodeCapacity) {
      roots.add(
        _RopeNode.internal(chunks.skip(i).take(Rope._nodeCapacity).toList()),
      );
    }
    while (roots.length > 1) {
      final next = <_RopeNode>[];
      for (var i = 0; i < roots.length; i += Rope._nodeCapacity) {
        next.add(
          _RopeNode.internal(roots.skip(i).take(Rope._nodeCapacity).toList()),
        );
      }
      roots
        ..clear()
        ..addAll(next);
    }
    return roots.single;
  }

  factory _RopeNode.internal(List<_RopeNode> children) =>
      _RopeInternal(children);

  _RopeNode range(int start, int end) {
    final result = _RopeNode.fromText(slice(start, end));
    return result;
  }
}

class _RopeLeaf extends _RopeNode {
  String value;

  _RopeLeaf(this.value) {
    _refresh();
  }

  void _refresh() {
    charCount = value.runes.length;
    newlineCount = '\n'.allMatches(value).length;
  }

  @override
  _RopeNode clone() => _RopeLeaf(value);

  @override
  String text() => value;

  @override
  String slice(int start, int end) {
    final startUnits = _codeUnitOffsetForRuneIndex(start);
    final endUnits = _codeUnitOffsetForRuneIndex(end);
    return value.substring(startUnits, endUnits);
  }

  @override
  String charAt(int index) {
    var runeIndex = 0;
    for (var codeUnitIndex = 0; codeUnitIndex < value.length; codeUnitIndex++) {
      final codeUnit = value.codeUnitAt(codeUnitIndex);
      if (runeIndex == index) {
        if (codeUnit >= 0xd800 &&
            codeUnit <= 0xdbff &&
            codeUnitIndex + 1 < value.length) {
          return value.substring(codeUnitIndex, codeUnitIndex + 2);
        }
        return value.substring(codeUnitIndex, codeUnitIndex + 1);
      }
      if (codeUnit >= 0xd800 &&
          codeUnit <= 0xdbff &&
          codeUnitIndex + 1 < value.length &&
          value.codeUnitAt(codeUnitIndex + 1) >= 0xdc00 &&
          value.codeUnitAt(codeUnitIndex + 1) <= 0xdfff) {
        codeUnitIndex++;
      }
      runeIndex++;
    }
    return '';
  }

  @override
  _RopeNode? insert(int index, String text) {
    final runes = value.runes.toList()..insertAll(index, text.runes);
    if (runes.length <= Rope._leafCapacity) {
      value = String.fromCharCodes(runes);
      _refresh();
      return null;
    }
    final midpoint = runes.length ~/ 2;
    value = String.fromCharCodes(runes.take(midpoint));
    _refresh();
    return _RopeLeaf(String.fromCharCodes(runes.skip(midpoint)));
  }

  @override
  void remove(int start, int end) {
    final runes = value.runes.toList()..removeRange(start, end);
    value = String.fromCharCodes(runes);
    _refresh();
  }

  @override
  int newlinesBefore(int offset) {
    final end = _codeUnitOffsetForRuneIndex(offset);
    var count = 0;
    for (var i = 0; i < end; i++) {
      if (value.codeUnitAt(i) == 10) count++;
    }
    return count;
  }

  @override
  int nthNewline(int index) {
    var seen = 0;
    var runeIndex = 0;
    for (var i = 0; i < value.length; i++) {
      if (value.codeUnitAt(i) == 10 && seen++ == index) {
        return runeIndex;
      }
      if (value.codeUnitAt(i) >= 0xd800 &&
          value.codeUnitAt(i) <= 0xdbff &&
          i + 1 < value.length &&
          value.codeUnitAt(i + 1) >= 0xdc00 &&
          value.codeUnitAt(i + 1) <= 0xdfff) {
        i++;
      }
      runeIndex++;
    }
    return charCount;
  }

  @override
  int? nextNewline(int offset) {
    var runeIndex = 0;
    for (var i = 0; i < value.length; i++) {
      final codeUnit = value.codeUnitAt(i);
      if (runeIndex >= offset && codeUnit == 10) return runeIndex;
      if (codeUnit >= 0xd800 &&
          codeUnit <= 0xdbff &&
          i + 1 < value.length &&
          value.codeUnitAt(i + 1) >= 0xdc00 &&
          value.codeUnitAt(i + 1) <= 0xdfff) {
        i++;
      }
      runeIndex++;
    }
    return null;
  }

  int _codeUnitOffsetForRuneIndex(int index) {
    if (index <= 0) return 0;
    var runeIndex = 0;
    for (var i = 0; i < value.length; i++, runeIndex++) {
      if (runeIndex == index) return i;
      final codeUnit = value.codeUnitAt(i);
      if (codeUnit >= 0xd800 &&
          codeUnit <= 0xdbff &&
          i + 1 < value.length &&
          value.codeUnitAt(i + 1) >= 0xdc00 &&
          value.codeUnitAt(i + 1) <= 0xdfff) {
        i++;
      }
    }
    return value.length;
  }

  @override
  void forEachChar(void Function(int) callback) {
    for (final rune in value.runes) {
      callback(rune);
    }
  }

  @override
  void forEachLeaf(void Function(String) callback) => callback(value);
}

class _RopeInternal extends _RopeNode {
  final List<_RopeNode> children;

  _RopeInternal(this.children) {
    _refresh();
  }

  void _refresh() {
    charCount = 0;
    newlineCount = 0;
    for (final child in children) {
      charCount += child.charCount;
      newlineCount += child.newlineCount;
    }
  }

  @override
  _RopeNode clone() =>
      _RopeInternal([for (final child in children) child.clone()]);

  @override
  String text() {
    final result = StringBuffer();
    result.writeAll(children.map((child) => child.text()));
    return result.toString();
  }

  @override
  String slice(int start, int end) {
    final result = StringBuffer();
    var cursor = 0;
    for (final child in children) {
      final childEnd = cursor + child.charCount;
      if (childEnd > start && cursor < end) {
        result.write(
          child.slice(
            (start - cursor).clamp(0, child.charCount),
            (end - cursor).clamp(0, child.charCount),
          ),
        );
      }
      cursor = childEnd;
      if (cursor >= end) break;
    }
    return result.toString();
  }

  @override
  String charAt(int index) {
    var offset = index;
    for (final child in children) {
      if (offset < child.charCount) return child.charAt(offset);
      offset -= child.charCount;
    }
    return '';
  }

  @override
  _RopeNode? insert(int index, String text) {
    var offset = index;
    var childIndex = children.length - 1;
    for (var i = 0; i < children.length; i++) {
      if (offset <= children[i].charCount || i == children.length - 1) {
        childIndex = i;
        break;
      }
      offset -= children[i].charCount;
    }
    final split = children[childIndex].insert(offset, text);
    if (split != null) children.insert(childIndex + 1, split);
    _refresh();
    if (children.length <= Rope._nodeCapacity) return null;
    final midpoint = children.length ~/ 2;
    final right = _RopeInternal(children.sublist(midpoint));
    children.removeRange(midpoint, children.length);
    _refresh();
    return right;
  }

  @override
  void remove(int start, int end) {
    for (var i = children.length - 1; i >= 0; i--) {
      final child = children[i];
      final childStart = cursorFor(i);
      final childEnd = childStart + child.charCount;
      if (childEnd > start && childStart < end) {
        child.remove(
          (start - childStart).clamp(0, child.charCount),
          (end - childStart).clamp(0, child.charCount),
        );
        if (child.charCount == 0) children.removeAt(i);
      }
    }
    _refresh();
  }

  int cursorFor(int index) {
    var result = 0;
    for (var i = 0; i < index; i++) {
      result += children[i].charCount;
    }
    return result;
  }

  @override
  int newlinesBefore(int offset) {
    var remaining = offset;
    var result = 0;
    for (final child in children) {
      if (remaining <= child.charCount) {
        return result + child.newlinesBefore(remaining);
      }
      remaining -= child.charCount;
      result += child.newlineCount;
    }
    return result;
  }

  @override
  int nthNewline(int index) {
    var remaining = index;
    var offset = 0;
    for (final child in children) {
      if (remaining < child.newlineCount) {
        return offset + child.nthNewline(remaining);
      }
      remaining -= child.newlineCount;
      offset += child.charCount;
    }
    return charCount;
  }

  @override
  int? nextNewline(int offset) {
    var cursor = 0;
    for (final child in children) {
      if (offset < cursor + child.charCount) {
        final result = child.nextNewline(offset > cursor ? offset - cursor : 0);
        if (result != null) return cursor + result;
      }
      cursor += child.charCount;
    }
    return null;
  }

  @override
  void forEachChar(void Function(int) callback) {
    for (final child in children) {
      child.forEachChar(callback);
    }
  }

  @override
  void forEachLeaf(void Function(String) callback) {
    for (final child in children) {
      child.forEachLeaf(callback);
    }
  }
}
