import 'dart:async';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/services.dart';
import 'rope.dart';

class CodeForgeController implements DeltaTextInputClient {
  static const _flushDelay = Duration(milliseconds: 300);
  final List<VoidCallback> _listeners = [];
  VoidCallback? manualAiCompletion;
  Rope _rope = Rope('');
  TextSelection _selection = const TextSelection.collapsed(offset: 0);
  TextInputConnection? connection;
  Timer? _flushTimer;
  TextRange? dirtyRegion;
  List<FoldRange> foldings = [];
  String? _cachedText, _bufferLineText;
  bool _bufferDirty = false, bufferNeedsRepaint = false, selectionOnly = false;
  int _bufferLineRopeStart = 0, _bufferLineOriginalLength = 0;
  int _cachedTextVersion = -1, _currentVersion = 0;
  int? dirtyLine, _bufferLineIndex;
  bool readOnly = false;
  bool lineStructureChanged = false;
  String? _lastSentText;
  TextSelection? _lastSentSelection;

  String get text {
    if (_cachedText == null || _cachedTextVersion != _currentVersion) {
      if (_bufferLineIndex != null && _bufferDirty) {
        final ropeText = _rope.getText();
        final before = ropeText.substring(0, _bufferLineRopeStart);
        final after = ropeText.substring(
          _bufferLineRopeStart + _bufferLineOriginalLength,
        );
        _cachedText = before + _bufferLineText! + after;
      } else {
        _cachedText = _rope.getText();
      }
      _cachedTextVersion = _currentVersion;
    }
    return _cachedText!;
  }

  int get length {
    if (_bufferLineIndex != null && _bufferDirty) {
      return _rope.length +
          (_bufferLineText!.length - _bufferLineOriginalLength);
    }
    return _rope.length;
  }

  TextSelection get selection => _selection;
  List<String> get lines => _rope.cachedLines;

  int get lineCount {
    return _rope.lineCount;
  }

  String get visibleText {
    if (foldings.isEmpty) return text;
    final visLines = List<String>.from(lines);
    for (final fold in foldings.reversed) {
      if (!fold.isFolded) continue;
      final start = fold.startIndex + 1;
      final end = fold.endIndex + 1;
      final safeStart = start.clamp(0, visLines.length);
      final safeEnd = end.clamp(safeStart, visLines.length);
      if (safeEnd > safeStart) {
        visLines.removeRange(safeStart, safeEnd);
      }
    }
    return visLines.join('\n');
  }

  String getLineText(int lineIndex) {
    if (_bufferLineIndex != null &&
        lineIndex == _bufferLineIndex &&
        _bufferDirty) {
      return _bufferLineText!;
    }
    return _rope.getLineText(lineIndex);
  }

  int getLineAtOffset(int charOffset) {
    if (_bufferLineIndex != null && _bufferDirty) {
      final bufferStart = _bufferLineRopeStart;
      final bufferEnd = bufferStart + _bufferLineText!.length;
      if (charOffset >= bufferStart && charOffset <= bufferEnd) {
        return _bufferLineIndex!;
      } else if (charOffset > bufferEnd) {
        final delta = _bufferLineText!.length - _bufferLineOriginalLength;
        return _rope.getLineAtOffset(charOffset - delta);
      }
    }
    return _rope.getLineAtOffset(charOffset);
  }

  int getLineStartOffset(int lineIndex) {
    if (_bufferLineIndex != null &&
        lineIndex == _bufferLineIndex &&
        _bufferDirty) {
      return _bufferLineRopeStart;
    }
    if (_bufferLineIndex != null &&
        lineIndex > _bufferLineIndex! &&
        _bufferDirty) {
      final delta = _bufferLineText!.length - _bufferLineOriginalLength;
      return _rope.getLineStartOffset(lineIndex) + delta;
    }
    return _rope.getLineStartOffset(lineIndex);
  }

  int findLineStart(int offset) => _rope.findLineStart(offset);
  int findLineEnd(int offset) => _rope.findLineEnd(offset);

  set text(String newText) {
    _rope = Rope(newText);
    _currentVersion++;
    _selection = TextSelection.collapsed(offset: newText.length);
    dirtyRegion = TextRange(start: 0, end: newText.length);
    notifyListeners();
  }

  set selection(TextSelection newSelection) {
    if (_selection == newSelection) return;

    _flushBuffer();

    _selection = newSelection;
    selectionOnly = true;

    if (connection != null && connection!.attached) {
      _lastSentText = text;
      _lastSentSelection = newSelection;
      connection!.setEditingState(
        TextEditingValue(text: _lastSentText!, selection: newSelection),
      );
    }

    notifyListeners();
  }

  /// Update selection and sync to text input connection for keyboard navigation.
  /// This flushes any pending buffer first to ensure IME state is consistent.
  void setSelectionSilently(TextSelection newSelection) {
    if (_selection == newSelection) return;

    _flushBuffer();

    final textLength = text.length;
    final clampedBase = newSelection.baseOffset.clamp(0, textLength);
    final clampedExtent = newSelection.extentOffset.clamp(0, textLength);
    newSelection = newSelection.copyWith(
      baseOffset: clampedBase,
      extentOffset: clampedExtent,
    );

    _selection = newSelection;
    selectionOnly = true;

    if (connection != null && connection!.attached) {
      _lastSentText = text;
      _lastSentSelection = newSelection;
      connection!.setEditingState(
        TextEditingValue(text: _lastSentText!, selection: newSelection),
      );
    }

    notifyListeners();
  }

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    if(readOnly) return;
    for (final delta in textEditingDeltas) {
      if (delta is TextEditingDeltaNonTextUpdate) {
        if (_lastSentSelection == null ||
            delta.selection != _lastSentSelection) {
          _selection = delta.selection;
        }
        _lastSentSelection = null;
        _lastSentText = null;
        continue;
      }

      _lastSentSelection = null;
      _lastSentText = null;

      if (delta is TextEditingDeltaInsertion) {
        _handleInsertion(
          delta.insertionOffset,
          delta.textInserted,
          delta.selection,
        );
      } else if (delta is TextEditingDeltaDeletion) {
        _handleDeletion(delta.deletedRange, delta.selection);
      } else if (delta is TextEditingDeltaReplacement) {
        _handleReplacement(
          delta.replacedRange,
          delta.replacementText,
          delta.selection,
        );
      }
    }
    notifyListeners();
  }

  void _handleInsertion(
    int offset,
    String insertedText,
    TextSelection newSelection,
  ) {
    final currentLength = length;
    if (offset < 0 || offset > currentLength) {
      return;
    }

    String actualInsertedText = insertedText;
    TextSelection actualSelection = newSelection;
    
    if (insertedText.length == 1) {
      final char = insertedText[0];
      const pairs = {'(': ')', '{': '}', '[': ']', '"': '"', "'": "'"};
      final openers = pairs.keys.toSet();
      final closers = pairs.values.toSet();
      
      if (openers.contains(char)) {
        final closing = pairs[char]!;
        actualInsertedText = '$char$closing';
        actualSelection = TextSelection.collapsed(offset: offset + 1);
      }
      else if (closers.contains(char)) {
        final currentText = text;
        if (offset < currentText.length && currentText[offset] == char) {
          _selection = TextSelection.collapsed(offset: offset + 1);
          notifyListeners();
          return;
        }
      }
    }
    
    if (actualInsertedText.contains('\n')) {
      final currentText = text;
      final textBeforeCursor = currentText.substring(0, offset);
      final textAfterCursor = currentText.substring(offset);
      final lines = textBeforeCursor.split('\n');

      if (lines.isNotEmpty) {
        final prevLine = lines[lines.length - 1];
        final indentMatch = RegExp(r'^\s*').firstMatch(prevLine);
        final prevIndent = indentMatch?.group(0) ?? '';
        final shouldIndent = RegExp(r'[:{[(]\s*$').hasMatch(prevLine);
        final extraIndent = shouldIndent ? '  ' : '';
        final indent = prevIndent + extraIndent;
        final openToClose = {'{': '}', '(': ')', '[': ']'};
        final trimmedPrev = prevLine.trimRight();
        final lastChar = trimmedPrev.isNotEmpty ? trimmedPrev[trimmedPrev.length - 1] : null;
        final trimmedNext = textAfterCursor.trimLeft();
        final nextChar = trimmedNext.isNotEmpty ? trimmedNext[0] : null;
        final isBracketOpen = openToClose.containsKey(lastChar);
        final isNextClosing = isBracketOpen && openToClose[lastChar] == nextChar;
        
        if (isBracketOpen && isNextClosing) {
          actualInsertedText = '\n$indent\n$prevIndent';
          actualSelection = TextSelection.collapsed(offset: offset + 1 + indent.length);
        } else {
          actualInsertedText = '\n$indent';
          actualSelection = TextSelection.collapsed(offset: offset + actualInsertedText.length);
        }
      }
      
      _flushBuffer();
      _rope.insert(offset, actualInsertedText);
      _currentVersion++;
      _selection = actualSelection;
      dirtyLine = _rope.getLineAtOffset(offset);
      lineStructureChanged = true;
      dirtyRegion = TextRange(start: offset, end: offset + actualInsertedText.length);
      
      if (connection != null && connection!.attached) {
        _lastSentText = text;
        _lastSentSelection = _selection;
        connection!.setEditingState(
          TextEditingValue(text: _lastSentText!, selection: _selection),
        );
      }
      
      notifyListeners();
      return;
    }

    if (actualInsertedText.length == 2 && actualInsertedText[0] != actualInsertedText[1]) {
      if (_bufferLineIndex != null && _bufferDirty) {
        final bufferEnd = _bufferLineRopeStart + _bufferLineText!.length;

        if (offset >= _bufferLineRopeStart && offset <= bufferEnd) {
          final localOffset = offset - _bufferLineRopeStart;
          if (localOffset >= 0 && localOffset <= _bufferLineText!.length) {
            _bufferLineText =
                _bufferLineText!.substring(0, localOffset) +
                actualInsertedText +
                _bufferLineText!.substring(localOffset);
            _selection = actualSelection;
            _currentVersion++;
            dirtyLine = _bufferLineIndex;

            bufferNeedsRepaint = true;

            if (connection != null && connection!.attached) {
              _lastSentText = text;
              _lastSentSelection = _selection;
              connection!.setEditingState(
                TextEditingValue(text: _lastSentText!, selection: _selection),
              );
            }

            _scheduleFlush();
            notifyListeners();
            return;
          }
        }
        _flushBuffer();
      }

      final lineIndex = _rope.getLineAtOffset(offset);
      _initBuffer(lineIndex);

      final localOffset = offset - _bufferLineRopeStart;
      if (localOffset >= 0 && localOffset <= _bufferLineText!.length) {
        _bufferLineText =
            _bufferLineText!.substring(0, localOffset) +
            actualInsertedText +
            _bufferLineText!.substring(localOffset);
        _bufferDirty = true;
        _selection = actualSelection;
        _currentVersion++;
        dirtyLine = lineIndex;

        bufferNeedsRepaint = true;

        if (connection != null && connection!.attached) {
          _lastSentText = text;
          _lastSentSelection = _selection;
          connection!.setEditingState(
            TextEditingValue(text: _lastSentText!, selection: _selection),
          );
        }

        _scheduleFlush();
        notifyListeners();
      }
      return;
    }

    if (_bufferLineIndex != null && _bufferDirty) {
      final bufferEnd = _bufferLineRopeStart + _bufferLineText!.length;

      if (offset >= _bufferLineRopeStart && offset <= bufferEnd) {
        final localOffset = offset - _bufferLineRopeStart;
        if (localOffset >= 0 && localOffset <= _bufferLineText!.length) {
          _bufferLineText =
              _bufferLineText!.substring(0, localOffset) +
              actualInsertedText +
              _bufferLineText!.substring(localOffset);
          _selection = actualSelection;
          _currentVersion++;

          bufferNeedsRepaint = true;

          _scheduleFlush();
          return;
        }
      }
      _flushBuffer();
    }

    final lineIndex = _rope.getLineAtOffset(offset);
    _initBuffer(lineIndex);

    final localOffset = offset - _bufferLineRopeStart;
    if (localOffset >= 0 && localOffset <= _bufferLineText!.length) {
      _bufferLineText =
          _bufferLineText!.substring(0, localOffset) +
          actualInsertedText +
          _bufferLineText!.substring(localOffset);
      _bufferDirty = true;
      _selection = actualSelection;
      _currentVersion++;
      dirtyLine = lineIndex;

      bufferNeedsRepaint = true;

      _scheduleFlush();
    }
  }

  void _handleDeletion(TextRange range, TextSelection newSelection) {
    final currentLength = length;
    if (range.start < 0 ||
        range.end > currentLength ||
        range.start > range.end) {
      return;
    }

    final deleteLen = range.end - range.start;

    if (_bufferLineIndex != null && _bufferDirty) {
      final bufferEnd = _bufferLineRopeStart + _bufferLineText!.length;

      if (range.start >= _bufferLineRopeStart && range.end <= bufferEnd) {
        final localStart = range.start - _bufferLineRopeStart;
        final localEnd = range.end - _bufferLineRopeStart;

        if (localStart >= 0 && localEnd <= _bufferLineText!.length) {
          final deletedText = _bufferLineText!.substring(localStart, localEnd);
          if (deletedText.contains('\n')) {
            _flushBuffer();
            _rope.delete(range.start, range.end);
            _currentVersion++;
            _selection = newSelection;
            dirtyLine = _rope.getLineAtOffset(range.start);
            lineStructureChanged = true;
            dirtyRegion = TextRange(start: range.start, end: range.start);
            return;
          }

          _bufferLineText =
              _bufferLineText!.substring(0, localStart) +
              _bufferLineText!.substring(localEnd);
          _selection = newSelection;
          _currentVersion++;

          bufferNeedsRepaint = true;

          _scheduleFlush();
          return;
        }
      }
      _flushBuffer();
    }

    bool crossesNewline = false;
    if (deleteLen == 1) {
      if (range.start < _rope.length && _rope.charAt(range.start) == '\n') {
        crossesNewline = true;
      }
    } else {
      crossesNewline = true;
    }

    if (crossesNewline) {
      _rope.delete(range.start, range.end);
      _currentVersion++;
      _selection = newSelection;
      dirtyLine = _rope.getLineAtOffset(range.start);
      lineStructureChanged = true;
      dirtyRegion = TextRange(start: range.start, end: range.start);
      return;
    }

    final lineIndex = _rope.getLineAtOffset(range.start);
    _initBuffer(lineIndex);

    final localStart = range.start - _bufferLineRopeStart;
    final localEnd = range.end - _bufferLineRopeStart;

    if (localStart >= 0 && localEnd <= _bufferLineText!.length) {
      _bufferLineText =
          _bufferLineText!.substring(0, localStart) +
          _bufferLineText!.substring(localEnd);
      _bufferDirty = true;
      _selection = newSelection;
      _currentVersion++;

      bufferNeedsRepaint = true;

      _scheduleFlush();
    }
  }

  void _handleReplacement(
    TextRange range,
    String text,
    TextSelection newSelection,
  ) {
    _flushBuffer();
    _rope.delete(range.start, range.end);
    _rope.insert(range.start, text);
    _currentVersion++;
    _selection = newSelection;
    dirtyLine = _rope.getLineAtOffset(range.start);
    dirtyRegion = TextRange(start: range.start, end: range.start + text.length);
  }

  void _initBuffer(int lineIndex) {
    _bufferLineIndex = lineIndex;
    _bufferLineText = _rope.getLineText(lineIndex);
    _bufferLineRopeStart = _rope.getLineStartOffset(lineIndex);
    _bufferLineOriginalLength = _bufferLineText!.length;
    _bufferDirty = false;
  }

  bool get isBufferActive => _bufferLineIndex != null && _bufferDirty;
  int? get bufferLineIndex => _bufferLineIndex;
  int get bufferLineRopeStart => _bufferLineRopeStart;
  String? get bufferLineText => _bufferLineText;

  int get bufferCursorColumn {
    if (!isBufferActive) return 0;
    return _selection.extentOffset - _bufferLineRopeStart;
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushDelay, _flushBuffer);
  }

  void _flushBuffer() {
    _flushTimer?.cancel();
    _flushTimer = null;

    if (_bufferLineIndex == null || !_bufferDirty) return;

    final lineToInvalidate = _bufferLineIndex!;

    final start = _bufferLineRopeStart;
    final end = start + _bufferLineOriginalLength;

    if (_bufferLineOriginalLength > 0) {
      _rope.delete(start, end);
    }
    if (_bufferLineText!.isNotEmpty) {
      _rope.insert(start, _bufferLineText!);
    }

    _bufferLineIndex = null;
    _bufferLineText = null;
    _bufferDirty = false;

    dirtyLine = lineToInvalidate;
    notifyListeners();
  }

  String _getCurrentWordPrefix(String text, int offset) {
    final safeOffset = offset.clamp(0, text.length);
    final beforeCursor = text.substring(0, safeOffset);
    final match = RegExp(r'([a-zA-Z_][a-zA-Z0-9_]*)$').firstMatch(beforeCursor);
    return match?.group(0) ?? '';
  }

  void clearDirtyRegion() {
    dirtyRegion = null;
    dirtyLine = null;
    lineStructureChanged = false;
  }

  /// Insert text at the current cursor position (or replace selection).
  void insertAtCurrentCursor(
    String textToInsert, {
    bool replaceTypedChar = false,
  }) {
    _flushBuffer();

    final cursorPosition = selection.extentOffset;
    final safePosition = cursorPosition.clamp(0, _rope.length);
    final currentLine = _rope.getLineAtOffset(safePosition);
    final isFolded = foldings.any(
      (fold) =>
        fold.isFolded &&
        currentLine > fold.startIndex &&
        currentLine <= fold.endIndex,
    );

    if (isFolded) {
      final newPosition = visibleText.length;
      selection = TextSelection.collapsed(offset: newPosition);
      return;
    }

    if (replaceTypedChar) {
      final ropeText = _rope.getText();
      final prefix = _getCurrentWordPrefix(ropeText, safePosition);
      final prefixStart = (safePosition - prefix.length).clamp(0, _rope.length);

      replaceRange(prefixStart, safePosition, textToInsert);
    } else {
      replaceRange(safePosition, safePosition, textToInsert);
    }
  }

  /// Sync current state to the IME connection
  void _syncToConnection() {
    if (connection != null && connection!.attached) {
      final currentText = text;
      _lastSentText = currentText;
      _lastSentSelection = _selection;
      connection!.setEditingState(
        TextEditingValue(text: currentText, selection: _selection),
      );
    }
  }

  /// Remove the selection or last char if the selection is empty (backspace key)
  void backspace() {
    _flushBuffer();

    final sel = _selection;

    if (sel.start < sel.end) {
      _rope.delete(sel.start, sel.end);
      _currentVersion++;
      _selection = TextSelection.collapsed(offset: sel.start);
      dirtyLine = _rope.getLineAtOffset(sel.start);
    } else if (sel.start > 0) {
      _rope.delete(sel.start - 1, sel.start);
      _currentVersion++;
      _selection = TextSelection.collapsed(offset: sel.start - 1);
      dirtyLine = _rope.getLineAtOffset(sel.start - 1);
    } else {
      return;
    }

    _syncToConnection();
    notifyListeners();
  }

  /// Remove the selection or the char at cursor position (delete key)
  void delete() {
    _flushBuffer();

    final sel = _selection;
    final textLen = _rope.length;

    if (sel.start < sel.end) {
      _rope.delete(sel.start, sel.end);
      _currentVersion++;
      _selection = TextSelection.collapsed(offset: sel.start);
      dirtyLine = _rope.getLineAtOffset(sel.start);
    } else if (sel.start < textLen) {
      _rope.delete(sel.start, sel.start + 1);
      _currentVersion++;
      dirtyLine = _rope.getLineAtOffset(sel.start);
    } else {
      return;
    }

    _syncToConnection();
    notifyListeners();
  }

  @override
  void connectionClosed() {
    connection = null;
  }

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  TextEditingValue? get currentTextEditingValue =>
      TextEditingValue(text: text, selection: _selection);

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {}
  @override
  void insertContent(KeyboardInsertedContent content) {}
  @override
  void insertTextPlaceholder(Size size) {}
  @override
  void performAction(TextInputAction action) {}
  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}
  @override
  void performSelector(String selectorName) {}
  @override
  void removeTextPlaceholder() {}
  @override
  void showAutocorrectionPromptRect(int start, int end) {}
  @override
  void showToolbar() {}
  @override
  void updateEditingValue(TextEditingValue value) {}
  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  /// Replace a range of text with new text.
  /// Used for clipboard operations and text manipulation.
  void replaceRange(int start, int end, String replacement) {
    _flushBuffer();
    final safeStart = start.clamp(0, _rope.length);
    final safeEnd = end.clamp(safeStart, _rope.length);

    if (safeStart < safeEnd) {
      _rope.delete(
        safeStart,
        safeEnd,
      );
    }
    if (replacement.isNotEmpty) {
      _rope.insert(safeStart, replacement);
    }
    _currentVersion++;
    _selection = TextSelection.collapsed(
      offset: safeStart + replacement.length,
    );
    dirtyLine = _rope.getLineAtOffset(safeStart);
    dirtyRegion = TextRange(
      start: safeStart,
      end: safeStart + replacement.length,
    );

    if (connection != null && connection!.attached) {
      _lastSentText = text;
      _lastSentSelection = _selection;
      connection!.setEditingState(
        TextEditingValue(text: _lastSentText!, selection: _selection),
      );
    }

    notifyListeners();
  }

  void dispose() {
    _listeners.clear();
    connection?.close();
  }
}
