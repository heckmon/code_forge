import 'dart:async';
import 'dart:io';

import '../code_forge.dart';
import 'rope.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Controller for the [CodeForge] code editor widget.
///
/// This controller manages the text content, selection state, and various
/// editing operations for the code editor. It implements [DeltaTextInputClient]
/// to handle text input from the platform.
///
/// The controller uses a rope data structure internally for efficient text
/// manipulation, especially for large documents.
///
/// Example:
/// ```dart
/// final controller = CodeForgeController();
/// controller.text = 'void main() {\n  print("Hello");\n}';
///
/// // Access selection
/// print(controller.selection);
///
/// // Get specific line
/// print(controller.getLineText(0)); // 'void main() {'
///
/// // Fold/unfold code
/// controller.foldAll();
/// controller.unfoldAll();
/// ```
class CodeForgeController implements DeltaTextInputClient {
  static const _flushDelay = Duration(milliseconds: 300);
  final List<VoidCallback> _listeners = [];
  Timer? _flushTimer;
  String? _cachedText, _bufferLineText;
  bool _bufferDirty = false, bufferNeedsRepaint = false, selectionOnly = false;
  int _bufferLineRopeStart = 0, _bufferLineOriginalLength = 0;
  int _cachedTextVersion = -1, _currentVersion = 0;
  int? dirtyLine, _bufferLineIndex;
  String? _lastSentText;
  TextSelection? _lastSentSelection;
  UndoRedoController? _undoController;
  void Function(int lineNumber)? _toggleFoldCallback;
  VoidCallback? _foldAllCallback, _unfoldAllCallback;

  /// Currently opened file.
  String? openedFile;

  /// Callback for manually triggering AI completion.
  /// Set this to enable custom AI completion triggers.
  VoidCallback? manualAiCompletion;

  Rope _rope = Rope('');
  TextSelection _selection = const TextSelection.collapsed(offset: 0);

  /// The text input connection to the platform.
  TextInputConnection? connection;

  /// The range of text that has been modified and needs reprocessing.
  TextRange? dirtyRegion;

  /// List of all fold ranges detected in the document.
  ///
  /// This list is automatically populated based on code structure
  /// (braces, indentation, etc.) when folding is enabled.
  List<FoldRange> foldings = [];

  /// List of search highlights to display in the editor.
  ///
  /// Add [SearchHighlight] objects to this list to highlight
  /// search results or other text ranges.
  List<SearchHighlight> searchHighlights = [];

  /// Whether the search highlights have changed and need repaint.
  bool searchHighlightsChanged = false;

  /// Whether the editor is in read-only mode.
  ///
  /// When true, the user cannot modify the text content.
  bool readOnly = false;

  /// Whether the line structure has changed (lines added or removed).
  bool lineStructureChanged = false;

  /// Callback to show Ai suggestion manually when the [AiCompletion.completionType] is [CompletionType.manual] or [CompletionType.mixed].
  void getManualAiSuggestion() {
    manualAiCompletion?.call();
  }

  /// Sets the undo controller for this editor.
  ///
  /// The undo controller manages the undo/redo history for text operations.
  /// Pass null to disable undo/redo functionality.
  void setUndoController(UndoRedoController? controller) {
    _undoController = controller;
    if (controller != null) {
      controller.setApplyEditCallback(_applyUndoRedoOperation);
    }
  }

  /// Save the current content, [controller.text] to the opened file.
  void saveFile() {
    if (openedFile == null) {
      throw FlutterError(
        "No file found.\nPlease open a file by providing a valid filePath to the CodeForge widget",
      );
    }
    File(openedFile!).writeAsStringSync(text);
  }

  /// Moves the cursor one character to the left.
  ///
  /// If [isShiftPressed] is true, extends the selection.
  void pressLetfArrowKey({bool isShiftPressed = false}) {
    int newOffset;
    if (!isShiftPressed && selection.start != selection.end) {
      newOffset = selection.start;
    } else if (selection.extentOffset > 0) {
      newOffset = selection.extentOffset - 1;
    } else {
      newOffset = 0;
    }

    if (isShiftPressed) {
      setSelectionSilently(
        TextSelection(
          baseOffset: selection.baseOffset,
          extentOffset: newOffset,
        ),
      );
    } else {
      setSelectionSilently(TextSelection.collapsed(offset: newOffset));
    }
  }

  /// Moves the cursor one character to the right.
  ///
  /// If [isShiftPressed] is true, extends the selection.
  void pressRightArrowKey({bool isShiftPressed = false}) {
    int newOffset;
    if (!isShiftPressed && selection.start != selection.end) {
      newOffset = selection.end;
    } else if (selection.extentOffset < length) {
      newOffset = selection.extentOffset + 1;
    } else {
      newOffset = length;
    }

    if (isShiftPressed) {
      setSelectionSilently(
        TextSelection(
          baseOffset: selection.baseOffset,
          extentOffset: newOffset,
        ),
      );
    } else {
      setSelectionSilently(TextSelection.collapsed(offset: newOffset));
    }
  }

  /// Moves the cursor up one line, maintaining the column position.
  ///
  /// If [isShiftPressed] is true, extends the selection.
  void pressUpArrowKey({bool isShiftPressed = false}) {
    final currentLine = getLineAtOffset(selection.extentOffset);

    if (currentLine <= 0) {
      if (isShiftPressed) {
        setSelectionSilently(
          TextSelection(baseOffset: selection.baseOffset, extentOffset: 0),
        );
      } else {
        setSelectionSilently(const TextSelection.collapsed(offset: 0));
      }
      return;
    }

    int targetLine = currentLine - 1;
    while (targetLine > 0 && _isLineInFoldedRegion(targetLine)) {
      targetLine--;
    }

    if (_isLineInFoldedRegion(targetLine)) {
      targetLine = _getFoldStartForLine(targetLine) ?? 0;
    }

    final lineStart = getLineStartOffset(currentLine);
    final column = selection.extentOffset - lineStart;
    final prevLineStart = getLineStartOffset(targetLine);
    final prevLineText = getLineText(targetLine);
    final prevLineLength = prevLineText.length;
    final newColumn = column.clamp(0, prevLineLength);
    final newOffset = (prevLineStart + newColumn).clamp(0, length);

    if (isShiftPressed) {
      setSelectionSilently(
        TextSelection(
          baseOffset: selection.baseOffset,
          extentOffset: newOffset,
        ),
      );
    } else {
      setSelectionSilently(TextSelection.collapsed(offset: newOffset));
    }
  }

  /// Moves the cursor down one line, maintaining the column position.
  ///
  /// If [isShiftPressed] is true, extends the selection.
  void pressDownArrowKey({bool isShiftPressed = false}) {
    final currentLine = getLineAtOffset(selection.extentOffset);

    if (currentLine >= lineCount - 1) {
      final endOffset = length;
      if (isShiftPressed) {
        setSelectionSilently(
          TextSelection(
            baseOffset: selection.baseOffset,
            extentOffset: endOffset,
          ),
        );
      } else {
        setSelectionSilently(TextSelection.collapsed(offset: endOffset));
      }
      return;
    }

    final foldAtCurrent = _getFoldRangeAtCurrentLine(currentLine);
    int targetLine;
    if (foldAtCurrent != null && foldAtCurrent.isFolded) {
      targetLine = foldAtCurrent.endIndex + 1;
    } else {
      targetLine = currentLine + 1;
    }

    while (targetLine < lineCount && _isLineInFoldedRegion(targetLine)) {
      final foldStart = _getFoldStartForLine(targetLine);
      if (foldStart != null) {
        final fold = foldings.firstWhere(
          (f) => f.startIndex == foldStart && f.isFolded,
          orElse: () => FoldRange(targetLine, targetLine),
        );
        targetLine = fold.endIndex + 1;
      } else {
        targetLine++;
      }
    }

    if (targetLine >= lineCount) {
      final endOffset = length;
      if (isShiftPressed) {
        setSelectionSilently(
          TextSelection(
            baseOffset: selection.baseOffset,
            extentOffset: endOffset,
          ),
        );
      } else {
        setSelectionSilently(TextSelection.collapsed(offset: endOffset));
      }
      return;
    }

    final lineStart = getLineStartOffset(currentLine);
    final column = selection.extentOffset - lineStart;
    final nextLineStart = getLineStartOffset(targetLine);
    final nextLineText = getLineText(targetLine);
    final nextLineLength = nextLineText.length;
    final newColumn = column.clamp(0, nextLineLength);
    final newOffset = (nextLineStart + newColumn).clamp(0, length);

    if (isShiftPressed) {
      setSelectionSilently(
        TextSelection(
          baseOffset: selection.baseOffset,
          extentOffset: newOffset,
        ),
      );
    } else {
      setSelectionSilently(TextSelection.collapsed(offset: newOffset));
    }
  }

  /// Moves the cursor to the beginning of the current line.
  ///
  /// If [isShiftPressed] is true, extends the selection to the line start.
  void pressHomeKey({bool isShiftPressed = false}) {
    final currentLine = getLineAtOffset(selection.extentOffset);
    final lineStart = getLineStartOffset(currentLine);

    if (isShiftPressed) {
      setSelectionSilently(
        TextSelection(
          baseOffset: selection.baseOffset,
          extentOffset: lineStart,
        ),
      );
    } else {
      setSelectionSilently(TextSelection.collapsed(offset: lineStart));
    }
  }

  /// Moves the cursor to the end of the current line.
  ///
  /// If [isShiftPressed] is true, extends the selection to the line end.
  void pressEndKey({bool isShiftPressed = false}) {
    final currentLine = getLineAtOffset(selection.extentOffset);
    final lineText = getLineText(currentLine);
    final lineStart = getLineStartOffset(currentLine);
    final lineEnd = lineStart + lineText.length;

    if (isShiftPressed) {
      setSelectionSilently(
        TextSelection(baseOffset: selection.baseOffset, extentOffset: lineEnd),
      );
    } else {
      setSelectionSilently(TextSelection.collapsed(offset: lineEnd));
    }
  }

  /// Copies the currently selected text to the clipboard.
  ///
  /// If no text is selected, does nothing.
  void copy() {
    final sel = selection;
    if (sel.start == sel.end) return;
    final selectedText = text.substring(sel.start, sel.end);
    Clipboard.setData(ClipboardData(text: selectedText));
  }

  /// Cuts the currently selected text to the clipboard.
  ///
  /// If no text is selected, does nothing.
  void cut() {
    final sel = selection;
    if (sel.start == sel.end) return;
    final selectedText = text.substring(sel.start, sel.end);
    Clipboard.setData(ClipboardData(text: selectedText));
    replaceRange(sel.start, sel.end, '');
  }

  /// Pastes text from the clipboard at the current cursor position.
  ///
  /// Replaces any selected text with the pasted content.
  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    final sel = selection;
    replaceRange(sel.start, sel.end, data.text!);
  }

  /// Selects all text in the editor.
  void selectAll() {
    selection = TextSelection(baseOffset: 0, extentOffset: length);
  }

  /// The complete text content of the editor.
  ///
  /// Getting this property returns the full document text.
  /// Setting this property replaces all content and moves the cursor to the end.
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

  /// The total length of the document in characters.
  int get length {
    if (_bufferLineIndex != null && _bufferDirty) {
      return _rope.length +
          (_bufferLineText!.length - _bufferLineOriginalLength);
    }
    return _rope.length;
  }

  /// The current text selection in the editor.
  ///
  /// For a cursor with no selection, [TextSelection.isCollapsed] will be true.
  TextSelection get selection => _selection;

  /// List of all lines in the document.
  List<String> get lines => _rope.cachedLines;

  /// The total number of lines in the document.
  int get lineCount {
    return _rope.lineCount;
  }

  /// The visible text content with folded regions hidden.
  ///
  /// Returns the document text with lines inside collapsed fold ranges removed.
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

  /// Gets the text content of a specific line.
  ///
  /// [lineIndex] is zero-based (0 for the first line).
  /// Returns the text of the line without the newline character.
  String getLineText(int lineIndex) {
    if (_bufferLineIndex != null &&
        lineIndex == _bufferLineIndex &&
        _bufferDirty) {
      return _bufferLineText!;
    }
    return _rope.getLineText(lineIndex);
  }

  /// Gets the line number (zero-based) for a character offset.
  ///
  /// [charOffset] is the character position in the document.
  /// Returns the line index containing that character.
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

  /// Gets the character offset where a line starts.
  ///
  /// [lineIndex] is zero-based (0 for the first line).
  /// Returns the character offset of the first character in that line.
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

  /// Finds the start of the line containing [offset].
  int findLineStart(int offset) => _rope.findLineStart(offset);

  /// Finds the end of the line containing [offset].
  int findLineEnd(int offset) => _rope.findLineEnd(offset);

  set text(String newText) {
    _rope = Rope(newText);
    _currentVersion++;
    _selection = TextSelection.collapsed(offset: newText.length);
    dirtyRegion = TextRange(start: 0, end: newText.length);
    notifyListeners();
  }

  /// Sets the current text selection.
  ///
  /// Setting this property will update the selection and notify listeners.
  /// For a collapsed cursor, use `TextSelection.collapsed(offset: pos)`.
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

  /// Updates selection and syncs to text input connection for keyboard navigation.
  ///
  /// This method flushes any pending buffer first to ensure IME state is consistent.
  /// Use this for programmatic selection changes that should sync with the platform.
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

  /// Adds a listener that will be called when the controller state changes.
  ///
  /// Listeners are notified on text changes, selection changes, and other
  /// state updates.
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Removes a previously added listener.
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Notifies all registered listeners of a state change.
  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    if (readOnly) return;
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

  bool get isBufferActive => _bufferLineIndex != null && _bufferDirty;
  int? get bufferLineIndex => _bufferLineIndex;
  int get bufferLineRopeStart => _bufferLineRopeStart;
  String? get bufferLineText => _bufferLineText;

  int get bufferCursorColumn {
    if (!isBufferActive) return 0;
    return _selection.extentOffset - _bufferLineRopeStart;
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
    if (_undoController?.isUndoRedoInProgress ?? false) return;

    _flushBuffer();

    final selectionBefore = _selection;
    final sel = _selection;
    String deletedText;

    if (sel.start < sel.end) {
      deletedText = _rope.substring(sel.start, sel.end);
      _rope.delete(sel.start, sel.end);
      _currentVersion++;
      _selection = TextSelection.collapsed(offset: sel.start);
      dirtyLine = _rope.getLineAtOffset(sel.start);

      _recordDeletion(sel.start, deletedText, selectionBefore, _selection);
    } else if (sel.start > 0) {
      deletedText = _rope.charAt(sel.start - 1);
      _rope.delete(sel.start - 1, sel.start);
      _currentVersion++;
      _selection = TextSelection.collapsed(offset: sel.start - 1);
      dirtyLine = _rope.getLineAtOffset(sel.start - 1);

      _recordDeletion(sel.start - 1, deletedText, selectionBefore, _selection);
    } else {
      return;
    }

    _syncToConnection();
    notifyListeners();
  }

  /// Remove the selection or the char at cursor position (delete key)
  void delete() {
    if (_undoController?.isUndoRedoInProgress ?? false) return;

    _flushBuffer();

    final selectionBefore = _selection;
    final sel = _selection;
    final textLen = _rope.length;
    String deletedText;

    if (sel.start < sel.end) {
      deletedText = _rope.substring(sel.start, sel.end);
      _rope.delete(sel.start, sel.end);
      _currentVersion++;
      _selection = TextSelection.collapsed(offset: sel.start);
      dirtyLine = _rope.getLineAtOffset(sel.start);

      _recordDeletion(sel.start, deletedText, selectionBefore, _selection);
    } else if (sel.start < textLen) {
      deletedText = _rope.charAt(sel.start);
      _rope.delete(sel.start, sel.start + 1);
      _currentVersion++;
      dirtyLine = _rope.getLineAtOffset(sel.start);

      _recordDeletion(sel.start, deletedText, selectionBefore, _selection);
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
    if (_undoController?.isUndoRedoInProgress ?? false) return;

    final selectionBefore = _selection;
    _flushBuffer();
    final safeStart = start.clamp(0, _rope.length);
    final safeEnd = end.clamp(safeStart, _rope.length);
    final deletedText = safeStart < safeEnd
        ? _rope.substring(safeStart, safeEnd)
        : '';

    if (safeStart < safeEnd) {
      _rope.delete(safeStart, safeEnd);
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

    if (deletedText.isNotEmpty && replacement.isNotEmpty) {
      _recordReplacement(
        safeStart,
        deletedText,
        replacement,
        selectionBefore,
        _selection,
      );
    } else if (deletedText.isNotEmpty) {
      _recordDeletion(safeStart, deletedText, selectionBefore, _selection);
    } else if (replacement.isNotEmpty) {
      _recordInsertion(safeStart, replacement, selectionBefore, _selection);
    }

    if (connection != null && connection!.attached) {
      _lastSentText = text;
      _lastSentSelection = _selection;
      connection!.setEditingState(
        TextEditingValue(text: _lastSentText!, selection: _selection),
      );
    }

    notifyListeners();
  }

  void findWord(
    String word, {
    TextStyle? highlightStyle,
    bool matchCase = false,
    bool matchWholeWord = false,
  }) {
    final style =
        highlightStyle ?? const TextStyle(backgroundColor: Colors.amberAccent);

    searchHighlights.clear();

    if (word.isEmpty) {
      searchHighlightsChanged = true;
      notifyListeners();
      return;
    }

    final searchText = text;
    final searchWord = matchCase ? word : word.toLowerCase();
    final textToSearch = matchCase ? searchText : searchText.toLowerCase();

    int offset = 0;
    while (offset < textToSearch.length) {
      final index = textToSearch.indexOf(searchWord, offset);
      if (index == -1) break;

      bool isMatch = true;

      if (matchWholeWord) {
        final before = index > 0 ? searchText[index - 1] : '';
        final after = index + word.length < searchText.length
            ? searchText[index + word.length]
            : '';

        final isWordChar = RegExp(r'\w');
        final beforeIsWord = before.isNotEmpty && isWordChar.hasMatch(before);
        final afterIsWord = after.isNotEmpty && isWordChar.hasMatch(after);

        if (beforeIsWord || afterIsWord) {
          isMatch = false;
        }
      }

      if (isMatch) {
        searchHighlights.add(
          SearchHighlight(start: index, end: index + word.length, style: style),
        );
      }

      offset = index + 1;
    }

    searchHighlightsChanged = true;
    notifyListeners();
  }

  void findRegex(RegExp regex, TextStyle? highlightStyle) {
    final style =
        highlightStyle ?? const TextStyle(backgroundColor: Colors.amberAccent);

    searchHighlights.clear();

    final searchText = text;
    final matches = regex.allMatches(searchText);

    for (final match in matches) {
      searchHighlights.add(
        SearchHighlight(start: match.start, end: match.end, style: style),
      );
    }

    searchHighlightsChanged = true;
    notifyListeners();
  }

  /// Clear all search highlights
  void clearSearchHighlights() {
    searchHighlights.clear();
    searchHighlightsChanged = true;
    notifyListeners();
  }

  /// Set fold operation callbacks - called by the render object
  void setFoldCallbacks({
    void Function(int lineNumber)? toggleFold,
    VoidCallback? foldAll,
    VoidCallback? unfoldAll,
  }) {
    _toggleFoldCallback = toggleFold;
    _foldAllCallback = foldAll;
    _unfoldAllCallback = unfoldAll;
  }

  /// Toggles the fold state at the specified line number.
  ///
  /// [lineNumber] is zero-indexed (0 for the first line).
  /// If the line is at the start of a fold region, it will be toggled.
  ///
  /// Throws [StateError] if:
  /// - Folding is not enabled on the editor
  /// - The editor has not been initialized
  /// - No fold range exists at the specified line
  ///
  /// Example:
  /// ```dart
  /// controller.toggleFold(5); // Toggle fold at line 6
  /// ```
  void toggleFold(int lineNumber) {
    if (_toggleFoldCallback == null) {
      throw StateError('Folding is not enabled or editor is not initialized');
    }
    _toggleFoldCallback!(lineNumber);
  }

  /// Folds all foldable regions in the document.
  ///
  /// All detected fold ranges will be collapsed, hiding their contents.
  ///
  /// Throws [StateError] if folding is not enabled or editor is not initialized.
  ///
  /// Example:
  /// ```dart
  /// controller.foldAll();
  /// ```
  void foldAll() {
    if (_foldAllCallback == null) {
      throw StateError('Folding is not enabled or editor is not initialized');
    }
    _foldAllCallback!();
  }

  /// Unfolds all folded regions in the document.
  ///
  /// All collapsed fold ranges will be expanded, showing their contents.
  ///
  /// Throws [StateError] if folding is not enabled or editor is not initialized.
  ///
  /// Example:
  /// ```dart
  /// controller.unfoldAll();
  /// ```
  void unfoldAll() {
    if (_unfoldAllCallback == null) {
      throw StateError('Folding is not enabled or editor is not initialized');
    }
    _unfoldAllCallback!();
  }

  /// Disposes of the controller and releases resources.
  ///
  /// Call this method when the controller is no longer needed to prevent
  /// memory leaks.
  void dispose() {
    _listeners.clear();
    connection?.close();
  }

  void _applyUndoRedoOperation(EditOperation operation) {
    _flushBuffer();

    switch (operation) {
      case InsertOperation(:final offset, :final text, :final selectionAfter):
        _rope.insert(offset, text);
        _currentVersion++;
        _selection = selectionAfter;
        dirtyLine = _rope.getLineAtOffset(offset);
        if (text.contains('\n')) {
          lineStructureChanged = true;
        }
        dirtyRegion = TextRange(start: offset, end: offset + text.length);

      case DeleteOperation(:final offset, :final text, :final selectionAfter):
        _rope.delete(offset, offset + text.length);
        _currentVersion++;
        _selection = selectionAfter;
        dirtyLine = _rope.getLineAtOffset(offset);
        if (text.contains('\n')) {
          lineStructureChanged = true;
        }
        dirtyRegion = TextRange(start: offset, end: offset);

      case ReplaceOperation(
        :final offset,
        :final deletedText,
        :final insertedText,
        :final selectionAfter,
      ):
        if (deletedText.isNotEmpty) {
          _rope.delete(offset, offset + deletedText.length);
        }
        if (insertedText.isNotEmpty) {
          _rope.insert(offset, insertedText);
        }
        _currentVersion++;
        _selection = selectionAfter;
        dirtyLine = _rope.getLineAtOffset(offset);
        if (deletedText.contains('\n') || insertedText.contains('\n')) {
          lineStructureChanged = true;
        }
        dirtyRegion = TextRange(
          start: offset,
          end: offset + insertedText.length,
        );

      case CompoundOperation(:final operations):
        for (final op in operations) {
          _applyUndoRedoOperation(op);
        }
        return;
    }

    _syncToConnection();
    notifyListeners();
  }

  void _recordEdit(EditOperation operation) {
    _undoController?.recordEdit(operation);
  }

  void _recordInsertion(
    int offset,
    String text,
    TextSelection selBefore,
    TextSelection selAfter,
  ) {
    if (_undoController?.isUndoRedoInProgress ?? false) return;
    _recordEdit(
      InsertOperation(
        offset: offset,
        text: text,
        selectionBefore: selBefore,
        selectionAfter: selAfter,
      ),
    );
  }

  void _recordDeletion(
    int offset,
    String text,
    TextSelection selBefore,
    TextSelection selAfter,
  ) {
    if (_undoController?.isUndoRedoInProgress ?? false) return;
    _recordEdit(
      DeleteOperation(
        offset: offset,
        text: text,
        selectionBefore: selBefore,
        selectionAfter: selAfter,
      ),
    );
  }

  void _recordReplacement(
    int offset,
    String deleted,
    String inserted,
    TextSelection selBefore,
    TextSelection selAfter,
  ) {
    if (_undoController?.isUndoRedoInProgress ?? false) return;
    _recordEdit(
      ReplaceOperation(
        offset: offset,
        deletedText: deleted,
        insertedText: inserted,
        selectionBefore: selBefore,
        selectionAfter: selAfter,
      ),
    );
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
    searchHighlightsChanged = false;
  }

  void _handleInsertion(
    int offset,
    String insertedText,
    TextSelection newSelection,
  ) {
    if (_undoController?.isUndoRedoInProgress ?? false) return;

    final selectionBefore = _selection;
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
      } else if (closers.contains(char)) {
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
        final lastChar = trimmedPrev.isNotEmpty
            ? trimmedPrev[trimmedPrev.length - 1]
            : null;
        final trimmedNext = textAfterCursor.trimLeft();
        final nextChar = trimmedNext.isNotEmpty ? trimmedNext[0] : null;
        final isBracketOpen = openToClose.containsKey(lastChar);
        final isNextClosing =
            isBracketOpen && openToClose[lastChar] == nextChar;

        if (isBracketOpen && isNextClosing) {
          actualInsertedText = '\n$indent\n$prevIndent';
          actualSelection = TextSelection.collapsed(
            offset: offset + 1 + indent.length,
          );
        } else {
          actualInsertedText = '\n$indent';
          actualSelection = TextSelection.collapsed(
            offset: offset + actualInsertedText.length,
          );
        }
      }

      _flushBuffer();
      _rope.insert(offset, actualInsertedText);
      _currentVersion++;
      _selection = actualSelection;
      dirtyLine = _rope.getLineAtOffset(offset);
      lineStructureChanged = true;
      dirtyRegion = TextRange(
        start: offset,
        end: offset + actualInsertedText.length,
      );

      _recordInsertion(
        offset,
        actualInsertedText,
        selectionBefore,
        actualSelection,
      );

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

    if (actualInsertedText.length == 2 &&
        actualInsertedText[0] != actualInsertedText[1]) {
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

            _recordInsertion(
              offset,
              actualInsertedText,
              selectionBefore,
              actualSelection,
            );

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

        _recordInsertion(
          offset,
          actualInsertedText,
          selectionBefore,
          actualSelection,
        );

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

          _recordInsertion(
            offset,
            actualInsertedText,
            selectionBefore,
            actualSelection,
          );

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

      _recordInsertion(
        offset,
        actualInsertedText,
        selectionBefore,
        actualSelection,
      );

      _scheduleFlush();
    }
  }

  void _handleDeletion(TextRange range, TextSelection newSelection) {
    if (_undoController?.isUndoRedoInProgress ?? false) return;

    final selectionBefore = _selection;
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

            _recordDeletion(
              range.start,
              deletedText,
              selectionBefore,
              newSelection,
            );
            return;
          }

          _bufferLineText =
              _bufferLineText!.substring(0, localStart) +
              _bufferLineText!.substring(localEnd);
          _selection = newSelection;
          _currentVersion++;

          bufferNeedsRepaint = true;

          _recordDeletion(
            range.start,
            deletedText,
            selectionBefore,
            newSelection,
          );

          _scheduleFlush();
          return;
        }
      }
      _flushBuffer();
    }

    bool crossesNewline = false;
    String deletedText = '';
    if (deleteLen == 1) {
      if (range.start < _rope.length) {
        deletedText = _rope.charAt(range.start);
        if (deletedText == '\n') {
          crossesNewline = true;
        }
      }
    } else {
      crossesNewline = true;
      deletedText = _rope.substring(range.start, range.end);
    }

    if (crossesNewline) {
      if (deletedText.isEmpty) {
        deletedText = _rope.substring(range.start, range.end);
      }
      _rope.delete(range.start, range.end);
      _currentVersion++;
      _selection = newSelection;
      dirtyLine = _rope.getLineAtOffset(range.start);
      lineStructureChanged = true;
      dirtyRegion = TextRange(start: range.start, end: range.start);

      _recordDeletion(range.start, deletedText, selectionBefore, newSelection);
      return;
    }

    final lineIndex = _rope.getLineAtOffset(range.start);
    _initBuffer(lineIndex);

    final localStart = range.start - _bufferLineRopeStart;
    final localEnd = range.end - _bufferLineRopeStart;

    if (localStart >= 0 && localEnd <= _bufferLineText!.length) {
      deletedText = _bufferLineText!.substring(localStart, localEnd);
      _bufferLineText =
          _bufferLineText!.substring(0, localStart) +
          _bufferLineText!.substring(localEnd);
      _bufferDirty = true;
      _selection = newSelection;
      _currentVersion++;

      bufferNeedsRepaint = true;

      _recordDeletion(range.start, deletedText, selectionBefore, newSelection);

      _scheduleFlush();
    }
  }

  void _handleReplacement(
    TextRange range,
    String text,
    TextSelection newSelection,
  ) {
    if (_undoController?.isUndoRedoInProgress ?? false) return;

    final selectionBefore = _selection;
    _flushBuffer();

    final deletedText = range.start < range.end
        ? _rope.substring(range.start, range.end)
        : '';

    _rope.delete(range.start, range.end);
    _rope.insert(range.start, text);
    _currentVersion++;
    _selection = newSelection;
    dirtyLine = _rope.getLineAtOffset(range.start);
    dirtyRegion = TextRange(start: range.start, end: range.start + text.length);

    _recordReplacement(
      range.start,
      deletedText,
      text,
      selectionBefore,
      newSelection,
    );
  }

  void _initBuffer(int lineIndex) {
    _bufferLineIndex = lineIndex;
    _bufferLineText = _rope.getLineText(lineIndex);
    _bufferLineRopeStart = _rope.getLineStartOffset(lineIndex);
    _bufferLineOriginalLength = _bufferLineText!.length;
    _bufferDirty = false;
  }

  bool _isLineInFoldedRegion(int lineIndex) {
    return foldings.any(
      (fold) =>
          fold.isFolded &&
          lineIndex > fold.startIndex &&
          lineIndex <= fold.endIndex,
    );
  }

  int? _getFoldStartForLine(int lineIndex) {
    for (final fold in foldings) {
      if (fold.isFolded &&
          lineIndex > fold.startIndex &&
          lineIndex <= fold.endIndex) {
        return fold.startIndex;
      }
    }
    return null;
  }

  FoldRange? _getFoldRangeAtCurrentLine(int lineIndex) {
    try {
      return foldings.firstWhere((f) => f.startIndex == lineIndex);
    } catch (_) {
      return null;
    }
  }
}
