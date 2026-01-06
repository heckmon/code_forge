import 'dart:math';

/// Text direction for bidirectional text support
enum TextDirection {
  ltr, // Left-to-right (English, etc.)
  rtl, // Right-to-left (Arabic, Hebrew, etc.)
  mixed, // Contains both directions
}

/// Unicode BiDi character ranges and utilities
class BiDi {
  static const int _arabicStart = 0x0600;
  static const int _arabicEnd = 0x06FF;
  static const int _arabicSupplementStart = 0x0750;
  static const int _arabicSupplementEnd = 0x077F;
  static const int _arabicExtendedAStart = 0x08A0;
  static const int _arabicExtendedAEnd = 0x08FF;
  static const int _hebrewStart = 0x0590;
  static const int _hebrewEnd = 0x05FF;
  static const int _syriacStart = 0x0700;
  static const int _syriacEnd = 0x074F;
  static const int _thaanaStart = 0x0780;
  static const int _thaanaEnd = 0x07BF;
  static const int _nkoStart = 0x07C0;
  static const int _nkoEnd = 0x07FF;

  // BiDi control characters
  static const int lrm = 0x200E; // Left-to-Right Mark
  static const int rlm = 0x200F; // Right-to-Left Mark
  static const int lre = 0x202A; // Left-to-Right Embedding
  static const int rle = 0x202B; // Right-to-Left Embedding
  static const int pdf = 0x202C; // Pop Directional Formatting
  static const int lro = 0x202D; // Left-to-Right Override
  static const int rlo = 0x202E; // Right-to-Left Override
  static const int lri = 0x2066; // Left-to-Right Isolate
  static const int rli = 0x2067; // Right-to-Left Isolate
  static const int fsi = 0x2068; // First Strong Isolate
  static const int pdi = 0x2069; // Pop Directional Isolate

  /// Check if a code unit is an RTL character
  static bool isRtlChar(int codeUnit) {
    return (codeUnit >= _arabicStart && codeUnit <= _arabicEnd) ||
        (codeUnit >= _arabicSupplementStart &&
            codeUnit <= _arabicSupplementEnd) ||
        (codeUnit >= _arabicExtendedAStart &&
            codeUnit <= _arabicExtendedAEnd) ||
        (codeUnit >= _hebrewStart && codeUnit <= _hebrewEnd) ||
        (codeUnit >= _syriacStart && codeUnit <= _syriacEnd) ||
        (codeUnit >= _thaanaStart && codeUnit <= _thaanaEnd) ||
        (codeUnit >= _nkoStart && codeUnit <= _nkoEnd) ||
        codeUnit == rlm ||
        codeUnit == rle ||
        codeUnit == rlo ||
        codeUnit == rli;
  }

  /// Check if a code unit is an LTR character (strong)
  static bool isLtrChar(int codeUnit) {
    // Latin, Greek, Cyrillic, and other LTR scripts
    return (codeUnit >= 0x0041 && codeUnit <= 0x005A) || // A-Z
        (codeUnit >= 0x0061 && codeUnit <= 0x007A) || // a-z
        (codeUnit >= 0x00C0 && codeUnit <= 0x00FF) || // Latin Extended
        (codeUnit >= 0x0100 && codeUnit <= 0x017F) || // Latin Extended-A
        (codeUnit >= 0x0180 && codeUnit <= 0x024F) || // Latin Extended-B
        (codeUnit >= 0x0370 && codeUnit <= 0x03FF) || // Greek
        (codeUnit >= 0x0400 && codeUnit <= 0x04FF) || // Cyrillic
        codeUnit == lrm ||
        codeUnit == lre ||
        codeUnit == lro ||
        codeUnit == lri;
  }

  /// Check if a code unit is neutral (numbers, punctuation, spaces)
  static bool isNeutral(int codeUnit) {
    return !isRtlChar(codeUnit) && !isLtrChar(codeUnit);
  }
}

/// Represents a segment of text with a specific direction
class BiDiSegment {
  final int start;
  final int end;
  final TextDirection direction;

  const BiDiSegment(this.start, this.end, this.direction);

  int get length => end - start;

  @override
  String toString() => 'BiDiSegment($start-$end, $direction)';
}

class Rope {
  static const int _leafSize = 512;
  _RopeNode? _root;
  int _length = 0;

  List<String>? _lineCache;

  TextDirection? _cachedDirection;
  List<BiDiSegment>? _cachedBiDiSegments;

  Rope([String initialText = '']) {
    if (initialText.isEmpty) {
      _root = null;
      _length = 0;
    } else {
      _root = _buildBalanced(initialText, 0, initialText.length);
      _length = initialText.length;
    }
  }

  /// Private constructor for immutable operations
  Rope._fromNode(_RopeNode? root, int length) : _root = root, _length = length;

  int get length => _length;

  /// Creates a new Rope with text inserted at position (immutable)
  Rope insertImmutable(int position, String text) {
    if (position < 0 || position > _length) {
      throw RangeError('Invalid position: $position for length $_length');
    }
    if (text.isEmpty) return Rope._fromNode(_root, _length);

    final pair = _split(_root, position);
    final mid = _buildBalanced(text, 0, text.length);
    final newRoot = _concat(_concat(pair.left, mid), pair.right);
    return Rope._fromNode(newRoot, _length + text.length);
  }

  /// Creates a new Rope with text deleted between start and end (immutable)
  Rope deleteImmutable(int start, int end) {
    if (start < 0 || end < start || end > _length) {
      throw RangeError('Invalid range: [$start, $end) for length $_length');
    }
    if (start == end) return Rope._fromNode(_root, _length);

    final first = _split(_root, start);
    final second = _split(first.right, end - start);
    final newRoot = _concat(first.left, second.right);
    return Rope._fromNode(newRoot, _length - (end - start));
  }

  /// Creates a new Rope by concatenating another Rope (immutable)
  Rope concatImmutable(Rope other) {
    if (other._root == null) return Rope._fromNode(_root, _length);
    if (_root == null) return Rope._fromNode(other._root, other._length);

    final newRoot = _concat(_root, other._root);
    return Rope._fromNode(newRoot, _length + other._length);
  }

  /// Splits this rope at position, returning two new Ropes (immutable)
  (Rope, Rope) splitImmutable(int position) {
    if (position < 0 || position > _length) {
      throw RangeError('Invalid position: $position for length $_length');
    }
    if (position == 0) {
      return (Rope._fromNode(null, 0), Rope._fromNode(_root, _length));
    }
    if (position == _length) {
      return (Rope._fromNode(_root, _length), Rope._fromNode(null, 0));
    }

    final pair = _split(_root, position);
    final leftLen = pair.left?.length ?? 0;
    final rightLen = pair.right?.length ?? 0;
    return (
      Rope._fromNode(pair.left, leftLen),
      Rope._fromNode(pair.right, rightLen),
    );
  }

  /// Creates a deep copy of this Rope
  Rope copy() => Rope._fromNode(_root, _length);

  /// Returns the overall text direction of this rope
  TextDirection get textDirection {
    if (_cachedDirection != null) return _cachedDirection!;
    _cachedDirection = _computeTextDirection();
    return _cachedDirection!;
  }

  /// Returns true if this rope contains any RTL characters
  bool get containsRtl => textDirection != TextDirection.ltr;

  /// Returns true if this rope is primarily RTL
  bool get isRtl => textDirection == TextDirection.rtl;

  /// Returns true if this rope is primarily LTR
  bool get isLtr => textDirection == TextDirection.ltr;

  /// Returns true if this rope contains both RTL and LTR characters
  bool get isMixed => textDirection == TextDirection.mixed;

  /// Get BiDi segments for the entire rope
  List<BiDiSegment> get bidiSegments {
    if (_cachedBiDiSegments != null) return _cachedBiDiSegments!;
    _cachedBiDiSegments = _computeBiDiSegments();
    return _cachedBiDiSegments!;
  }

  /// Get BiDi segments for a specific line
  List<BiDiSegment> getBiDiSegmentsForLine(int lineIndex) {
    final lineStart = getLineStartOffset(lineIndex);
    final lineEnd = findLineEnd(lineStart);
    return getBiDiSegmentsInRange(lineStart, lineEnd);
  }

  /// Get BiDi segments within a character range
  List<BiDiSegment> getBiDiSegmentsInRange(int start, int end) {
    if (start >= end || _root == null) return [];

    final text = substring(start, end);
    final segments = <BiDiSegment>[];

    if (text.isEmpty) return segments;

    TextDirection? currentDir;
    int segmentStart = 0;

    for (int i = 0; i < text.length; i++) {
      final codeUnit = text.codeUnitAt(i);
      TextDirection charDir;

      if (BiDi.isRtlChar(codeUnit)) {
        charDir = TextDirection.rtl;
      } else if (BiDi.isLtrChar(codeUnit)) {
        charDir = TextDirection.ltr;
      } else {
        continue;
      }

      if (currentDir == null) {
        currentDir = charDir;
        segmentStart = i;
      } else if (charDir != currentDir) {
        segments.add(BiDiSegment(start + segmentStart, start + i, currentDir));
        currentDir = charDir;
        segmentStart = i;
      }
    }

    if (currentDir != null) {
      segments.add(
        BiDiSegment(start + segmentStart, start + text.length, currentDir),
      );
    }

    return segments;
  }

  /// Get only RTL segments (useful for rendering)
  List<(int start, int end)> getRtlSegments() {
    return bidiSegments
        .where((s) => s.direction == TextDirection.rtl)
        .map((s) => (s.start, s.end))
        .toList();
  }

  /// Wrap text with appropriate BiDi control characters for rendering
  String toStringWithBiDiControls() {
    if (_root == null) return '';
    final text = getText();

    if (!containsRtl) return text;

    if (isRtl) {
      return String.fromCharCode(BiDi.rle) +
          text +
          String.fromCharCode(BiDi.pdf);
    } else {
      return String.fromCharCode(BiDi.lre) +
          text +
          String.fromCharCode(BiDi.pdf);
    }
  }

  /// Returns the primary direction based on character count
  /// For mixed text, returns the direction with more characters
  TextDirection get primaryDirection {
    if (_root == null) return TextDirection.ltr;

    int rtlCount = 0;
    int ltrCount = 0;

    for (final chunk in _root!.chunks()) {
      for (int i = 0; i < chunk.length; i++) {
        final codeUnit = chunk.codeUnitAt(i);
        if (BiDi.isRtlChar(codeUnit)) {
          rtlCount++;
        } else if (BiDi.isLtrChar(codeUnit)) {
          ltrCount++;
        }
      }
    }

    if (rtlCount == 0 && ltrCount == 0) return TextDirection.ltr;
    return rtlCount > ltrCount ? TextDirection.rtl : TextDirection.ltr;
  }

  TextDirection _computeTextDirection() {
    if (_root == null) return TextDirection.ltr;

    bool hasRtl = false;
    bool hasLtr = false;

    for (final chunk in _root!.chunks()) {
      for (int i = 0; i < chunk.length; i++) {
        final codeUnit = chunk.codeUnitAt(i);
        if (BiDi.isRtlChar(codeUnit)) {
          hasRtl = true;
        } else if (BiDi.isLtrChar(codeUnit)) {
          hasLtr = true;
        }

        if (hasRtl && hasLtr) {
          return TextDirection.mixed;
        }
      }
    }

    if (!hasRtl && !hasLtr) return TextDirection.ltr;
    if (!hasRtl) return TextDirection.ltr;
    return TextDirection.rtl;
  }

  List<BiDiSegment> _computeBiDiSegments() {
    if (_root == null) return [];
    return getBiDiSegmentsInRange(0, _length);
  }

  void _invalidateBiDiCache() {
    _cachedDirection = null;
    _cachedBiDiSegments = null;
  }

  _RopeNode? _buildBalanced(String s, int start, int end) {
    final len = end - start;
    if (len <= 0) return null;
    if (len <= _leafSize) return _RopeLeaf(s.substring(start, end));

    final mid = start + len ~/ 2;
    final left = _buildBalanced(s, start, mid);
    final right = _buildBalanced(s, mid, end);
    return _concat(left, right);
  }

  String getText() {
    if (_root == null) return '';
    final buffer = StringBuffer();
    for (final chunk in _root!.chunks()) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  String substring(int start, [int? end]) {
    end ??= _length;
    if (start < 0 || end < start || end > _length) {
      throw RangeError('Invalid range: [$start, $end) for length $_length');
    }
    if (start == end) return '';
    if (_root == null) return '';

    final buffer = StringBuffer();
    for (final chunk in _root!.chunksInRange(start, end)) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  String charAt(int position) {
    if (position < 0 || position >= _length) {
      throw RangeError('Invalid position: $position for length $_length');
    }
    if (_root == null) throw StateError('Empty rope');
    return _root!.charAt(position);
  }

  /// Mutable insert - modifies this rope in place
  /// For immutable version, use [insertImmutable]
  void insert(int position, String text) {
    if (position < 0 || position > _length) {
      throw RangeError('Invalid position: $position for length $_length');
    }
    if (text.isEmpty) return;

    _lineCache = null;
    _invalidateBiDiCache();

    if (text.length == 1 && _root != null) {
      final inserted = _tryInsertInLeaf(_root!, position, text);
      if (inserted != null) {
        _root = inserted;
        _length += 1;
        return;
      }
    }

    final pair = _split(_root, position);
    final mid = _buildBalanced(text, 0, text.length);
    _root = _concat(_concat(pair.left, mid), pair.right);
    _length += text.length;
  }

  _RopeNode? _tryInsertInLeaf(_RopeNode node, int position, String char) {
    if (node is _RopeLeaf) {
      if (node.text.length < _leafSize) {
        final newText =
            node.text.substring(0, position) +
            char +
            node.text.substring(position);
        return _RopeLeaf(newText);
      }
      return null;
    } else if (node is _RopeConcat) {
      final leftLen = node.left.length;
      if (position <= leftLen) {
        final newLeft = _tryInsertInLeaf(node.left, position, char);
        if (newLeft != null) {
          return _rawConcatNoMerge(newLeft, node.right);
        }
      } else {
        final newRight = _tryInsertInLeaf(node.right, position - leftLen, char);
        if (newRight != null) {
          return _rawConcatNoMerge(node.left, newRight);
        }
      }
    }
    return null;
  }

  /// Mutable delete - modifies this rope in place
  /// For immutable version, use [deleteImmutable]
  void delete(int start, int end) {
    if (start < 0 || end < start || end > _length) {
      throw RangeError('Invalid range: [$start, $end) for length $_length');
    }
    if (start == end) return;

    _lineCache = null;
    _invalidateBiDiCache();

    if (end - start == 1 && _root != null) {
      final deleted = _tryDeleteInLeaf(_root!, start);
      if (deleted != null) {
        _root = deleted.length == 0 ? null : deleted;
        _length -= 1;
        return;
      }
    }

    final first = _split(_root, start);
    final second = _split(first.right, end - start);
    _root = _concat(first.left, second.right);
    _length -= (end - start);
  }

  _RopeNode? _tryDeleteInLeaf(_RopeNode node, int position) {
    if (node is _RopeLeaf) {
      if (position >= 0 && position < node.text.length) {
        final newText =
            node.text.substring(0, position) +
            node.text.substring(position + 1);
        return newText.isEmpty ? _RopeLeaf('') : _RopeLeaf(newText);
      }
      return null;
    } else if (node is _RopeConcat) {
      final leftLen = node.left.length;
      if (position < leftLen) {
        final newLeft = _tryDeleteInLeaf(node.left, position);
        if (newLeft != null) {
          if (newLeft is _RopeLeaf && newLeft.text.isEmpty) {
            return node.right;
          }
          return _rawConcatNoMerge(newLeft, node.right);
        }
      } else {
        final newRight = _tryDeleteInLeaf(node.right, position - leftLen);
        if (newRight != null) {
          if (newRight is _RopeLeaf && newRight.text.isEmpty) {
            return node.left;
          }
          return _rawConcatNoMerge(node.left, newRight);
        }
      }
    }
    return null;
  }

  Iterable<String> chunks() sync* {
    if (_root == null) return;
    yield* _root!.chunks();
  }

  List<String> get cachedLines {
    _lineCache ??= lines.toList();
    return _lineCache!;
  }

  Iterable<String> get lines sync* {
    final buffer = StringBuffer();

    for (final chunk in chunks()) {
      for (int i = 0; i < chunk.length; i++) {
        final char = chunk[i];
        if (char == '\n') {
          yield buffer.toString();
          buffer.clear();
        } else {
          buffer.write(char);
        }
      }
    }

    if (buffer.isNotEmpty || _length == 0) {
      yield buffer.toString();
    }
  }

  int get lineCount {
    if (_root == null) return 1;
    return _root!.newlines + 1;
  }

  int findLineStart(int offset) {
    if (offset <= 0) return 0;
    if (_root == null) return 0;
    if (offset > _length) offset = _length;

    final pos = _lastNewlineBefore(_root!, offset);
    return pos + 1;
  }

  int findLineEnd(int offset) {
    if (offset >= _length) return _length;
    if (_root == null) return 0;
    if (offset < 0) offset = 0;

    final nextNewline = _firstNewlineAtOrAfter(_root!, offset);
    return nextNewline == -1 ? _length : nextNewline;
  }

  String getLineText(int lineIndex) {
    if (lineIndex < 0) return '';
    if (_root == null) {
      return lineIndex == 0 ? '' : '';
    }
    final start = _lineStartByIndex(lineIndex);
    if (start == -1) return '';
    final end = findLineEnd(start);
    return substring(start, end);
  }

  int getLineStartOffset(int lineIndex) {
    final start = _lineStartByIndex(lineIndex);
    return start == -1 ? 0 : start;
  }

  int getLineAtOffset(int charOffset) {
    if (charOffset <= 0) return 0;
    if (_root == null) return 0;
    if (charOffset >= _length) return max(0, lineCount - 1);
    return _getLineAtOffset(_root!, charOffset, 0);
  }

  _SplitPair _split(_RopeNode? node, int index) {
    if (node == null) return _SplitPair(null, null);

    if (node is _RopeLeaf) {
      final text = node.text;
      final clampedIndex = index.clamp(0, text.length);
      final leftText = text.substring(0, clampedIndex);
      final rightText = text.substring(clampedIndex);
      return _SplitPair(
        leftText.isEmpty ? null : _RopeLeaf(leftText),
        rightText.isEmpty ? null : _RopeLeaf(rightText),
      );
    }

    if (node is _RopeConcat) {
      final leftLen = node.left.length;

      if (index <= 0) {
        return _SplitPair(null, node);
      } else if (index >= node.length) {
        return _SplitPair(node, null);
      } else if (index < leftLen) {
        final leftSplit = _split(node.left, index);
        return _SplitPair(leftSplit.left, _concat(leftSplit.right, node.right));
      } else if (index == leftLen) {
        return _SplitPair(node.left, node.right);
      } else {
        final rightSplit = _split(node.right, index - leftLen);
        return _SplitPair(
          _concat(node.left, rightSplit.left),
          rightSplit.right,
        );
      }
    }

    throw StateError('Unknown node type');
  }

  _RopeNode? _concat(_RopeNode? a, _RopeNode? b) {
    if (a == null) return b;
    if (b == null) return a;

    if (a is _RopeLeaf &&
        b is _RopeLeaf &&
        a.text.length + b.text.length <= _leafSize) {
      return _RopeLeaf(a.text + b.text);
    }

    final node = _RopeConcat(a, b);
    return _balance(node);
  }

  _RopeNode _rawConcatNoMerge(_RopeNode a, _RopeNode b) {
    return _RopeConcat(a, b);
  }

  _RopeNode _balance(_RopeNode node) {
    if (node is! _RopeConcat) return node;

    final n = node;
    final balance = n.left.height - n.right.height;

    if (balance > 1) {
      if (n.left is _RopeConcat) {
        final leftNode = n.left as _RopeConcat;
        if (leftNode.left.height < leftNode.right.height) {
          final newLeft = _rotateLeft(leftNode);
          final combined = _rawConcatNoMerge(newLeft, n.right);
          return _rotateRight(combined as _RopeConcat);
        }
      }
      return _rotateRight(n);
    } else if (balance < -1) {
      if (n.right is _RopeConcat) {
        final rightNode = n.right as _RopeConcat;
        if (rightNode.left.height > rightNode.right.height) {
          final newRight = _rotateRight(rightNode);
          final combined = _rawConcatNoMerge(n.left, newRight);
          return _rotateLeft(combined as _RopeConcat);
        }
      }
      return _rotateLeft(n);
    }

    return n;
  }

  _RopeNode _rotateRight(_RopeConcat y) {
    if (y.left is! _RopeConcat) return y;

    final x = y.left as _RopeConcat;
    final t1 = x.left;
    final t2 = x.right;
    final t3 = y.right;

    final newY = _rawConcatNoMerge(t2, t3);
    return _rawConcatNoMerge(t1, newY);
  }

  _RopeNode _rotateLeft(_RopeConcat x) {
    if (x.right is! _RopeConcat) return x;

    final y = x.right as _RopeConcat;
    final t1 = x.left;
    final t2 = y.left;
    final t3 = y.right;

    final newX = _rawConcatNoMerge(t1, t2);
    return _rawConcatNoMerge(newX, t3);
  }

  int _getLineAtOffset(_RopeNode node, int offset, int baseLine) {
    if (node is _RopeLeaf) {
      int pos = 0;
      int line = baseLine;
      final text = node.text;
      for (int i = 0; i < text.length; i++) {
        if (pos >= offset) break;
        if (text.codeUnitAt(i) == 10) {
          // '\n'
          line++;
        }
        pos++;
      }
      return line;
    } else if (node is _RopeConcat) {
      final left = node.left;
      if (offset < left.length) {
        return _getLineAtOffset(left, offset, baseLine);
      } else {
        return _getLineAtOffset(
          node.right,
          offset - left.length,
          baseLine + left.newlines,
        );
      }
    } else {
      throw StateError('Unknown node type');
    }
  }

  int _lastNewlineBefore(_RopeNode node, int offset) {
    if (node is _RopeLeaf) {
      final text = node.text;
      final limit = offset.clamp(0, text.length);
      for (int i = limit - 1; i >= 0; i--) {
        if (text.codeUnitAt(i) == 10) return i;
      }
      return -1;
    } else if (node is _RopeConcat) {
      final left = node.left;
      final right = node.right;
      if (offset <= left.length) {
        return _lastNewlineBefore(left, offset);
      } else {
        final rightResult = _lastNewlineBefore(right, offset - left.length);
        if (rightResult != -1) {
          return left.length + rightResult;
        } else {
          return _lastNewlineBefore(left, left.length);
        }
      }
    } else {
      throw StateError('Unknown node type');
    }
  }

  int _firstNewlineAtOrAfter(_RopeNode node, int offset) {
    if (node is _RopeLeaf) {
      final text = node.text;
      final start = offset.clamp(0, text.length);
      for (int i = start; i < text.length; i++) {
        if (text.codeUnitAt(i) == 10) return i;
      }
      return -1;
    } else if (node is _RopeConcat) {
      final left = node.left;
      final right = node.right;
      if (offset < left.length) {
        final leftResult = _firstNewlineAtOrAfter(left, offset);
        if (leftResult != -1) return leftResult;
        final rightResult = _firstNewlineAtOrAfter(right, 0);
        if (rightResult != -1) return left.length + rightResult;
        return -1;
      } else {
        final rightResult = _firstNewlineAtOrAfter(right, offset - left.length);
        if (rightResult != -1) return left.length + rightResult;
        return -1;
      }
    } else {
      throw StateError('Unknown node type');
    }
  }

  int _lineStartByIndex(int lineIndex) {
    if (_root == null) return lineIndex == 0 ? 0 : -1;
    if (lineIndex < 0) return -1;
    if (lineIndex == 0) return 0;
    if (lineIndex > _root!.newlines) return -1; // out of range

    final newlinePos = _findNthNewline(_root!, lineIndex - 1);
    return newlinePos == -1 ? 0 : (newlinePos + 1);
  }

  int _findNthNewline(_RopeNode node, int k) {
    if (k < 0) return -1;
    if (node is _RopeLeaf) {
      final text = node.text;
      int count = 0;
      for (int i = 0; i < text.length; i++) {
        if (text.codeUnitAt(i) == 10) {
          if (count == k) return i;
          count++;
        }
      }
      return -1;
    } else if (node is _RopeConcat) {
      final left = node.left;
      final right = node.right;
      if (k < left.newlines) {
        return _findNthNewline(left, k);
      } else {
        final rightPos = _findNthNewline(right, k - left.newlines);
        if (rightPos == -1) return -1;
        return left.length + rightPos;
      }
    } else {
      throw StateError('Unknown node type');
    }
  }
}

class _SplitPair {
  final _RopeNode? left;
  final _RopeNode? right;
  _SplitPair(this.left, this.right);
}

abstract class _RopeNode {
  int get length;
  int get height;
  int get newlines;

  String charAt(int index);
  Iterable<String> chunks();
  Iterable<String> chunksInRange(int start, int end);
}

class _RopeLeaf extends _RopeNode {
  final String text;
  final int _newlines;

  _RopeLeaf(this.text) : _newlines = _countNewlines(text);

  static int _countNewlines(String s) {
    int c = 0;
    for (int i = 0; i < s.length; i++) {
      if (s.codeUnitAt(i) == 10) c++;
    }
    return c;
  }

  @override
  int get length => text.length;

  @override
  int get height => 1;

  @override
  int get newlines => _newlines;

  @override
  String charAt(int index) => text[index];

  @override
  Iterable<String> chunks() sync* {
    if (text.isNotEmpty) yield text;
  }

  @override
  Iterable<String> chunksInRange(int start, int end) sync* {
    final s = start.clamp(0, text.length);
    final e = end.clamp(0, text.length);
    if (s < e) yield text.substring(s, e);
  }
}

class _RopeConcat extends _RopeNode {
  final _RopeNode left;
  final _RopeNode right;
  final int _length;
  final int _height;
  final int _newlines;

  _RopeConcat(this.left, this.right)
    : _length = left.length + right.length,
      _height = 1 + max(left.height, right.height),
      _newlines = left.newlines + right.newlines;

  @override
  int get length => _length;

  @override
  int get height => _height;

  @override
  int get newlines => _newlines;

  @override
  String charAt(int index) {
    if (index < left.length) {
      return left.charAt(index);
    }
    return right.charAt(index - left.length);
  }

  @override
  Iterable<String> chunks() sync* {
    yield* left.chunks();
    yield* right.chunks();
  }

  @override
  Iterable<String> chunksInRange(int start, int end) sync* {
    if (start >= end) return;

    final leftLen = left.length;

    if (start < leftLen) {
      final leftEnd = end <= leftLen ? end : leftLen;
      yield* left.chunksInRange(start, leftEnd);
    }

    if (end > leftLen) {
      final rightStart = start <= leftLen ? 0 : start - leftLen;
      final rightEnd = end - leftLen;
      yield* right.chunksInRange(rightStart, rightEnd);
    }
  }
}
