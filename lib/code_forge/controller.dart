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
  static const _semanticTokenDebounce = Duration(milliseconds: 500);
  final List<VoidCallback> _listeners = [];
  Timer? _flushTimer, _semanticTokenTimer, _codeActionTimer;
  String? _cachedText, _bufferLineText, _openedFile;
  String _previousValue = "";
  TextSelection _prevSelection = const TextSelection.collapsed(offset: 0);
  bool _bufferDirty = false, bufferNeedsRepaint = false, selectionOnly = false;
  int _bufferLineRopeStart = 0, _bufferLineOriginalLength = 0;
  int _cachedTextVersion = -1, _currentVersion = 0, _semanticTokensVersion = 0;
  int? dirtyLine, _bufferLineIndex;
  String? _lastSentText;
  TextSelection? _lastSentSelection;
  UndoRedoController? _undoController;
  void Function(int lineNumber)? _toggleFoldCallback;
  VoidCallback? _foldAllCallback, _unfoldAllCallback;
  bool _lspReady = false, _isTyping = false, _isDisposed = false;
  List<dynamic> _suggestions = [];
  StreamSubscription? _lspResponsesSubscription;

  CodeForgeController({this.lspConfig}) {
    if (lspConfig != null) {
      (() async {
        try {
          if (lspConfig is LspSocketConfig) {
            await (lspConfig! as LspSocketConfig).connect();
          }
          if (!lspConfig!.isIntialized) {
            await lspConfig!.initialize();
          }
          await Future.delayed(const Duration(milliseconds: 300));
          await lspConfig!.openDocument(openedFile!);
          _lspReady = true;
          await _fetchSemanticTokensFull();
        } catch (e) {
          debugPrint('Error initializing LSP: $e');
        } finally {
          _listeners.add(_highlightListener);
        }
      })();

      _lspResponsesSubscription = lspConfig!.responses.listen((data) async {
        try {
          if (data['method'] == 'workspace/applyEdit') {
            final Map<String, dynamic>? params = data['params'];
            if (params != null && params.isNotEmpty) {
              if (params.containsKey('edit')) {
                await applyWorkspaceEdit(params);
              }
            }
          }

          if (data['method'] == 'textDocument/publishDiagnostics') {
            final List<dynamic> rawDiagnostics =
                data['params']?['diagnostics'] ?? [];
            if (rawDiagnostics.isNotEmpty) {
              final List<LspErrors> errors = [];
              for (final item in rawDiagnostics) {
                if (item is! Map<String, dynamic>) continue;
                int severity = item['severity'] ?? 0;
                if (severity == 1 && lspConfig!.disableError) {
                  severity = 0;
                }
                if (severity == 2 && lspConfig!.disableWarning) {
                  severity = 0;
                }
                if (severity > 0) {
                  errors.add(
                    LspErrors(
                      severity: severity,
                      range: item['range'],
                      message: item['message'] ?? '',
                    ),
                  );
                }
              }
              if (!_isDisposed) diagnostics.value = errors;

              _codeActionTimer?.cancel();
              _codeActionTimer = Timer(
                const Duration(milliseconds: 250),
                () async {
                  if (errors.isEmpty) {
                    if (!_isDisposed) codeActions.value = null;
                    return;
                  }
                  int minStartLine = errors
                      .map((d) => d.range['start']?['line'] as int? ?? 0)
                      .reduce((a, b) => a < b ? a : b);
                  int minStartChar = errors
                      .map((d) => d.range['start']?['character'] as int? ?? 0)
                      .reduce((a, b) => a < b ? a : b);
                  int maxEndLine = errors
                      .map((d) => d.range['end']?['line'] as int? ?? 0)
                      .reduce((a, b) => a > b ? a : b);
                  int maxEndChar = errors
                      .map((d) => d.range['end']?['character'] as int? ?? 0)
                      .reduce((a, b) => a > b ? a : b);

                  try {
                    final actions = await lspConfig!.getCodeActions(
                      filePath: openedFile!,
                      startLine: minStartLine,
                      startCharacter: minStartChar,
                      endLine: maxEndLine,
                      endCharacter: maxEndChar,
                      diagnostics: rawDiagnostics.cast<Map<String, dynamic>>(),
                    );
                    if (!_isDisposed) codeActions.value = actions;
                  } catch (e) {
                    debugPrint('Error fetching code actions: $e');
                  }
                },
              );
            } else {
              if (!_isDisposed) diagnostics.value = [];
            }
          }
        } catch (e, st) {
          debugPrint('Error handling LSP response: $e\n$st');
        }
      });
    } else {
      _listeners.add(() {
        _previousValue = text;
        _prevSelection = selection;

        final cursorPosition = selection.extentOffset;
        final prefix = getCurrentWordPrefix(text, cursorPosition);
        if (_isTyping && selection.extentOffset > 0) {
          final regExp = RegExp(r'\b\w+\b');
          final List<String> words = regExp
              .allMatches(text)
              .map((m) => m.group(0)!)
              .toList();

          String currentWord = '';
          if (text.isNotEmpty) {
            final match = RegExp(r'\w+$').firstMatch(text);
            if (match != null) {
              currentWord = match.group(0)!;
            }
          }

          _suggestions.clear();

          for (final i in words) {
            if (!_suggestions.contains(i) && i != currentWord) {
              _suggestions.add(i);
            }
          }
          if (prefix.isNotEmpty) {
            _suggestions = _suggestions
                .where((s) => s.startsWith(prefix))
                .toList();
          }
          _sortSuggestions(prefix);
          final triggerChar = text[cursorPosition - 1];
          if (!_isAlpha(triggerChar)) {
            if (!_isDisposed) suggestions.value = null;
            return;
          }
          if (!_isDisposed) suggestions.value = _suggestions;
        } else {
          if (!_isDisposed) suggestions.value = null;
        }
      });
    }
  }

  Future<void> _highlightListener() async {
    if (text != _previousValue && _lspReady) {
      await lspConfig!.updateDocument(openedFile!, text);
      _scheduleSemantictokenRefresh();
      if (text.length == _previousValue.length + 1 &&
          selection.extentOffset == _prevSelection.extentOffset + 1 &&
          _isTyping) {
        final cursorPosition = selection.extentOffset;
        final line = getLineAtOffset(cursorPosition);
        final lineStartOffset = getLineStartOffset(line);
        final character = cursorPosition - lineStartOffset;
        final prefix = getCurrentWordPrefix(text, cursorPosition);
        _suggestions = await lspConfig!.getCompletions(
          openedFile!,
          getLineAtOffset(selection.extentOffset),
          character,
        );
        _sortSuggestions(prefix);
        final triggerChar = text[cursorPosition - 1];
        if (!_isAlpha(triggerChar)) {
          if (!_isDisposed) suggestions.value = null;
          return;
        }
        if (!_isDisposed) suggestions.value = _suggestions;
      } else {
        if (!_isDisposed) suggestions.value = null;
      }
    }
    _previousValue = text;
    _prevSelection = selection;
  }

  final ValueNotifier<(List<LspSemanticToken>?, int)> semanticTokens =
      ValueNotifier((null, 0));
  final ValueNotifier<List<dynamic>?> suggestions = ValueNotifier(null);
  final ValueNotifier<List<LspErrors>> diagnostics = ValueNotifier([]);
  final ValueNotifier<List<dynamic>?> codeActions = ValueNotifier(null);

  /// Configuration for Language Server Protocol integration.
  ///
  /// Enables advanced features like hover documentation, diagnostics,
  /// and semantic highlighting.
  LspConfig? lspConfig;

  /// Open a file using the controller API instead of passing `filePath` parameter to [CodeForge]
  set openedFile(String? file) {
    _openedFile = file;
    if (openedFile != null) {
      text = File(_openedFile!).readAsStringSync();
    }
  }

  /// Currently opened file.
  String? get openedFile => _openedFile;

  VoidCallback? manualAiCompletion, userCodeAction;

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

  /// Callback to get the LSP code action at the current cursor position
  void getCodeAction() {
    userCodeAction?.call();
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
    if (readOnly) return;
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
    if (readOnly) return;
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
    _isTyping = false;
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
    _isTyping = false; // Explicit selection change resets typing state

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
    _isTyping = false;

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
    if (_isDisposed) return;
    for (final listener in _listeners) {
      listener();
    }
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    if (readOnly) return;

    bool typingDetected = false;

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
        if (delta.textInserted.isNotEmpty && _isAlpha(delta.textInserted)) {
          typingDetected = true;
        }
        _handleInsertion(
          delta.insertionOffset,
          delta.textInserted,
          delta.selection,
        );
      } else if (delta is TextEditingDeltaDeletion) {
        _handleDeletion(delta.deletedRange, delta.selection);
      } else if (delta is TextEditingDeltaReplacement) {
        if (delta.replacementText.isNotEmpty &&
            _isAlpha(delta.replacementText)) {
          typingDetected = true;
        }
        _handleReplacement(
          delta.replacedRange,
          delta.replacementText,
          delta.selection,
        );
      }
    }

    _isTyping = typingDetected;

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
    if (readOnly) return;

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
      final newPosition = text.length;
      selection = TextSelection.collapsed(offset: newPosition);
      return;
    }

    if (replaceTypedChar) {
      final ropeText = _rope.getText();
      final prefix = getCurrentWordPrefix(ropeText, safePosition);
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
    if (readOnly) return;
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
  void replaceRange(
    int start,
    int end,
    String replacement, {
    bool preserveOldCursor = false,
  }) {
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
    TextSelection newSelection;
    if (preserveOldCursor) {
      final delta = replacement.length - (safeEnd - safeStart);

      int mapOffset(int offset) {
        if (offset <= safeStart) return offset;
        if (offset >= safeEnd) return (offset + delta).clamp(0, _rope.length);
        final relative = offset - safeStart;
        final mapped = safeStart + relative.clamp(0, replacement.length);
        return mapped.clamp(0, _rope.length);
      }

      final base = mapOffset(selectionBefore.baseOffset);
      final extent = mapOffset(selectionBefore.extentOffset);
      newSelection = TextSelection(baseOffset: base, extentOffset: extent);
    } else {
      newSelection = TextSelection.collapsed(
        offset: safeStart + replacement.length,
      );
    }
    _selection = newSelection;
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

  /// Search the document for occurrences of [word] and add highlight ranges.
  ///
  /// - `word`: The substring to search for. If empty, existing highlights
  ///   are cleared and listeners are notified.
  /// - `highlightStyle`: Optional style applied to each found match. If null,
  ///   a default amber background style is used.
  /// - `matchCase`: When true the search is case-sensitive; otherwise the
  ///   search is performed case-insensitively.
  /// - `matchWholeWord`: When true matches are considered valid only when the
  ///   matched substring is not adjacent to other word characters (letters,
  ///   digits, or underscore).
  ///
  /// Behavior:
  /// Clears existing `searchHighlights`, scans the document for matches
  /// according to the provided options, appends a `SearchHighlight` for each
  /// match, sets `searchHighlightsChanged = true` and calls
  /// `notifyListeners()` to request a repaint/update.
  void findWord(
    String word, {
    bool matchCase = false,
    bool matchWholeWord = false,
  }) {
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
          SearchHighlight(
            start: index,
            end: index + word.length,
            isCurrentMatch: true,
          ),
        );
      }

      offset = index + 1;
    }

    searchHighlightsChanged = true;
    notifyListeners();
  }

  /// Search the document using a regular expression and add highlight ranges
  /// for each match.
  ///
  /// - `regex`: The regular expression used to find matches in the current
  ///   document text. All matches returned by `regex.allMatches` are added as
  ///   highlights.
  /// - `highlightStyle`: Optional `TextStyle` applied to each match. If null,
  ///   a default amber background style is used.
  ///
  /// Behavior:
  /// Clears existing `searchHighlights`, applies [regex] to the document
  /// text, appends a `SearchHighlight` for every match and then sets
  /// `searchHighlightsChanged = true` and calls `notifyListeners()`.
  void findRegex(RegExp regex) {
    searchHighlights.clear();

    final searchText = text;
    final matches = regex.allMatches(searchText);

    for (final match in matches) {
      searchHighlights.add(
        SearchHighlight(
          start: match.start,
          end: match.end,
          isCurrentMatch: true,
        ),
      );
    }

    searchHighlightsChanged = true;
    notifyListeners();
  }

  /// Indent the current selection or insert an indent at the caret.
  ///
  /// If a range is selected, each line in the selected block is prefixed
  /// with three spaces. The selection is adjusted to account for the added
  /// characters. If there is no selection (collapsed caret), three spaces
  /// are inserted at the caret position.
  ///
  /// The method uses `replaceRange` and `setSelectionSilently` to update the
  /// document and selection without triggering external selection side
  /// effects.
  void indent() {
    if (selection.baseOffset != selection.extentOffset) {
      final selStart = selection.start;
      final selEnd = selection.end;

      final lineStart = text.lastIndexOf('\n', selStart - 1) + 1;
      int lineEnd = text.indexOf('\n', selEnd);
      if (lineEnd == -1) lineEnd = text.length;

      final selectedBlock = text.substring(lineStart, lineEnd);
      final indentedBlock = selectedBlock
          .split('\n')
          .map((line) => '   $line')
          .join('\n');

      final lines = selectedBlock.split('\n');
      final addedChars = 3 * lines.length;
      final newSelection = TextSelection(
        baseOffset: selection.baseOffset + 3,
        extentOffset: selection.extentOffset + addedChars,
      );

      replaceRange(lineStart, lineEnd, indentedBlock);
      setSelectionSilently(newSelection);
    } else {
      insertAtCurrentCursor('   ');
    }
  }

  /// Remove indentation from the current selection or the current line.
  ///
  /// If a range is selected, the method attempts to remove up to three
  /// leading spaces from each line in the selection (or removes the leading
  /// contiguous spaces if fewer than three). The selection is adjusted to
  /// reflect the removed characters. If there is no selection, the current
  /// line is unindented and the caret is moved appropriately.
  ///
  /// Uses `replaceRange` and `setSelectionSilently` to update the document
  /// and selection without causing external selection side effects.
  void unindent() {
    if (selection.baseOffset != selection.extentOffset) {
      final selStart = selection.start;
      final selEnd = selection.end;

      final lineStart = text.lastIndexOf('\n', selStart - 1) + 1;
      int lineEnd = text.indexOf('\n', selEnd);
      if (lineEnd == -1) lineEnd = text.length;

      final selectedBlock = text.substring(lineStart, lineEnd);
      final unindentedBlock = selectedBlock
          .split('\n')
          .map(
            (line) => line.startsWith('   ')
                ? line.substring(3)
                : line.replaceFirst(RegExp(r'^ +'), ''),
          )
          .join('\n');

      final lines = selectedBlock.split('\n');
      int removedChars = 0;
      for (final line in lines) {
        if (line.startsWith('   ')) {
          removedChars += 3;
        } else {
          removedChars += RegExp(r'^ +').stringMatch(line)?.length ?? 0;
        }
      }

      final newSelection = TextSelection(
        baseOffset:
            selection.baseOffset -
            (lines.first.startsWith('   ')
                ? 3
                : (RegExp(r'^ +').stringMatch(lines.first)?.length ?? 0)),
        extentOffset: selection.extentOffset - removedChars,
      );

      replaceRange(lineStart, lineEnd, unindentedBlock);
      setSelectionSilently(newSelection);
    } else {
      final caret = selection.start;
      final prevNewline = text.lastIndexOf('\n', caret - 1);
      final lineStart = prevNewline == -1 ? 0 : prevNewline + 1;
      final nextNewline = text.indexOf('\n', caret);
      final lineEnd = nextNewline == -1 ? text.length : nextNewline;
      final line = text.substring(lineStart, lineEnd);

      int removeCount = 0;
      if (line.startsWith('   ')) {
        removeCount = 3;
      } else {
        removeCount = RegExp(r'^ +').stringMatch(line)?.length ?? 0;
      }

      final newLine = line.substring(removeCount);
      final newOffset = caret - removeCount > lineStart
          ? caret - removeCount
          : lineStart;

      replaceRange(lineStart, lineEnd, newLine);
      setSelectionSilently(TextSelection.collapsed(offset: newOffset));
    }
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

  /// Returns the identifier prefix immediately preceding the given offset.
  ///
  /// This method extracts a contiguous sequence of identifier characters
  /// (ASCII letters, digits and underscore) that ends at `offset` (or at the
  /// current buffer cursor when a buffer is active). The extracted prefix is
  /// only returned if its first character is a letter (A–Z or a–z) or an
  /// underscore; prefixes that start with a digit are considered invalid and
  /// yield an empty string.
  ///
  /// Behavior details:
  /// - If `isBufferActive` is true, the method uses `bufferLineText` and
  ///   `bufferCursorColumn` instead of the provided `text` and `offset`.
  /// - `offset` is clamped to the range [0, text.length] before processing.
  /// - If the effective cursor/column is out of range (<= 0 or greater than
  ///   the line length) the method returns an empty string.
  /// - Identifier characters considered: '0'–'9', 'A'–'Z', 'a'–'z', and '_'.
  /// - The first character of the returned prefix must be a letter ('A'–'Z' or
  ///   'a'–'z') or an underscore; otherwise an empty string is returned.
  /// - If there is no identifier character immediately before the offset, or
  ///   the computed start equals the offset, an empty string is returned.
  ///
  /// Parameters:
  /// - text: The full text to inspect (ignored when a buffer is active).
  /// - offset: The exclusive character index (cursor position) in `text` at
  ///   which to look backwards for an identifier prefix.
  ///
  /// Returns:
  /// - The identifier prefix ending at the given offset (or buffer cursor),
  ///   or an empty string if no valid prefix exists.
  ///
  /// Examples:
  /// ```dart
  ///  getCurrentWordPrefix("hello world", 5) -> "hello"
  ///  getCurrentWordPrefix("123abc", 6) -> ""  (prefix starts with a digit)
  /// ```
  /// - When buffer is active, the method behaves the same but uses the buffer's
  ///   current line and column instead of `text`/`offset`.
  String getCurrentWordPrefix(String text, int offset) {
    final safeOffset = offset.clamp(0, text.length);
    if (isBufferActive) {
      final lineText = bufferLineText ?? '';
      final col = bufferCursorColumn;
      if (col <= 0) return '';
      if (col > lineText.length) return '';
      int i = col - 1;
      while (i >= 0) {
        final code = lineText.codeUnitAt(i);
        final isIdentChar =
            (code >= 48 && code <= 57) ||
            (code >= 65 && code <= 90) ||
            (code >= 97 && code <= 122) ||
            code == 95;
        if (!isIdentChar) break;
        i--;
      }
      final start = i + 1;
      if (start >= col) return '';
      final firstCode = lineText.codeUnitAt(start);
      final isStartOk =
          (firstCode >= 65 && firstCode <= 90) ||
          (firstCode >= 97 && firstCode <= 122) ||
          firstCode == 95;
      if (!isStartOk) return '';
      return lineText.substring(start, col);
    }

    if (safeOffset == 0) return '';
    int i = safeOffset - 1;
    while (i >= 0) {
      final code = text.codeUnitAt(i);
      final isIdentChar =
          (code >= 48 && code <= 57) ||
          (code >= 65 && code <= 90) ||
          (code >= 97 && code <= 122) ||
          code == 95;
      if (!isIdentChar) break;
      i--;
    }
    final start = i + 1;
    if (start >= safeOffset) return '';
    final firstCode = text.codeUnitAt(start);
    final isStartOk =
        (firstCode >= 65 && firstCode <= 90) ||
        (firstCode >= 97 && firstCode <= 122) ||
        firstCode == 95;
    if (!isStartOk) return '';
    return text.substring(start, safeOffset);
  }

  /// Disposes of the controller and releases resources.
  ///
  /// Call this method when the controller is no longer needed to prevent
  /// memory leaks.
  void dispose() {
    _isDisposed = true;
    _semanticTokenTimer?.cancel();
    _flushTimer?.cancel();
    _codeActionTimer?.cancel();
    _lspResponsesSubscription?.cancel();
    _listeners.clear();
    connection?.close();
  }

  /// Applies a workspace edit or code action payload coming from the LSP.
  ///
  /// The method understands several forms: a map with an `edit` containing
  /// `changes`, `documentChanges`, a raw list of edits, or a command. It will
  /// apply text edits to the currently opened file and update the LSP server
  /// document afterwards.
  Future<void> applyWorkspaceEdit(dynamic action) async {
    if (openedFile == null) return;
    final fileUri = Uri.file(openedFile!).toString();

    if (action is Map && action.containsKey('command')) {
      final String command = action['command'];
      final List args = action['arguments'] ?? [];
      await lspConfig?.executeCommand(command, args);
      return;
    } else if (action is Map &&
        action.containsKey('edit') &&
        (action['edit'] as Map).containsKey('changes')) {
      final Map changes = action['edit']['changes'] as Map;
      if (changes.containsKey(fileUri)) {
        final List edits = List.from(changes[fileUri] as List);
        final converted = <Map<String, dynamic>>[];
        for (final e in edits) {
          try {
            final start = e['range']?['start'];
            final end = e['range']?['end'];
            if (start == null || end == null) continue;
            final startOffset =
                getLineStartOffset(start['line'] as int) +
                (start['character'] as int);
            final endOffset =
                getLineStartOffset(end['line'] as int) +
                (end['character'] as int);
            final newText = e['newText'] as String? ?? '';
            converted.add({
              'start': startOffset,
              'end': endOffset,
              'newText': newText,
            });
          } catch (_) {
            continue;
          }
        }
        converted.sort(
          (a, b) => (b['start'] as int).compareTo(a['start'] as int),
        );
        for (final ce in converted) {
          replaceRange(
            ce['start'] as int,
            ce['end'] as int,
            ce['newText'] as String,
            preserveOldCursor: true,
          );
        }
        if (lspConfig != null) {
          await lspConfig!.updateDocument(openedFile!, text);
        }
      }
      return;
    } else if (action is Map &&
        action.containsKey('documentChanges') &&
        action['documentChanges'] is List) {
      final List docChanges = List.from(action['documentChanges'] as List);
      for (final dc in docChanges) {
        if (dc is Map) {
          final td = dc['textDocument'];
          final uri = td != null ? td['uri'] as String? : null;
          if (uri == fileUri && dc.containsKey('edits')) {
            final List edits = List.from(dc['edits'] as List);
            final converted = <Map<String, dynamic>>[];
            for (final e in edits) {
              try {
                final start = e['range']?['start'];
                final end = e['range']?['end'];
                if (start == null || end == null) continue;
                final int startOffset =
                    getLineStartOffset(start['line'] as int) +
                    (start['character'] as int);
                final int endOffset =
                    getLineStartOffset(end['line'] as int) +
                    (end['character'] as int);
                final String newText = e['newText'] as String? ?? '';
                converted.add({
                  'start': startOffset,
                  'end': endOffset,
                  'newText': newText,
                });
              } catch (_) {
                continue;
              }
            }
            converted.sort(
              (a, b) => (b['start'] as int).compareTo(a['start'] as int),
            );
            for (final ce in converted) {
              replaceRange(
                ce['start'] as int,
                ce['end'] as int,
                ce['newText'] as String,
                preserveOldCursor: true,
              );
            }
            if (lspConfig != null) {
              await lspConfig!.updateDocument(openedFile!, text);
            }
          }
        }
      }
      return;
    } else if (action is List) {
      final converted = <Map<String, dynamic>>[];
      try {
        for (Map<String, dynamic> item in action) {
          if (!(item.containsKey('newText') && item.containsKey('range'))) {
            return;
          }
          final start = item['range']?['start'];
          final end = item['range']?['end'];
          if (start == null || end == null) return;
          final startOffset =
              getLineStartOffset(start['line'] as int) +
              (start['character'] as int);
          final endOffset =
              getLineStartOffset(end['line'] as int) +
              (end['character'] as int);
          final newText = item['newText'] as String? ?? '';
          converted.add({
            'start': startOffset,
            'end': endOffset,
            'newText': newText,
          });
        }
      } catch (_) {
        return;
      }
      converted.sort(
        (a, b) => (b['start'] as int).compareTo(a['start'] as int),
      );
      for (final ce in converted) {
        replaceRange(
          ce['start'] as int,
          ce['end'] as int,
          ce['newText'] as String,
          preserveOldCursor: true,
        );
      }
      if (lspConfig != null) {
        await lspConfig!.updateDocument(openedFile!, text);
      }
    }
  }

  bool _isAlpha(String s) {
    if (s.isEmpty) return false;
    final code = s.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  Future<void> _fetchSemanticTokensFull() async {
    if (lspConfig == null) return;

    try {
      final tokens = await lspConfig!.getSemanticTokensFull(openedFile!);
      if (!_isDisposed) {
        semanticTokens.value = (tokens, _semanticTokensVersion++);
      }
    } catch (e) {
      debugPrint('Error fetching semantic tokens: $e');
    }
  }

  void _scheduleSemantictokenRefresh() {
    _semanticTokenTimer?.cancel();
    _semanticTokenTimer = Timer(_semanticTokenDebounce, () async {
      await _fetchSemanticTokensFull();
    });
  }

  void _sortSuggestions(String prefix) {
    _suggestions.sort((a, b) {
      final aLabel = a is LspCompletion ? a.label : a.toString();
      final bLabel = b is LspCompletion ? b.label : b.toString();
      final aScore = _scoreMatch(aLabel, prefix);
      final bScore = _scoreMatch(bLabel, prefix);

      if (aScore != bScore) {
        return bScore.compareTo(aScore);
      }

      return aLabel.compareTo(bLabel);
    });
  }

  int _scoreMatch(String label, String prefix) {
    if (prefix.isEmpty) return 0;

    final lowerLabel = label.toLowerCase();
    final lowerPrefix = prefix.toLowerCase();

    if (!lowerLabel.contains(lowerPrefix)) return -1000000;

    int score = 0;

    if (label.startsWith(prefix)) {
      score += 100000;
    } else if (lowerLabel.startsWith(lowerPrefix)) {
      score += 50000;
    } else {
      score += 10000;
    }

    final matchIndex = lowerLabel.indexOf(lowerPrefix);
    score -= matchIndex * 100;

    if (matchIndex > 0) {
      final charBefore = label[matchIndex - 1];
      final matchChar = label[matchIndex];
      if (charBefore.toLowerCase() == charBefore &&
          matchChar.toUpperCase() == matchChar) {
        score += 5000;
      } else if (charBefore == '_' || charBefore == '-') {
        score += 5000;
      }
    }

    score -= label.length;

    return score;
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
    final currentLength = text.length;
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
