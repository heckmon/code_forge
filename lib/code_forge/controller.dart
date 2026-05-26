import 'dart:async';
import 'dart:io';

import '../code_forge.dart';
import 'rope.dart';

import 'package:flutter/foundation.dart';
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
class CodeForgeController with DeltaTextInputClient {
  static const _flushDelay = Duration(milliseconds: 100);
  static const _semanticTokenDebounce = Duration(milliseconds: 500);
  static const _documentColorDebounce = Duration(milliseconds: 50);
  static const _documentHighlightDebounce = Duration(milliseconds: 300);
  static const _cclsRefreshDebounce = Duration(milliseconds: 1000);
  final List<VoidCallback> _listeners = [];
  final _isMobile = Platform.isAndroid || Platform.isIOS;
  final List<LineDecoration> _lineDecorations = [];
  final List<GutterDecoration> _gutterDecorations = [];
  final List<({int line, int character})> _multiCursors = [];
  Timer? _flushTimer, _semanticTokenTimer, _codeActionTimer, _syncTimer;
  Timer? _documentColorTimer, _foldRangesTimer, _documentHighlightTimer;
  Timer? _cclsRefreshTimer, _debounceTimer;
  Timer? _lspTypingTimer;
  static const Duration _lspTypingDebounce = Duration(milliseconds: 300);
  String? _cachedText, _bufferLineText, _openedFile, _lastSentText;
  String _previousValue = "";
  TextSelection _prevSelection = const TextSelection.collapsed(offset: 0);
  bool _bufferDirty = false, bufferNeedsRepaint = false, selectionOnly = false;
  int _bufferLineRopeStart = 0, _bufferLineOriginalLength = 0;
  List<String>? _cachedBufferLines;
  int _cachedTextVersion = -1, _currentVersion = 0, _semanticTokensVersion = 0;
  int? dirtyLine, _bufferLineIndex;
  bool deleteFoldRangeOnDeletingFirstLine = false;
  TextSelection? _lastSentSelection;
  String? _lastTypedCharacter;
  UndoRedoController? _undoController;
  void Function(int lineNumber)? _toggleFoldCallback;
  void Function(int line)? _scrollToLineCallback;
  VoidCallback? _foldAllCallback, _unfoldAllCallback;
  bool _lspReady = false, _isTyping = false, _isDisposed = false;
  bool _usesCclsSemanticHighlight = false;
  TextRange _composing = TextRange.empty;
  TextSelection? _preComposingSelection;
  List<dynamic> _suggestions = [];
  StreamSubscription? _lspResponsesSubscription;
  Set<String> _wordCache = {};
  GhostText? _ghostText;
  final List<VirtualRemovedBlock> _virtualRemovedBlocks = [];
  List<InlayHint> _inlayHints = [];
  List<DocumentColor> _documentColors = [];
  List<DocumentHighlight> _documentHighlights = [];
  Map<int, FoldRange>? _lspFoldRanges;
  bool _lspFoldRangesAdjustedNotFetched = false;
  bool _inlayHintsVisible = false, documentHighlightsChanged = false;

  CodeForgeController({this.lspConfig}) {
    if (lspConfig != null) {
      (() async {
        try {
          if (lspConfig is LspSocketConfig) {
            await (lspConfig! as LspSocketConfig).connect();
          }
          if (!lspConfig!.isInitialized) {
            await lspConfig!.initialize();
          }
          if (openedFile != null) {
            await _openDocumentInLsp();
          }
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

          if (data['method'] == 'workspace/configuration') {
            final id = data['id'];
            await lspConfig!.sendResponse(id, [
              lspConfig!.workspaceConfiguration,
            ]);
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
              if (!_isDisposed) diagnosticsNotifier.value = errors;

              _codeActionTimer?.cancel();
              _codeActionTimer = Timer(
                const Duration(milliseconds: 250),
                    () async {
                  if (errors.isEmpty) {
                    if (!_isDisposed) codeActionsNotifier.value = null;
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
                    if (!_isDisposed) codeActionsNotifier.value = actions;
                  } catch (e) {
                    debugPrint('Error fetching code actions: $e');
                  }
                },
              );
            } else {
              if (!_isDisposed) diagnosticsNotifier.value = [];
            }
          }

          if (data['method'] == r'$ccls/publishSemanticHighlight') {
            final params = data['params'] as Map<String, dynamic>?;
            if (params != null) {
              final uri = params['uri'] as String?;
              final symbols = params['symbols'] as List<dynamic>?;

              if (uri != null &&
                  openedFile != null &&
                  uri.endsWith(openedFile!.split('/').last) &&
                  symbols != null) {
                _usesCclsSemanticHighlight = true;
                final tokens = _convertCclsSymbolsToTokens(symbols);
                if (!_isDisposed) {
                  semanticTokens.value = (tokens, _semanticTokensVersion++);
                }
              }
            }
          }
        } catch (e, st) {
          debugPrint('Error handling LSP response: $e\n$st');
        }
      });
    } else {
      _listeners.add(() async {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 200), () async {
          if (text != _previousValue) {
            _wordCache = await compute(CodeForgeController._extractWords, text);
          }
          _previousValue = text;
          _prevSelection = selection;

          final cursorPosition = selection.extentOffset;
          final prefix = getCurrentWordPrefix(text, cursorPosition);
          if (_isTyping && selection.extentOffset > 0) {
            String currentWord = '';
            if (text.isNotEmpty) {
              final match = RegExp(
                r'[\w\u0600-\u06FF\u08A0-\u08FF\u0590-\u05FF]+$',
              ).firstMatch(text.substring(0, cursorPosition));
              if (match != null) {
                currentWord = match.group(0)!;
              }
            }

            _suggestions.clear();

            for (final i in _wordCache) {
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
            final isTriggerChar = _isCompletionTriggerChar(triggerChar);
            final isAlphaChar = _isAlpha(triggerChar);

            if (!isTriggerChar && !isAlphaChar) {
              if (!_isDisposed) suggestionsNotifier.value = null;
              return;
            }
            if (!_isDisposed) suggestionsNotifier.value = _suggestions;
          } else {
            if (!_isDisposed) suggestionsNotifier.value = null;
          }
        });
      });
    }
  }

  Future<void> _openDocumentInLsp({String? previousFile}) async {
    if (lspConfig == null || !lspConfig!.isInitialized || openedFile == null) {
      return;
    }

    try {
      if (previousFile != null && previousFile != openedFile) {
        await lspConfig!.closeDocument(previousFile);
      }
      await lspConfig!.openDocument(openedFile!);
      _lspReady = true;
      await _fetchSemanticTokensFull();
      await fetchDocumentColors();
      await fetchLSPFoldRanges();
    } catch (e) {
      debugPrint('Error opening LSP document: $e');
    }
  }

  Future<void> _highlightListener() async {
    if (text != _previousValue && _lspReady) {
      final currentText = text;
      final currentSelection = selection;
      final isTypingLenMatch =
          currentText.length == _previousValue.length + 1 &&
              currentSelection.extentOffset == _prevSelection.extentOffset + 1 &&
              _isTyping;

      _lspTypingTimer?.cancel();
      _lspTypingTimer = Timer(_lspTypingDebounce, () async {
        if (_isDisposed || !_lspReady || openedFile == null) return;

        await lspConfig!.updateDocument(openedFile!, currentText);

        if (_usesCclsSemanticHighlight && !_isDisposed) {
          semanticTokens.value = (null, _semanticTokensVersion++);
          _scheduleCclsRefresh();
        }

        _scheduleSemantictokenRefresh();
        _scheduleDocumentColorRefresh();
        _scheduleFoldRangesRefresh();

        if (isTypingLenMatch) {
          final cursorPosition = currentSelection.extentOffset;
          final line = getLineAtOffset(cursorPosition);
          final lineStartOffset = getLineStartOffset(line);
          if (cursorPosition - 1 >= currentText.length) return;
          final character = cursorPosition - lineStartOffset;
          final prefix = getCurrentWordPrefix(currentText, cursorPosition);
          final triggerChar = currentText[cursorPosition - 1];
          final isTriggerChar = _isCompletionTriggerChar(triggerChar);
          final isAlphaChar = _isAlpha(triggerChar);

          if ((isTriggerChar || isAlphaChar) && !_isDisposed) {
            _suggestions = await lspConfig!.getCompletions(
              openedFile!,
              line,
              character,
            );
            _sortSuggestions(prefix);
            if (!_isDisposed) suggestionsNotifier.value = _suggestions;
          } else {
            if (!_isDisposed) suggestionsNotifier.value = null;
          }
        } else {
          if (!_isDisposed) suggestionsNotifier.value = null;
        }
      });
    }
    _previousValue = text;
    _prevSelection = selection;
  }

  void _scheduleDocumentColorRefresh() {
    _documentColorTimer?.cancel();
    _documentColorTimer = Timer(_documentColorDebounce, () {
      if (!_isDisposed && _lspReady) {
        fetchDocumentColors();
      }
    });
  }

  void _scheduleFoldRangesRefresh() {
    _foldRangesTimer?.cancel();
    _foldRangesTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_isDisposed && _lspReady) {
        fetchLSPFoldRanges();
      }
    });
  }

  void _scheduleCclsRefresh() {
    _cclsRefreshTimer?.cancel();
    _cclsRefreshTimer = Timer(_cclsRefreshDebounce, () async {
      if (!_isDisposed &&
          _lspReady &&
          _usesCclsSemanticHighlight &&
          openedFile != null) {
        await lspConfig!.saveDocument(openedFile!, text);
      }
    });
  }

  final ValueNotifier<(List<LspSemanticToken>?, int)> semanticTokens =
  ValueNotifier((null, 0));
  final ValueNotifier<List<dynamic>?> suggestionsNotifier = ValueNotifier(null);
  final ValueNotifier<int?> selectedSuggestionNotifier = ValueNotifier(null);
  final ValueNotifier<List<LspErrors>> diagnosticsNotifier = ValueNotifier([]);
  final ValueNotifier<List<dynamic>?> codeActionsNotifier = ValueNotifier(null);
  final ValueNotifier<LspSignatureHelps?> signatureNotifier = ValueNotifier(
    null,
  );

  /// The [FocusNode] instance, used to control editor focus
  FocusNode? focusNode;

  /// Configuration for Language Server Protocol integration.
  ///
  /// Enables advanced features like hover documentation, diagnostics,
  /// and semantic highlighting.
  LspConfig? lspConfig;

  /// Open a file using the controller API instead of passing `filePath` parameter to [CodeForge]
  set openedFile(String? file) {
    final previousFile = _openedFile;
    _openedFile = file;
    if (openedFile != null) {
      text = File(_openedFile!).readAsStringSync();
    }

    if (previousFile != openedFile &&
        lspConfig != null &&
        lspConfig!.isInitialized &&
        openedFile != null) {
      (() async {
        await _openDocumentInLsp(previousFile: previousFile);
      })();
    }
  }

  /// Returns the errors, warnings and info available in the editor as a [List<LspErrors>].
  /// Each [LspErrors] item holds the error severity, range and the message of each errors.
  List<LspErrors> get diagnostics => diagnosticsNotifier.value;

  /// The curent LSP suggestions shown in the editor.
  /// The vale is [List<dynamic>] because it can be either [String] or [LspCompletion].
  /// if the lspconfig is available and a valid server is configured, the [List<LspCompletion>] will be returned.
  /// else a [List<String>] with locally available words will be returned.
  List<dynamic>? get suggestions => suggestionsNotifier.value;

  /// The last character that was typed by the user.
  /// Returns an empty string if no character has been typed or if the last input was not a single character.
  String get lastTypedCharacter => _lastTypedCharacter ?? '';

  /// Currently opened file.
  String? get openedFile => _openedFile;

  VoidCallback? userCodeAction;

  Rope _rope = Rope('');
  TextSelection _selection = const TextSelection.collapsed(offset: 0);

  /// The text input connection to the platform.
  TextInputConnection? connection;

  /// The range of text that has been modified and needs reprocessing.
  TextRange? dirtyRegion;

  /// Map of all fold ranges detected in the document, keyed by start line index.
  ///
  /// This map is automatically populated based on code structure
  /// (braces, indentation, etc.) when folding is enabled.
  ///
  /// Use the setter to update this map — it rebuilds internal sorted caches
  /// used for O(log n) fold-region lookups.
  Map<int, FoldRange?> get foldings => _foldings;

  Map<int, FoldRange?> _foldings = {};
  List<int> _foldedStartsSorted = [];
  List<int> _foldedEndsSorted = [];

  /// Set fold ranges in the editor
  set foldings(Map<int, FoldRange?> value) {
    _foldings = value;
    _rebuildFoldSortedCache();
  }

  /// List of search highlights to display in the editor.
  ///
  /// Add [SearchHighlight] objects to this list to highlight
  /// search results or other text ranges.
  List<SearchHighlight> searchHighlights = [];

  /// Whether the search highlights have changed and need repaint.
  bool searchHighlightsChanged = false;

  /// Whether multi-cursor positions have changed and the editor needs repaint.
  bool multiCursorsChanged = false;

  /// Returns an unmodifiable view of the secondary cursor positions.
  List<({int line, int character})> get multiCursors =>
      List.unmodifiable(_multiCursors);

  /// Whether there are active secondary cursors.
  bool get hasMultiCursors => _multiCursors.isNotEmpty;

  /// Whether inlay hints have changed and need repaint
  bool inlayHintsChanged = false;

  /// Whether document colors have changed and need repaint
  bool documentColorsChanged = false;

  /// Whether decorations have changed and need repaint
  bool decorationsChanged = false;

  /// Returns an unmodifiable view of line decorations
  List<LineDecoration> get lineDecorations =>
      List.unmodifiable(_lineDecorations);

  /// Returns an unmodifiable view of gutter decorations
  List<GutterDecoration> get gutterDecorations =>
      List.unmodifiable(_gutterDecorations);

  /// Returns the current ghost text, if any
  GhostText? get ghostText => _ghostText;

  /// Returns the current virtual removed blocks (git diff deleted lines)
  List<VirtualRemovedBlock> get virtualRemovedBlocks =>
      List.unmodifiable(_virtualRemovedBlocks);

  /// Returns the current inlay hints
  List<InlayHint> get inlayHints => List.unmodifiable(_inlayHints);

  /// Returns whether inlay hints are currently visible
  bool get inlayHintsVisible => _inlayHintsVisible;

  /// Returns the current document colors
  List<DocumentColor> get documentColors => List.unmodifiable(_documentColors);

  /// Returns the current document highlights
  List<DocumentHighlight> get documentHighlights =>
      List.unmodifiable(_documentHighlights);

  /// LSP-provided fold ranges, or null if not available.
  /// If available, these should be used instead of the built-in fold range algorithm.
  Map<int, FoldRange>? get lspFoldRanges => _lspFoldRanges;

  /// Returns true if LSP fold ranges were adjusted (not fetched fresh).
  /// When true, the render object should not clear its fold cache.
  bool get lspFoldRangesWereAdjusted => _lspFoldRangesAdjustedNotFetched;

  /// Returns the index of the currently selected seuggestion if an LSP/normal suggestion is available.
  ///
  /// Note: This will only work on mobile devices.
  int? get currentlySelectedSuggestion => selectedSuggestionNotifier.value;
  set currentlySelectedSuggestion(int? value) =>
      selectedSuggestionNotifier.value = value;

  /// Adds a secondary cursor at the given [line] and [character] position.
  ///
  /// The position is clamped to valid bounds. Duplicate positions
  /// (including the primary cursor) are ignored.
  void addMultiCursor(int line, int character) {
    final clampedLine = line.clamp(0, lineCount - 1);
    final lineText = getLineText(clampedLine);
    final clampedChar = character.clamp(0, lineText.length);

    for (final c in _multiCursors) {
      if (c.line == clampedLine && c.character == clampedChar) return;
    }

    final primaryLine = getLineAtOffset(selection.extentOffset);
    final primaryChar =
        selection.extentOffset - getLineStartOffset(primaryLine);
    if (clampedLine == primaryLine && clampedChar == primaryChar) return;

    _multiCursors.add((line: clampedLine, character: clampedChar));
    multiCursorsChanged = true;
    notifyListeners();
  }

  /// Removes all secondary cursors, keeping only the primary cursor.
  void clearMultiCursors() {
    if (_multiCursors.isEmpty) return;
    _multiCursors.clear();
    multiCursorsChanged = true;
    notifyListeners();
  }

  /// Moves every secondary cursor one character to the left.
  ///
  /// When [isShiftPressed] is true the secondary cursors are cleared because
  /// extending a multi-cursor selection is not supported.
  void moveMultiCursorsLeft({bool isShiftPressed = false}) {
    if (_multiCursors.isEmpty) return;
    if (isShiftPressed) {
      clearMultiCursors();
      return;
    }
    final updated = <({int line, int character})>[];
    for (final cursor in _multiCursors) {
      final offset = _multiCursorToOffset(cursor);
      final newOffset = (offset - 1).clamp(0, _rope.length);
      final newLine = _rope.getLineAtOffset(newOffset);
      final newLineStart = _rope.getLineStartOffset(newLine);
      updated.add((line: newLine, character: newOffset - newLineStart));
    }
    _updateMultiCursorsFromList(updated);
  }

  /// Moves every secondary cursor one character to the right.
  ///
  /// When [isShiftPressed] is true the secondary cursors are cleared.
  void moveMultiCursorsRight({bool isShiftPressed = false}) {
    if (_multiCursors.isEmpty) return;
    if (isShiftPressed) {
      clearMultiCursors();
      return;
    }
    final updated = <({int line, int character})>[];
    for (final cursor in _multiCursors) {
      final offset = _multiCursorToOffset(cursor);
      final newOffset = (offset + 1).clamp(0, _rope.length);
      final newLine = _rope.getLineAtOffset(newOffset);
      final newLineStart = _rope.getLineStartOffset(newLine);
      updated.add((line: newLine, character: newOffset - newLineStart));
    }
    _updateMultiCursorsFromList(updated);
  }

  /// Moves every secondary cursor up one line, maintaining its column.
  ///
  /// Folded regions are skipped exactly as they are for the primary cursor.
  /// When [isShiftPressed] is true the secondary cursors are cleared.
  void moveMultiCursorsUp({bool isShiftPressed = false}) {
    if (_multiCursors.isEmpty) return;
    if (isShiftPressed) {
      clearMultiCursors();
      return;
    }
    final updated = <({int line, int character})>[];
    for (final cursor in _multiCursors) {
      final cursorLine = cursor.line.clamp(0, lineCount - 1);
      if (cursorLine <= 0) {
        updated.add((line: 0, character: 0));
        continue;
      }
      int targetLine = cursorLine - 1;
      while (targetLine > 0 && _isLineInFoldedRegion(targetLine)) {
        targetLine--;
      }
      if (_isLineInFoldedRegion(targetLine)) {
        targetLine = _getFoldStartForLine(targetLine) ?? 0;
      }
      final prevLineText = getLineText(targetLine);
      final newChar = cursor.character.clamp(0, prevLineText.length);
      updated.add((line: targetLine, character: newChar));
    }
    _updateMultiCursorsFromList(updated);
  }

  /// Moves every secondary cursor down one line, maintaining its column.
  ///
  /// Folded regions are skipped exactly as they are for the primary cursor.
  /// When [isShiftPressed] is true the secondary cursors are cleared.
  void moveMultiCursorsDown({bool isShiftPressed = false}) {
    if (_multiCursors.isEmpty) return;
    if (isShiftPressed) {
      clearMultiCursors();
      return;
    }
    final updated = <({int line, int character})>[];
    for (final cursor in _multiCursors) {
      final cursorLine = cursor.line.clamp(0, lineCount - 1);
      if (cursorLine >= lineCount - 1) {
        final lastLineText = getLineText(lineCount - 1);
        updated.add((line: lineCount - 1, character: lastLineText.length));
        continue;
      }
      final foldAtCurrent = _getFoldRangeAtCurrentLine(cursorLine);
      int targetLine;
      if (foldAtCurrent != null && foldAtCurrent.isFolded) {
        targetLine = foldAtCurrent.endIndex + 1;
      } else {
        targetLine = cursorLine + 1;
      }
      while (targetLine < lineCount && _isLineInFoldedRegion(targetLine)) {
        final foldStart = _getFoldStartForLine(targetLine);
        if (foldStart != null) {
          final fold = foldings[foldStart] ?? FoldRange(targetLine, targetLine);
          targetLine = fold.endIndex + 1;
        } else {
          targetLine++;
        }
      }
      if (targetLine >= lineCount) {
        final lastLineText = getLineText(lineCount - 1);
        updated.add((line: lineCount - 1, character: lastLineText.length));
        continue;
      }
      final nextLineText = getLineText(targetLine);
      final newChar = cursor.character.clamp(0, nextLineText.length);
      updated.add((line: targetLine, character: newChar));
    }
    _updateMultiCursorsFromList(updated);
  }

  void _updateMultiCursorsFromList(
      List<({int line, int character})> positions,
      ) {
    _multiCursors.clear();
    final primaryLine = getLineAtOffset(selection.extentOffset);
    final primaryChar =
        selection.extentOffset - getLineStartOffset(primaryLine);
    final seen = <({int line, int character})>{};
    for (final pos in positions) {
      if (pos.line == primaryLine && pos.character == primaryChar) continue;
      if (seen.contains(pos)) continue;
      seen.add(pos);
      _multiCursors.add(pos);
    }
    multiCursorsChanged = true;
    notifyListeners();
  }

  /// Performs backspace at all cursor positions (primary + secondary).
  void backspaceAtAllCursors() {
    if (readOnly || _multiCursors.isEmpty) {
      return;
    }

    _flushBuffer();

    final selectionBefore = _selection;
    final primaryOffset = selection.extentOffset.clamp(0, _rope.length);
    final offsets = <int>[primaryOffset];
    for (final c in _multiCursors) {
      offsets.add(_multiCursorToOffset(c).clamp(0, _rope.length));
    }

    final uniqueOffsets = offsets.toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    final compound = _undoController?.beginCompoundOperation();

    for (final offset in uniqueOffsets) {
      if (offset > 0) {
        final deleteStart = (offset - 1).clamp(0, _rope.length);
        final deletedChar = _rope.substring(deleteStart, offset);
        _rope.delete(deleteStart, offset);
        _currentVersion++;

        _recordDeletion(
          deleteStart,
          deletedChar,
          selectionBefore,
          TextSelection.collapsed(offset: deleteStart),
        );
      }
    }

    compound?.end();

    int primaryShift = 0;
    for (final o in uniqueOffsets) {
      if (o <= primaryOffset && o > 0) {
        primaryShift += 1;
      }
    }
    _selection = TextSelection.collapsed(
      offset: (primaryOffset - primaryShift).clamp(0, _rope.length),
    );

    _multiCursors.clear();
    final sortedAsc = uniqueOffsets.reversed.toList();
    for (int i = 0; i < sortedAsc.length; i++) {
      final origOffset = sortedAsc[i];
      if (origOffset <= 0) continue;
      int shift = 0;
      for (int j = 0; j <= i; j++) {
        if (sortedAsc[j] > 0) shift++;
      }
      final newOffset = (origOffset - shift).clamp(0, _rope.length);
      final primaryNewOffset = (primaryOffset - primaryShift).clamp(
        0,
        _rope.length,
      );
      if (newOffset == primaryNewOffset) continue;
      final newLine = _rope.getLineAtOffset(newOffset);
      final newLineStart = _rope.getLineStartOffset(newLine);
      final newChar = newOffset - newLineStart;
      _multiCursors.add((line: newLine, character: newChar));
    }

    multiCursorsChanged = true;
    dirtyRegion = TextRange(start: 0, end: _rope.length);
    _syncToConnection();
    notifyListeners();
  }

  /// Inserts [textToInsert] at all cursor positions (primary + secondary).
  ///
  /// Insertions are performed from the last (highest-offset) cursor to the
  /// first so that earlier offsets are not invalidated by later insertions.
  /// After insertion, all cursor positions are updated to sit after the
  /// inserted text.
  void insertAtAllCursors(String textToInsert) {
    if (readOnly || _multiCursors.isEmpty) {
      return;
    }

    _flushBuffer();

    final selectionBefore = _selection;
    final primaryOffset = selection.extentOffset.clamp(0, _rope.length);
    final offsets = <int>[primaryOffset];
    for (final c in _multiCursors) {
      offsets.add(_multiCursorToOffset(c).clamp(0, _rope.length));
    }

    final uniqueOffsets = offsets.toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    final compound = _undoController?.beginCompoundOperation();

    for (final offset in uniqueOffsets) {
      final safeOffset = offset.clamp(0, _rope.length);
      _rope.insert(safeOffset, textToInsert);
      _currentVersion++;

      _recordInsertion(
        safeOffset,
        textToInsert,
        selectionBefore,
        TextSelection.collapsed(offset: safeOffset + textToInsert.length),
      );
    }

    compound?.end();

    int primaryShift = 0;
    for (final o in uniqueOffsets) {
      if (o <= primaryOffset) {
        primaryShift += textToInsert.length;
      }
    }
    _selection = TextSelection.collapsed(
      offset: (primaryOffset + primaryShift).clamp(0, _rope.length),
    );

    _multiCursors.clear();
    final sortedAsc = uniqueOffsets.reversed.toList();
    for (int i = 0; i < sortedAsc.length; i++) {
      final newOffset = sortedAsc[i] + (i + 1) * textToInsert.length;
      final safeNewOffset = newOffset.clamp(0, _rope.length);
      final newLine = _rope.getLineAtOffset(safeNewOffset);
      final newLineStart = _rope.getLineStartOffset(newLine);
      final newChar = safeNewOffset - newLineStart;
      final primaryNewOffset = primaryOffset + primaryShift;

      if (safeNewOffset == primaryNewOffset) continue;
      _multiCursors.add((line: newLine, character: newChar));
    }

    multiCursorsChanged = true;
    dirtyRegion = TextRange(start: 0, end: _rope.length);
    _syncToConnection();
    notifyListeners();
  }

  /// Clear LSP suggestions, hover info, code actions and signature help.
  void clearAllSuggestions() {
    suggestionsNotifier.value = null;
    selectedSuggestionNotifier.value = null;
    signatureNotifier.value = null;
    codeActionsNotifier.value = null;
  }

  /// Accepts the currently selected suggestion and inserts it at the cursor position.
  ///
  /// For mobile devices, uses [currentlySelectedSuggestion] to determine which
  /// suggestion to accept. For desktop/non-mobile, uses the provided [selectedIndex].
  ///
  /// The method handles different suggestion types:
  /// - [LspCompletion]: Uses the label property
  /// - [Map]: Uses 'insertText' or 'label' key
  /// - [String]: Uses the string directly
  ///
  /// After accepting, clears the suggestions and resets the selection index.
  ///
  /// Parameters:
  /// - [selectedIndex]: The index of the selected suggestion for desktop/non-mobile.
  ///   Defaults to 0 if not provided.
  void acceptSuggestion({int selectedIndex = 0}) {
    final suggestions = suggestionsNotifier.value;
    if (suggestions == null || suggestions.isEmpty) return;

    final isMobile = Platform.isAndroid || Platform.isIOS;
    final safeSelectedIndex = isMobile
        ? (currentlySelectedSuggestion ?? 0).clamp(0, suggestions.length - 1)
        : selectedIndex.clamp(0, suggestions.length - 1);
    final selected = suggestions[safeSelectedIndex];
    final insertText = _extractSuggestionText(selected);

    if (insertText.isNotEmpty) {
      insertAtCurrentCursor(insertText, replaceTypedChar: true);
    }

    suggestionsNotifier.value = null;
    currentlySelectedSuggestion = 0;
  }

  String _extractSuggestionText(dynamic suggestion) {
    if (suggestion is LspCompletion) {
      return suggestion.label;
    }
    if (suggestion is Map) {
      final dynamic insertText =
          suggestion['insertText'] ??
              suggestion['value'] ??
              suggestion['label'];
      return insertText is String ? insertText : '';
    }
    if (suggestion is String) {
      return suggestion;
    }

    final dynamic dynamicSuggestion = suggestion;
    try {
      final dynamic insertText = dynamicSuggestion.insertText;
      if (insertText is String && insertText.isNotEmpty) return insertText;
    } catch (_) {}
    try {
      final dynamic value = dynamicSuggestion.value;
      if (value is String && value.isNotEmpty) return value;
    } catch (_) {}
    try {
      final dynamic label = dynamicSuggestion.label;
      if (label is String) return label;
    } catch (_) {}
    return '';
  }

  /// Adds a line decoration to the editor.
  ///
  /// Line decorations can highlight code ranges with background colors,
  /// borders, or underlines. Useful for git diff, code coverage, etc.
  ///
  /// Example - Git diff added lines:
  /// ```dart
  /// controller.addLineDecoration(LineDecoration(
  ///   id: 'git-add-1',
  ///   startLine: 10,
  ///   endLine: 15,
  ///   type: LineDecorationType.background,
  ///   color: Colors.green.withOpacity(0.2),
  /// ));
  /// ```
  void addLineDecoration(LineDecoration decoration) {
    _lineDecorations.removeWhere((d) => d.id == decoration.id);
    _lineDecorations.add(decoration);
    _lineDecorations.sort((a, b) => a.priority.compareTo(b.priority));
    decorationsChanged = true;
    notifyListeners();
  }

  /// Adds multiple line decorations at once.
  ///
  /// More efficient than calling [addLineDecoration] multiple times.
  void addLineDecorations(List<LineDecoration> decorations) {
    for (final decoration in decorations) {
      _lineDecorations.removeWhere((d) => d.id == decoration.id);
      _lineDecorations.add(decoration);
    }
    _lineDecorations.sort((a, b) => a.priority.compareTo(b.priority));
    decorationsChanged = true;
    notifyListeners();
  }

  /// Removes a line decoration by its ID.
  void removeLineDecoration(String id) {
    _lineDecorations.removeWhere((d) => d.id == id);
    decorationsChanged = true;
    notifyListeners();
  }

  /// Removes all line decorations.
  void clearLineDecorations() {
    _lineDecorations.clear();
    decorationsChanged = true;
    notifyListeners();
  }

  /// Adds a gutter decoration to the editor.
  ///
  /// Gutter decorations appear in the line number area, useful for
  /// git diff indicators, breakpoints, bookmarks, etc.
  ///
  /// Example - Git diff indicator:
  /// ```dart
  /// controller.addGutterDecoration(GutterDecoration(
  ///   id: 'git-add-gutter-1',
  ///   startLine: 10,
  ///   endLine: 15,
  ///   type: GutterDecorationType.colorBar,
  ///   color: Colors.green,
  /// ));
  /// ```
  void addGutterDecoration(GutterDecoration decoration) {
    _gutterDecorations.removeWhere((d) => d.id == decoration.id);
    _gutterDecorations.add(decoration);
    _gutterDecorations.sort((a, b) => a.priority.compareTo(b.priority));
    decorationsChanged = true;
    notifyListeners();
  }

  /// Adds multiple gutter decorations at once.
  void addGutterDecorations(List<GutterDecoration> decorations) {
    for (final decoration in decorations) {
      _gutterDecorations.removeWhere((d) => d.id == decoration.id);
      _gutterDecorations.add(decoration);
    }
    _gutterDecorations.sort((a, b) => a.priority.compareTo(b.priority));
    decorationsChanged = true;
    notifyListeners();
  }

  /// Removes a gutter decoration by its ID.
  void removeGutterDecoration(String id) {
    _gutterDecorations.removeWhere((d) => d.id == id);
    decorationsChanged = true;
    notifyListeners();
  }

  /// Removes all gutter decorations.
  void clearGutterDecorations() {
    _gutterDecorations.clear();
    decorationsChanged = true;
    notifyListeners();
  }

  /// Sets the ghost text (inline suggestion) at a specific position.
  ///
  /// Ghost text appears as semi-transparent text, typically used for
  /// AI code completion suggestions. Only one ghost text can be active.
  ///
  /// Example:
  /// ```dart
  /// controller.setGhostText(GhostText(
  ///   line: 10,
  ///   column: 15,
  ///   text: 'print("Hello, World!");',
  ///   style: TextStyle(
  ///     color: Colors.grey.withOpacity(0.5),
  ///     fontStyle: FontStyle.italic,
  ///   ),
  /// ));
  /// ```
  ///
  /// Pass null to clear the ghost text.
  void setGhostText(GhostText? ghostText) {
    _ghostText = ghostText;
    decorationsChanged = true;
    notifyListeners();
  }

  /// Clears the ghost text.
  void clearGhostText() {
    _ghostText = null;
    decorationsChanged = true;
    notifyListeners();
  }

  /// Shows inlay hints in the editor.
  ///
  /// This fetches inlay hints from the LSP server for the visible range
  /// and displays them inline in the code. Sets readOnly to true while
  /// hints are visible to prevent user input.
  ///
  /// Inlay hints show type annotations (kind: 1) and parameter names (kind: 2).
  ///
  /// Example:
  /// ```dart
  /// // Call this when Ctrl+Alt is pressed
  /// await controller.showInlayHints();
  /// ```
  Future<void> showInlayHints() async {
    if (_inlayHintsVisible || lspConfig == null || openedFile == null) return;

    _inlayHintsVisible = true;
    readOnly = true;

    try {
      final endLine = lineCount > 500 ? 500 : lineCount;
      final response = await lspConfig!.getInlayHints(
        openedFile!,
        0,
        0,
        endLine,
        0,
      );

      final result = response['result'];
      if (result is List) {
        _inlayHints = result
            .whereType<Map<String, dynamic>>()
            .map((data) => InlayHint.fromLsp(data))
            .toList();
      } else {
        _inlayHints = [];
      }

      inlayHintsChanged = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching inlay hints: $e');
      _inlayHintsVisible = false;
      readOnly = false;
    }
  }

  /// Hides inlay hints from the editor.
  ///
  /// This clears all inlay hints and restores the editor to editable mode.
  ///
  /// Example:
  /// ```dart
  /// // Call this when Ctrl+Alt is released
  /// controller.hideInlayHints();
  /// ```
  void hideInlayHints() {
    if (!_inlayHintsVisible) return;

    _inlayHintsVisible = false;
    _inlayHints = [];
    readOnly = false;
    inlayHintsChanged = true;
    notifyListeners();
  }

  /// Sets inlay hints directly.
  ///
  /// Use this method if you want to provide custom inlay hints
  /// instead of fetching them from the LSP server.
  void setInlayHints(List<InlayHint> hints) {
    _inlayHints = hints;
    inlayHintsChanged = true;
    notifyListeners();
  }

  /// Clears all inlay hints.
  void clearInlayHints() {
    _inlayHints = [];
    inlayHintsChanged = true;
    notifyListeners();
  }

  /// Fetches and displays document colors from the LSP server.
  ///
  /// Document colors are displayed as small color boxes inline with
  /// color literals in the code (e.g., Colors.red, Color(0xFFFF0000)).
  ///
  /// Example:
  /// ```dart
  /// await controller.fetchDocumentColors();
  /// ```
  Future<void> fetchDocumentColors() async {
    if (lspConfig == null || openedFile == null) return;

    try {
      final response = await lspConfig!.getDocumentColor(openedFile!);
      final result = response['result'];

      if (result is List) {
        _documentColors = result
            .whereType<Map<String, dynamic>>()
            .map((data) => DocumentColor.fromLsp(data))
            .toList();
      } else {
        _documentColors = [];
      }

      documentColorsChanged = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching document colors: $e');
    }
  }

  /// Sets document colors directly.
  ///
  /// Use this method if you want to provide custom document colors
  /// instead of fetching them from the LSP server.
  void setDocumentColors(List<DocumentColor> colors) {
    _documentColors = colors;
    documentColorsChanged = true;
    notifyListeners();
  }

  /// Clears all document colors.
  void clearDocumentColors() {
    _documentColors = [];
    documentColorsChanged = true;
    notifyListeners();
  }

  /// Fetches document highlights for a symbol at the cursor position.
  ///
  /// This highlights all occurrences of the symbol at the given position.
  /// Should be called with a debounce delay to avoid frequent calls.
  ///
  /// Example:
  /// ```dart
  /// await controller.fetchDocumentHighlights(10, 5);
  /// ```
  Future<void> fetchDocumentHighlights(int line, int character) async {
    if (lspConfig == null || openedFile == null) return;

    try {
      final result = await lspConfig!.getDocumentHighlight(
        openedFile!,
        line,
        character,
      );

      if (result.isNotEmpty) {
        _documentHighlights = result
            .whereType<Map<String, dynamic>>()
            .map((data) => DocumentHighlight.fromLsp(data))
            .toList();
      } else {
        _documentHighlights = [];
      }

      documentHighlightsChanged = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching document highlights: $e');
      _documentHighlights = [];
      documentHighlightsChanged = true;
      notifyListeners();
    }
  }

  /// Schedules a document highlights refresh with debouncing.
  ///
  /// Cancels any pending refresh and schedules a new one.
  void scheduleDocumentHighlightsRefresh(int line, int character) {
    _documentHighlightTimer?.cancel();
    _documentHighlightTimer = Timer(_documentHighlightDebounce, () {
      fetchDocumentHighlights(line, character);
    });
  }

  /// Clears all document highlights.
  void clearDocumentHighlights() {
    _documentHighlights = [];
    documentHighlightsChanged = true;
    notifyListeners();
  }

  /// Fetches fold ranges from the LSP server.
  ///
  /// If successful, these fold ranges will be used instead of the
  /// built-in fold range detection algorithm.
  ///
  /// Example:
  /// ```dart
  /// await controller.fetchLSPFoldRanges();
  /// ```
  Future<void> fetchLSPFoldRanges() async {
    if (lspConfig == null || openedFile == null) return;

    try {
      final response = await lspConfig!.getLSPFoldRanges(openedFile!);
      final result = response['result'];

      if (result is List && result.isNotEmpty) {
        final Map<int, FoldRange> foldMap = {};
        final oldRanges = _lspFoldRanges;
        for (final item in result) {
          if (item is Map<String, dynamic>) {
            final startLine = item['startLine'] as int?;
            final endLine = item['endLine'] as int?;
            if (startLine != null && endLine != null && endLine > startLine) {
              final newFold = FoldRange(startLine, endLine);

              FoldRange? existing =
                  oldRanges?[startLine] ?? foldings[startLine];
              if (existing == null) {
                for (
                int offset = 1;
                offset <= 3 && existing == null;
                offset++
                ) {
                  existing =
                      oldRanges?[startLine - offset] ??
                          oldRanges?[startLine + offset] ??
                          foldings[startLine - offset] ??
                          foldings[startLine + offset];
                  if (existing != null) {
                    final oldSpan = existing.endIndex - existing.startIndex;
                    final newSpan = endLine - startLine;
                    if ((oldSpan - newSpan).abs() > (oldSpan * 0.3)) {
                      existing = null;
                    }
                  }
                }
              }
              if (existing != null) {
                newFold.isFolded = existing.isFolded;
                newFold.originallyFoldedChildren =
                    existing.originallyFoldedChildren;
              }

              foldMap[startLine] = newFold;
            }
          }
        }
        _lspFoldRanges = foldMap.isEmpty ? null : foldMap;
      } else {
        _lspFoldRanges = null;
      }
      _lspFoldRangesAdjustedNotFetched = false;

      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching LSP fold ranges: $e');
      _lspFoldRanges = null;
    }
  }

  /// Clears LSP fold ranges, forcing fallback to built-in algorithm.
  void clearLSPFoldRanges() {
    _lspFoldRanges = null;
    _lspFoldRangesAdjustedNotFetched = false;
    notifyListeners();
  }

  /// Adjusts LSP fold ranges after a line count change.
  ///
  /// [editLine] is the line where the edit occurred.
  /// [lineDelta] is the number of lines added (positive) or removed (negative).
  void adjustLspFoldRangesForLineChange(int editLine, int lineDelta) {
    if (_lspFoldRanges == null || lineDelta == 0) return;

    final adjustedLspFoldRanges = <int, FoldRange>{};

    for (final entry in _lspFoldRanges!.entries) {
      final oldStartIndex = entry.key;
      final fold = entry.value;

      if (fold.endIndex < editLine) {
        adjustedLspFoldRanges[oldStartIndex] = fold;
      } else if (fold.startIndex <= editLine && fold.endIndex >= editLine) {
        final newEndIndex = fold.endIndex + lineDelta;
        if (newEndIndex >= oldStartIndex) {
          final newFold = FoldRange(oldStartIndex, newEndIndex);
          newFold.isFolded = fold.isFolded;
          newFold.originallyFoldedChildren = fold.originallyFoldedChildren;
          adjustedLspFoldRanges[oldStartIndex] = newFold;
        }
      } else if (fold.startIndex > editLine) {
        final newStartIndex = fold.startIndex + lineDelta;
        final newEndIndex = fold.endIndex + lineDelta;
        if (newStartIndex >= 0 && newEndIndex >= newStartIndex) {
          final newFold = FoldRange(newStartIndex, newEndIndex);
          newFold.isFolded = fold.isFolded;
          newFold.originallyFoldedChildren = fold.originallyFoldedChildren;
          adjustedLspFoldRanges[newStartIndex] = newFold;
        }
      }
    }

    _lspFoldRanges = adjustedLspFoldRanges.isEmpty
        ? null
        : adjustedLspFoldRanges;
    _lspFoldRangesAdjustedNotFetched = true;
  }

  /// Convenience method to set git diff decorations for multiple line ranges.
  ///
  /// [addedRanges] - List of (startLine, endLine) for added lines (green)
  /// [removedRanges] - List of ({afterLine, content}) for removed lines displayed
  ///   virtually without line numbers, similar to ghost text. [afterLine] is the
  ///   0-based line after which the removed content appears, and [content] is the
  ///   deleted text (use `\n` for multiple lines).
  /// [modifiedRanges] - List of (startLine, endLine) for modified lines (blue)
  void setGitDiffDecorations({
    List<(int startLine, int endLine)>? addedRanges,
    List<({int afterLine, String content})>? removedRanges,
    List<(int startLine, int endLine)>? modifiedRanges,
    Color addedColor = const Color(0xFF4CAF50),
    Color removedColor = const Color(0xFFE53935),
    Color modifiedColor = const Color(0xFF2196F3),
  }) {
    _lineDecorations.removeWhere((d) => d.id.startsWith('git-'));
    _gutterDecorations.removeWhere((d) => d.id.startsWith('git-'));
    _virtualRemovedBlocks.clear();

    int idx = 0;

    if (addedRanges != null) {
      for (final range in addedRanges) {
        _lineDecorations.add(
          LineDecoration(
            id: 'git-add-line-$idx',
            startLine: range.$1,
            endLine: range.$2,
            type: LineDecorationType.background,
            color: addedColor.withValues(alpha: 0.15),
          ),
        );
        _gutterDecorations.add(
          GutterDecoration(
            id: 'git-add-gutter-$idx',
            startLine: range.$1,
            endLine: range.$2,
            type: GutterDecorationType.colorBar,
            color: addedColor,
          ),
        );
        idx++;
      }
    }

    if (removedRanges != null) {
      final sorted = removedRanges.toList()
        ..sort((a, b) => a.afterLine.compareTo(b.afterLine));
      for (final range in sorted) {
        _virtualRemovedBlocks.add(
          VirtualRemovedBlock(
            afterLine: range.afterLine,
            content: range.content,
            backgroundColor: removedColor.withValues(alpha: 0.15),
            textStyle: TextStyle(color: removedColor.withValues(alpha: 0.7)),
          ),
        );
      }
    }

    if (modifiedRanges != null) {
      for (final range in modifiedRanges) {
        _lineDecorations.add(
          LineDecoration(
            id: 'git-modify-line-$idx',
            startLine: range.$1,
            endLine: range.$2,
            type: LineDecorationType.background,
            color: modifiedColor.withValues(alpha: 0.15),
          ),
        );
        _gutterDecorations.add(
          GutterDecoration(
            id: 'git-modify-gutter-$idx',
            startLine: range.$1,
            endLine: range.$2,
            type: GutterDecorationType.colorBar,
            color: modifiedColor,
          ),
        );
        idx++;
      }
    }

    decorationsChanged = true;
    notifyListeners();
  }

  /// Clears all git diff decorations.
  void clearGitDiffDecorations() {
    _lineDecorations.removeWhere((d) => d.id.startsWith('git-'));
    _gutterDecorations.removeWhere((d) => d.id.startsWith('git-'));
    _virtualRemovedBlocks.clear();
    decorationsChanged = true;
    notifyListeners();
  }

  /// Whether the editor is in read-only mode.
  ///
  /// When true, the user cannot modify the text content.
  bool readOnly = false;

  /// Use space instead of the `\t` character for tab key press.
  bool useSpaceAsTab = false;

  /// Custom tabSize for the editor.
  int tabSize = 1;

  /// The tabspace inserted on tab key press.
  String get tabSpace {
    if (useSpaceAsTab) {
      return ' ' * tabSize;
    }
    return '\t' * tabSize;
  }

  /// Whether the line structure has changed (lines added or removed).
  bool lineStructureChanged = false;

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
    if (suggestionsNotifier.value != null) {
      suggestionsNotifier.value = null;
    }

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
    if (suggestionsNotifier.value != null) {
      suggestionsNotifier.value = null;
    }

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

    if (_isMobile &&
        suggestionsNotifier.value != null &&
        currentlySelectedSuggestion == null) {
      currentlySelectedSuggestion = 0;
      return;
    }

    if (_isMobile &&
        suggestionsNotifier.value != null &&
        currentlySelectedSuggestion != null) {
      currentlySelectedSuggestion =
          (currentlySelectedSuggestion! - 1) %
              suggestionsNotifier.value!.length;
      return;
    }

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

    if (_isMobile &&
        suggestionsNotifier.value != null &&
        currentlySelectedSuggestion == null) {
      currentlySelectedSuggestion = 0;
      return;
    }

    if (_isMobile &&
        suggestionsNotifier.value != null &&
        currentlySelectedSuggestion != null) {
      currentlySelectedSuggestion =
          (currentlySelectedSuggestion! + 1) %
              suggestionsNotifier.value!.length;
      return;
    }

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
        final fold = foldings[foldStart] ?? FoldRange(targetLine, targetLine);
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
    if (suggestionsNotifier.value != null) {
      suggestionsNotifier.value = null;
    }

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
    if (suggestionsNotifier.value != null) {
      suggestionsNotifier.value = null;
    }

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

  /// Moves the cursor to the beginning of the document.
  ///
  /// If [isShiftPressed] is true, extends the selection to the document start.
  void pressDocumentHomeKey({bool isShiftPressed = false}) {
    if (isShiftPressed) {
      setSelectionSilently(
        TextSelection(baseOffset: selection.baseOffset, extentOffset: 0),
      );
    } else {
      setSelectionSilently(TextSelection.collapsed(offset: 0));
    }
  }

  /// Moves the cursor to the end of the document.
  ///
  /// If [isShiftPressed] is true, extends the selection to the document end.
  void pressDocumentEndKey({bool isShiftPressed = false}) {
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
    setSelectionImmediately(TextSelection(baseOffset: 0, extentOffset: length));
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
    if (_bufferLineIndex != null && _bufferDirty) {
      _cachedBufferLines ??= _bufferLineText!.split('\n');
      final newLines = _cachedBufferLines!.length - 1;
      return _rope.lineCount + newLines;
    }
    return _rope.lineCount;
  }

  /// The visible text content with folded regions hidden.
  ///
  /// Returns the document text with lines inside collapsed fold ranges removed.
  String get visibleText {
    if (foldings.isEmpty) return text;
    final visLines = List<String>.from(lines);
    for (final fold
    in foldings.values.where((f) => f != null).toList().reversed) {
      if (!fold!.isFolded) continue;
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
    if (_bufferLineIndex != null && _bufferDirty) {
      _cachedBufferLines ??= _bufferLineText!.split('\n');
      final newLines = _cachedBufferLines!.length - 1;
      if (newLines > 0) {
        if (lineIndex >= _bufferLineIndex! &&
            lineIndex <= _bufferLineIndex! + newLines) {
          return _cachedBufferLines![lineIndex - _bufferLineIndex!];
        } else if (lineIndex > _bufferLineIndex! + newLines) {
          return _rope.getLineText(lineIndex - newLines);
        } else {
          return _rope.getLineText(lineIndex);
        }
      } else {
        if (lineIndex == _bufferLineIndex) {
          return _bufferLineText!;
        }
      }
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
        final localOffset = charOffset - bufferStart;
        final sub = _bufferLineText!.substring(0, localOffset);
        return _bufferLineIndex! + '\n'.allMatches(sub).length;
      } else if (charOffset > bufferEnd) {
        final delta = _bufferLineText!.length - _bufferLineOriginalLength;
        final newLines = '\n'.allMatches(_bufferLineText!).length;
        return _rope.getLineAtOffset(charOffset - delta) + newLines;
      }
    }
    return _rope.getLineAtOffset(charOffset);
  }

  /// Gets the character offset where a line starts.
  ///
  /// [lineIndex] is zero-based (0 for the first line).
  /// Returns the character offset of the first character in that line.
  int getLineStartOffset(int lineIndex) {
    if (_bufferLineIndex != null && _bufferDirty) {
      final newLines = '\n'.allMatches(_bufferLineText!).length;
      if (newLines > 0) {
        if (lineIndex == _bufferLineIndex!) {
          return _bufferLineRopeStart;
        } else if (lineIndex > _bufferLineIndex! &&
            lineIndex <= _bufferLineIndex! + newLines) {
          final lines = _bufferLineText!.split('\n');
          int offset = _bufferLineRopeStart;
          for (int i = 0; i < lineIndex - _bufferLineIndex!; i++) {
            offset += lines[i].length + 1;
          }
          return offset;
        } else if (lineIndex > _bufferLineIndex! + newLines) {
          final delta = _bufferLineText!.length - _bufferLineOriginalLength;
          return _rope.getLineStartOffset(lineIndex - newLines) + delta;
        }
      } else {
        if (lineIndex == _bufferLineIndex!) return _bufferLineRopeStart;
        if (lineIndex > _bufferLineIndex!) {
          final delta = _bufferLineText!.length - _bufferLineOriginalLength;
          return _rope.getLineStartOffset(lineIndex) + delta;
        }
      }
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
    _isTyping = false;

    if (!isComposing && connection != null && connection!.attached) {
      _lastSentText = text;
      _lastSentSelection = newSelection;
      connection!.setEditingState(
        TextEditingValue(text: _lastSentText!, selection: newSelection, composing: _composing),
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

    final textLength = length;
    final clampedBase = newSelection.baseOffset.clamp(0, textLength);
    final clampedExtent = newSelection.extentOffset.clamp(0, textLength);
    newSelection = newSelection.copyWith(
      baseOffset: clampedBase,
      extentOffset: clampedExtent,
    );

    _selection = newSelection;
    selectionOnly = true;
    _isTyping = false;

    _scheduleSyncToConnection();
    notifyListeners();
  }

  void setSelectionImmediately(TextSelection newSelection) {
    if (_selection == newSelection) return;

    _flushBuffer();

    final textLength = length;
    final clampedBase = newSelection.baseOffset.clamp(0, textLength);
    final clampedExtent = newSelection.extentOffset.clamp(0, textLength);
    newSelection = newSelection.copyWith(
      baseOffset: clampedBase,
      extentOffset: clampedExtent,
    );

    _selection = newSelection;
    selectionOnly = true;
    _isTyping = false;

    if (!isComposing && connection != null && connection!.attached) {
      _lastSentText = text;
      _lastSentSelection = newSelection;
      connection!.setEditingState(
        TextEditingValue(text: _lastSentText!, selection: newSelection, composing: _composing),
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

  /// Moves the current line up by one line.
  ///
  /// If the selection spans multiple lines, all selected lines are moved.
  /// The selection is adjusted accordingly after the move.
  /// Does nothing if the line is already at the top or if the controller is read-only.
  void moveLineUp() {
    if (readOnly) return;
    final selection = this.selection;
    final text = this.text;
    final selStart = selection.start;
    final selEnd = selection.end;
    final lineStart = selStart > 0
        ? text.lastIndexOf('\n', selStart - 1) + 1
        : 0;
    int lineEnd = text.indexOf('\n', selEnd);
    if (lineEnd == -1) lineEnd = text.length;
    if (lineStart == 0) return;

    final prevLineEnd = lineStart - 1;
    final prevLineStart = text.lastIndexOf('\n', prevLineEnd - 1) + 1;
    final prevLine = text.substring(prevLineStart, prevLineEnd);
    final currentLines = text.substring(lineStart, lineEnd);

    replaceRange(prevLineStart, lineEnd, '$currentLines\n$prevLine');

    final prevLineLen = prevLineEnd - prevLineStart;
    final offsetDelta = prevLineLen + 1;
    final newSelection = TextSelection(
      baseOffset: selection.baseOffset - offsetDelta,
      extentOffset: selection.extentOffset - offsetDelta,
    );
    setSelectionSilently(newSelection);
  }

  /// Moves the current line down by one line.
  ///
  /// If the selection spans multiple lines, all selected lines are moved.
  /// The selection is adjusted accordingly after the move.
  /// Does nothing if the line is already at the bottom or if the controller is read-only.
  void moveLineDown() {
    if (readOnly) return;
    final selection = this.selection;
    final text = this.text;
    final selStart = selection.start;
    final selEnd = selection.end;
    final lineStart = text.lastIndexOf('\n', selStart - 1) + 1;
    int lineEnd = text.indexOf('\n', selEnd);
    if (lineEnd == -1) lineEnd = text.length;
    final nextLineStart = lineEnd + 1;
    if (nextLineStart >= text.length) return;
    int nextLineEnd = text.indexOf('\n', nextLineStart);
    if (nextLineEnd == -1) nextLineEnd = text.length;

    final currentLines = text.substring(lineStart, lineEnd);
    final nextLine = text.substring(nextLineStart, nextLineEnd);

    replaceRange(lineStart, nextLineEnd, '$nextLine\n$currentLines');

    final offsetDelta = nextLine.length + 1;
    final newSelection = TextSelection(
      baseOffset: selection.baseOffset + offsetDelta,
      extentOffset: selection.extentOffset + offsetDelta,
    );
    setSelectionSilently(newSelection);
  }

  /// Duplicates the current line or selected text.
  ///
  /// If text is selected, duplicates the selected text.
  /// If no selection, duplicates the line at the cursor position.
  /// The cursor is moved to the end of the duplicated content.
  /// Does nothing if the controller is read-only.
  void duplicateLine() {
    if (readOnly) return;
    final text = this.text;
    final selection = this.selection;

    if (selection.start != selection.end) {
      final selectedText = text.substring(selection.start, selection.end);
      replaceRange(selection.end, selection.end, selectedText);
      setSelectionSilently(
        TextSelection.collapsed(offset: selection.end + selectedText.length),
      );
    } else {
      final caret = selection.extentOffset;
      final prevNewline = (caret > 0) ? text.lastIndexOf('\n', caret - 1) : -1;
      final nextNewline = text.indexOf('\n', caret);
      final lineStart = prevNewline == -1 ? 0 : prevNewline + 1;
      final lineEnd = nextNewline == -1 ? text.length : nextNewline;
      final lineText = text.substring(lineStart, lineEnd);

      replaceRange(lineEnd, lineEnd, '\n$lineText');
      setSelectionSilently(TextSelection.collapsed(offset: lineEnd + 1));
    }
  }

  @protected
  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    if (readOnly) return;

    bool typingDetected = false;

    for (final delta in textEditingDeltas) {
      // ── Track IME composing region from every delta ──
      final bool wasComposing = isComposing;
      _composing = delta.composing;

      // Composing: Start by saving the current selection, which will be used to restore the state when undoing.
      if (!wasComposing && isComposing) {
        _preComposingSelection = _selection;
      }

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
        if (delta.textInserted == '\n' &&
            suggestionsNotifier.value != null &&
            _isMobile &&
            currentlySelectedSuggestion != null) {
          final sugg = suggestionsNotifier.value![currentlySelectedSuggestion!];
          final text = _extractSuggestionText(sugg);
          insertAtCurrentCursor(text, replaceTypedChar: true);
          suggestionsNotifier.value = null;
          currentlySelectedSuggestion = null;
          callSignatureHelp();
          continue;
        }

        if (delta.textInserted.length == 1) {
          _lastTypedCharacter = delta.textInserted;
        }
        if (delta.textInserted.isNotEmpty &&
            (_isAlpha(delta.textInserted) ||
                _isCompletionTriggerChar(delta.textInserted))) {
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

    // Composing Cancel (no replacement consumed by _preComposingSelection): Clean up
    if (!isComposing && _preComposingSelection != null) {
      _preComposingSelection = null;
    }

    notifyListeners();
  }

  bool get isBufferActive => _bufferLineIndex != null && _bufferDirty;

  /// Whether an IME composing session is active (e.g. Chinese pinyin input).
  bool get isComposing => _composing.isValid && !_composing.isCollapsed;
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
    final isFolded = foldings.values.any(
          (fold) =>
      fold != null &&
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

  /// Inserts text at the specified line and character position.
  ///
  /// [line] is zero-based (0 for the first line).
  /// [character] is zero-based column position within the line.
  /// The character position will be clamped to the line's length.
  void insertText(String text, int line, int character) {
    if (readOnly) return;
    _flushBuffer();

    final clampedLine = line.clamp(0, lineCount - 1);
    final lineText = getLineText(clampedLine);
    final clampedChar = character.clamp(0, lineText.length);
    final offset = getLineStartOffset(clampedLine) + clampedChar;

    replaceRange(offset, offset, text);
  }

  /// Safely sync editing state to platform. Skipped during IME composing.
  void _safelySyncEditingState() {
    if (isComposing) return;
    if (connection != null && connection!.attached) {
      _lastSentText = text;
      _lastSentSelection = _selection;
      connection!.setEditingState(
        TextEditingValue(text: _lastSentText!, selection: _selection, composing: _composing),
      );
    }
  }

  void _syncToConnection() {
    if (isComposing) return; // Do not synchronize during composition to avoid disrupting the IME session
    if (connection != null && connection!.attached) {
      final currentText = text;
      _lastSentText = currentText;
      _lastSentSelection = _selection;
      connection!.setEditingState(
        TextEditingValue(text: currentText, selection: _selection, composing: _composing),
      );
    }
  }

  /// Remove the selection or last char if the selection is empty (backspace key)
  void backspace() {
    if (readOnly) return;
    if (_undoController?.isUndoRedoInProgress ?? false) return;

    final selectionBefore = _selection;
    final sel = _selection;
    String deletedText;

    if (sel.start < sel.end) {
      _flushBuffer();

      if (deleteFoldRangeOnDeletingFirstLine) {
        final startLine = _rope.getLineAtOffset(sel.start);
        final endLine = _rope.getLineAtOffset(sel.end);

        if (startLine == endLine ||
            (startLine + 1 == endLine &&
                sel.end == _rope.getLineStartOffset(endLine))) {
          final lineStart = _rope.getLineStartOffset(startLine);
          final lineText = _rope.getLineText(startLine);
          final lineEnd = lineStart + lineText.length;
          final selectsWholeLine = sel.start <= lineStart && sel.end >= lineEnd;

          if (selectsWholeLine) {
            FoldRange? foldToDelete;

            if (_isFirstLineOfFoldedRange(startLine)) {
              foldToDelete = foldings[startLine];
            } else {
              for (final fold in foldings.values) {
                if (fold != null && fold.isFolded) {
                  if (startLine > fold.startIndex &&
                      startLine <= fold.endIndex) {
                    for (final child in fold.originallyFoldedChildren) {
                      if (child.startIndex == startLine) {
                        foldToDelete = child;
                        break;
                      }
                    }
                    if (foldToDelete != null) break;
                  }
                }
              }
            }

            if (foldToDelete != null) {
              final foldStart = _rope.getLineStartOffset(
                foldToDelete.startIndex,
              );
              final foldEndLine = foldToDelete.endIndex;
              final foldEndLineText = _rope.getLineText(foldEndLine);
              final foldEnd =
                  _rope.getLineStartOffset(foldEndLine) +
                      foldEndLineText.length;

              deletedText = _rope.substring(foldStart, foldEnd);
              _rope.delete(foldStart, foldEnd);
              _currentVersion++;
              _selection = TextSelection.collapsed(offset: foldStart);
              dirtyLine = _rope.getLineAtOffset(
                foldStart.clamp(0, _rope.length),
              );
              lineStructureChanged = true;
              foldings.remove(foldToDelete.startIndex);

              for (final fold in foldings.values) {
                if (fold != null) {
                  fold.originallyFoldedChildren.remove(foldToDelete);
                }
              }

              _recordDeletion(
                foldStart,
                deletedText,
                selectionBefore,
                _selection,
              );
              _syncToConnection();
              notifyListeners();
              return;
            }
          }
        }
      }

      deletedText = _rope.substring(sel.start, sel.end);
      _rope.delete(sel.start, sel.end);
      _currentVersion++;
      _selection = TextSelection.collapsed(offset: sel.start);
      dirtyLine = _rope.getLineAtOffset(sel.start);

      _recordDeletion(sel.start, deletedText, selectionBefore, _selection);
      _syncToConnection();
      notifyListeners();
      return;
    }

    if (sel.start <= 0) return;

    final deleteOffset = sel.start - 1;

    String charToDelete;
    if (_bufferLineIndex != null && _bufferDirty) {
      final bufferEnd = _bufferLineRopeStart + _bufferLineText!.length;
      if (deleteOffset >= _bufferLineRopeStart && deleteOffset < bufferEnd) {
        charToDelete = _bufferLineText![deleteOffset - _bufferLineRopeStart];
      } else {
        charToDelete = _rope.charAt(deleteOffset);
      }
    } else {
      charToDelete = _rope.charAt(deleteOffset);
    }

    if (charToDelete == '\n') {
      _flushBuffer();
      _rope.delete(deleteOffset, sel.start);
      _currentVersion++;
      _selection = TextSelection.collapsed(offset: deleteOffset);
      dirtyLine = _rope.getLineAtOffset(deleteOffset);
      lineStructureChanged = true;

      _recordDeletion(deleteOffset, '\n', selectionBefore, _selection);
      _syncToConnection();
      notifyListeners();
      return;
    }

    if (_bufferLineIndex != null && _bufferDirty) {
      final bufferEnd = _bufferLineRopeStart + _bufferLineText!.length;

      if (deleteOffset >= _bufferLineRopeStart && deleteOffset < bufferEnd) {
        final localOffset = deleteOffset - _bufferLineRopeStart;
        deletedText = _bufferLineText![localOffset];
        _bufferLineText =
            _bufferLineText!.substring(0, localOffset) +
                _bufferLineText!.substring(localOffset + 1);
        _selection = TextSelection.collapsed(offset: deleteOffset);
        _currentVersion++;

        bufferNeedsRepaint = true;

        _recordDeletion(deleteOffset, deletedText, selectionBefore, _selection);
        _scheduleSyncToConnection();
        _scheduleFlush();
        notifyListeners();
        return;
      }
      _flushBuffer();
    }

    final lineIndex = _rope.getLineAtOffset(deleteOffset);
    _initBuffer(lineIndex);

    final localOffset = deleteOffset - _bufferLineRopeStart;
    if (localOffset >= 0 && localOffset < _bufferLineText!.length) {
      deletedText = _bufferLineText![localOffset];
      _bufferLineText =
          _bufferLineText!.substring(0, localOffset) +
              _bufferLineText!.substring(localOffset + 1);
      _bufferDirty = true;
      _cachedBufferLines = null;
      _selection = TextSelection.collapsed(offset: deleteOffset);
      _currentVersion++;
      dirtyLine = lineIndex;

      bufferNeedsRepaint = true;

      _recordDeletion(deleteOffset, deletedText, selectionBefore, _selection);
      _scheduleSyncToConnection();
      _scheduleFlush();
      notifyListeners();
    }
  }

  /// Remove the selection or the char at cursor position (delete key)
  void delete() {
    if (readOnly) return;
    if (_undoController?.isUndoRedoInProgress ?? false) return;

    final selectionBefore = _selection;
    final sel = _selection;
    String deletedText;

    if (sel.start < sel.end) {
      _flushBuffer();

      if (deleteFoldRangeOnDeletingFirstLine) {
        final startLine = _rope.getLineAtOffset(sel.start);
        final endLine = _rope.getLineAtOffset(sel.end);

        if (startLine == endLine ||
            (startLine + 1 == endLine &&
                sel.end == _rope.getLineStartOffset(endLine))) {
          final lineStart = _rope.getLineStartOffset(startLine);
          final lineText = _rope.getLineText(startLine);
          final lineEnd = lineStart + lineText.length;
          final selectsWholeLine = sel.start <= lineStart && sel.end >= lineEnd;

          if (selectsWholeLine) {
            FoldRange? foldToDelete;

            if (_isFirstLineOfFoldedRange(startLine)) {
              foldToDelete = foldings[startLine];
            } else {
              for (final fold in foldings.values) {
                if (fold != null && fold.isFolded) {
                  if (startLine > fold.startIndex &&
                      startLine <= fold.endIndex) {
                    for (final child in fold.originallyFoldedChildren) {
                      if (child.startIndex == startLine) {
                        foldToDelete = child;
                        break;
                      }
                    }
                    if (foldToDelete != null) break;
                  }
                }
              }
            }

            if (foldToDelete != null) {
              final foldStart = _rope.getLineStartOffset(
                foldToDelete.startIndex,
              );
              final foldEndLine = foldToDelete.endIndex;
              final foldEndLineText = _rope.getLineText(foldEndLine);
              final foldEnd =
                  _rope.getLineStartOffset(foldEndLine) +
                      foldEndLineText.length;

              deletedText = _rope.substring(foldStart, foldEnd);
              _rope.delete(foldStart, foldEnd);
              _currentVersion++;
              _selection = TextSelection.collapsed(offset: foldStart);
              dirtyLine = _rope.getLineAtOffset(
                foldStart.clamp(0, _rope.length),
              );
              lineStructureChanged = true;
              foldings.remove(foldToDelete.startIndex);

              for (final fold in foldings.values) {
                if (fold != null) {
                  fold.originallyFoldedChildren.remove(foldToDelete);
                }
              }

              _recordDeletion(
                foldStart,
                deletedText,
                selectionBefore,
                _selection,
              );
              _syncToConnection();
              notifyListeners();
              return;
            }
          }
        }
      }

      deletedText = _rope.substring(sel.start, sel.end);
      _rope.delete(sel.start, sel.end);
      _currentVersion++;
      _selection = TextSelection.collapsed(offset: sel.start);
      dirtyLine = _rope.getLineAtOffset(sel.start);

      _recordDeletion(sel.start, deletedText, selectionBefore, _selection);
      _syncToConnection();
      notifyListeners();
      return;
    }

    final textLen = length;
    if (sel.start >= textLen) return;

    final deleteOffset = sel.start;

    String charToDelete;
    if (_bufferLineIndex != null && _bufferDirty) {
      final bufferEnd = _bufferLineRopeStart + _bufferLineText!.length;
      if (deleteOffset >= _bufferLineRopeStart && deleteOffset < bufferEnd) {
        charToDelete = _bufferLineText![deleteOffset - _bufferLineRopeStart];
      } else {
        charToDelete = _rope.charAt(deleteOffset);
      }
    } else {
      charToDelete = _rope.charAt(deleteOffset);
    }

    if (charToDelete == '\n') {
      _flushBuffer();
      _rope.delete(deleteOffset, deleteOffset + 1);
      _currentVersion++;
      dirtyLine = _rope.getLineAtOffset(deleteOffset);
      lineStructureChanged = true;

      _recordDeletion(deleteOffset, '\n', selectionBefore, _selection);
      _syncToConnection();
      notifyListeners();
      return;
    }

    if (_bufferLineIndex != null && _bufferDirty) {
      final bufferEnd = _bufferLineRopeStart + _bufferLineText!.length;

      if (deleteOffset >= _bufferLineRopeStart && deleteOffset < bufferEnd) {
        final localOffset = deleteOffset - _bufferLineRopeStart;
        deletedText = _bufferLineText![localOffset];
        _bufferLineText =
            _bufferLineText!.substring(0, localOffset) +
                _bufferLineText!.substring(localOffset + 1);
        _currentVersion++;

        bufferNeedsRepaint = true;

        _recordDeletion(deleteOffset, deletedText, selectionBefore, _selection);
        _scheduleSyncToConnection();
        _scheduleFlush();
        notifyListeners();
        return;
      }
      _flushBuffer();
    }

    final lineIndex = _rope.getLineAtOffset(deleteOffset);
    _initBuffer(lineIndex);

    final localOffset = deleteOffset - _bufferLineRopeStart;
    if (localOffset >= 0 && localOffset < _bufferLineText!.length) {
      deletedText = _bufferLineText![localOffset];
      _bufferLineText =
          _bufferLineText!.substring(0, localOffset) +
              _bufferLineText!.substring(localOffset + 1);
      _bufferDirty = true;
      _cachedBufferLines = null;
      _currentVersion++;
      dirtyLine = lineIndex;

      bufferNeedsRepaint = true;

      _recordDeletion(deleteOffset, deletedText, selectionBefore, _selection);
      _scheduleSyncToConnection();
      _scheduleFlush();
      notifyListeners();
    }
  }

  void _rebuildFoldSortedCache() {
    final starts = <int>[];
    final ends = <int>[];
    for (final fold in _foldings.values) {
      if (fold != null && fold.isFolded) {
        starts.add(fold.startIndex);
        ends.add(fold.endIndex);
      }
    }

    if (starts.length > 1) {
      final indices = List.generate(starts.length, (i) => i);
      indices.sort((a, b) => starts[a].compareTo(starts[b]));
      _foldedStartsSorted = [for (final i in indices) starts[i]];
      _foldedEndsSorted = [for (final i in indices) ends[i]];
    } else {
      _foldedStartsSorted = starts;
      _foldedEndsSorted = ends;
    }
  }

  bool _isFirstLineOfFoldedRange(int lineIndex) {
    final fold = foldings[lineIndex];
    return fold != null && fold.isFolded;
  }

  @protected
  @override
  void connectionClosed() {
    if (connection != null && connection!.attached) {
      connection?.connectionClosedReceived();
      connection = null;
      focusNode?.unfocus();
    }
  }

  @protected
  @override
  AutofillScope? get currentAutofillScope => null;

  @protected
  @override
  TextEditingValue? get currentTextEditingValue =>
      TextEditingValue(text: text, selection: _selection, composing: _composing);

  @protected
  @override
  void didChangeInputControl(
      TextInputControl? oldControl,
      TextInputControl? newControl,
      ) {}

  @protected
  @override
  void insertContent(KeyboardInsertedContent content) {}

  @protected
  @override
  void insertTextPlaceholder(Size size) {}

  @protected
  @override
  void performAction(TextInputAction action) {}

  @protected
  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @protected
  @override
  void performSelector(String selectorName) {}

  @protected
  @override
  void removeTextPlaceholder() {}

  @protected
  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @protected
  @override
  void showToolbar() {}

  @protected
  @override
  bool onFocusReceived() => true;

  @protected
  @override
  void updateEditingValue(TextEditingValue value) {
    text = value.text;
    selection = value.selection;
    dirtyRegion = TextRange(start: 0, end: value.text.length);
    dirtyLine = null;
    notifyListeners();
  }

  Offset? Function()? getFloatingCursorStartPosition;
  int Function(Offset)? getTextOffsetForFloatingCursorPosition;
  Offset? _floatingCursorStartPosition;

  @protected
  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    if (readOnly) return;

    switch (point.state) {
      case FloatingCursorDragState.Start:
        _floatingCursorStartPosition = getFloatingCursorStartPosition?.call();
        break;
      case FloatingCursorDragState.Update:
        if (point.offset == null ||
            _floatingCursorStartPosition == null ||
            getTextOffsetForFloatingCursorPosition == null) {
          return;
        }
        final targetPosition = _floatingCursorStartPosition! + point.offset!;
        final newOffset = getTextOffsetForFloatingCursorPosition!(
          targetPosition,
        );
        setSelectionSilently(TextSelection.collapsed(offset: newOffset));
        break;
      case FloatingCursorDragState.End:
        _floatingCursorStartPosition = null;
        break;
    }
  }

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

    if (!isComposing && connection != null && connection!.attached) {
      _lastSentText = text;
      _lastSentSelection = _selection;
      connection!.setEditingState(
        TextEditingValue(text: _lastSentText!, selection: _selection, composing: _composing),
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
          .map((line) => '$tabSpace$line')
          .join('\n');

      final lines = selectedBlock.split('\n');
      final addedChars = tabSize * lines.length;
      final newSelection = TextSelection(
        baseOffset: selection.baseOffset + tabSize,
        extentOffset: selection.extentOffset + addedChars,
      );

      replaceRange(lineStart, lineEnd, indentedBlock);
      setSelectionSilently(newSelection);
    } else {
      insertAtCurrentCursor(tabSpace);
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
      final lines = selectedBlock.split('\n');
      final unindentedBlock = lines
          .map(
            (line) => line.startsWith(tabSpace)
            ? line.substring(tabSize)
            : line.replaceFirst(RegExp(r'^ +'), ''),
      )
          .join('\n');

      int removedChars = 0;
      for (final line in lines) {
        if (line.startsWith(tabSpace)) {
          removedChars += tabSize;
        } else {
          removedChars += RegExp(r'^ +').stringMatch(line)?.length ?? 0;
        }
      }

      final newSelection = TextSelection(
        baseOffset:
        selection.baseOffset -
            (lines.first.startsWith(tabSpace)
                ? tabSize
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
      if (line.startsWith(tabSpace)) {
        removeCount = tabSize;
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

  /// Sets the scroll callback - called by the render object.
  void setScrollCallback(void Function(int line)? scrollToLine) {
    _scrollToLineCallback = scrollToLine;
  }

  /// Scrolls the editor view to make the specified line visible.
  ///
  /// [line] is zero-indexed (0 for the first line). The editor will scroll
  /// vertically to bring the specified line into view, centering it if possible.
  ///
  /// If the line is within a folded region, the fold will be expanded first
  /// to make the line visible.
  ///
  /// Throws [StateError] if the editor has not been initialized.
  /// Throws [RangeError] if [line] is out of bounds.
  ///
  /// Example:
  /// ```dart
  /// // Scroll to line 50 (1-indexed line 51)
  /// controller.scrollToLine(50);
  ///
  /// // Scroll to the first line
  /// controller.scrollToLine(0);
  /// ```
  void scrollToLine(int line) {
    if (_scrollToLineCallback == null) {
      throw StateError('Editor is not initialized');
    }
    if (line < 0 || line >= lineCount) {
      throw RangeError.range(line, 0, lineCount - 1, 'line');
    }
    _scrollToLineCallback!(line);
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
  /// Helper to check if a code unit is a valid identifier character
  /// Includes ASCII alphanumerics, underscore, and RTL script ranges
  bool _isIdentChar(int code) {
    return (code >= 48 && code <= 57) || // 0-9
        (code >= 65 && code <= 90) || // A-Z
        (code >= 97 && code <= 122) || // a-z
        code == 95 || // underscore
        (code >= 0x0600 && code <= 0x06FF) || // Arabic
        (code >= 0x08A0 && code <= 0x08FF) || // Extended Arabic
        (code >= 0x0590 && code <= 0x05FF); // Hebrew
  }

  bool _isIdentStartChar(int code) {
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        code == 95 ||
        (code >= 0x0600 && code <= 0x06FF) ||
        (code >= 0x08A0 && code <= 0x08FF) ||
        (code >= 0x0590 && code <= 0x05FF);
  }

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
        if (!_isIdentChar(code)) break;
        i--;
      }
      final start = i + 1;
      if (start >= col) return '';
      final firstCode = lineText.codeUnitAt(start);
      if (!_isIdentStartChar(firstCode)) return '';
      return lineText.substring(start, col);
    }

    if (safeOffset == 0) return '';
    int i = safeOffset - 1;
    while (i >= 0) {
      final code = text.codeUnitAt(i);
      if (!_isIdentChar(code)) break;
      i--;
    }
    final start = i + 1;
    if (start >= safeOffset) return '';
    final firstCode = text.codeUnitAt(start);
    if (!_isIdentStartChar(firstCode)) return '';
    return text.substring(start, safeOffset);
  }

  /// Refetch the current file to delflect text changes
  /// Only works if a valid file is provided via `filePath`.
  void refetchFile() {
    if (_openedFile != null) {
      text = File(_openedFile!).readAsStringSync();
    }
  }

  /// Disposes of the controller and releases resources.
  ///
  /// Call this method when the controller is no longer needed to prevent
  /// memory leaks.
  void dispose() {
    _isDisposed = true;
    _semanticTokenTimer?.cancel();
    _debounceTimer?.cancel();
    _flushTimer?.cancel();
    _codeActionTimer?.cancel();
    _documentColorTimer?.cancel();
    _foldRangesTimer?.cancel();
    _documentHighlightTimer?.cancel();
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

  /// Calls the [LSP signature help](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_signatureHelp) feature.
  ///
  /// This method requests signature help from the Language Server Protocol (LSP)
  /// for the current cursor position, displaying available parameters and
  /// highlighting the parameter in focus within function parentheses.
  Future<void> callSignatureHelp() async {
    if (lspConfig != null) {
      final cursorPosition = selection.extentOffset;
      final line = getLineAtOffset(cursorPosition);
      final lineStartOffset = getLineStartOffset(line);
      final character = cursorPosition - lineStartOffset;
      signatureNotifier.value = await lspConfig!.getSignatureHelp(
        openedFile!,
        line,
        character,
        1,
      );
    }
  }

  int _multiCursorToOffset(({int line, int character}) cursor) {
    final clampedLine = cursor.line.clamp(0, lineCount - 1);
    final lineText = getLineText(clampedLine);
    final clampedChar = cursor.character.clamp(0, lineText.length);
    return getLineStartOffset(clampedLine) + clampedChar;
  }

  bool _isAlpha(String s) {
    if (s.isEmpty) return false;
    final code = s.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        (code >= 0x0600 && code <= 0x06FF) ||
        (code >= 0x08A0 && code <= 0x08FF) ||
        (code >= 0x0590 && code <= 0x05FF);
  }

  bool _isCompletionTriggerChar(String s) {
    if (s.isEmpty) return false;
    return s == '.' || s == ':' || s == '>' || s == '/' || s == '@';
  }

  Future<void> _fetchSemanticTokensFull() async {
    if (lspConfig == null) return;
    if (_usesCclsSemanticHighlight) {
      return;
    }

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

  List<LspSemanticToken> _convertCclsSymbolsToTokens(List<dynamic> symbols) {
    final tokens = <LspSemanticToken>[];
    final maxLen = length;

    for (final symbol in symbols) {
      if (symbol is! Map<String, dynamic>) continue;

      final kind = symbol['kind'] as int? ?? 0;
      final storage = symbol['storage'] as int? ?? 0;
      final tokenTypeName = _cclsSymbolKindToTokenType(kind);
      final lsRanges = symbol['lsRanges'] as List<dynamic>?;
      final ranges = symbol['ranges'] as List<dynamic>?;

      if (lsRanges != null && lsRanges.isNotEmpty) {
        for (final range in lsRanges) {
          if (range is! List<dynamic> || range.length < 3) continue;
          final line = range[0] as int;
          final startChar = range[1] as int;
          final endChar = range[2] as int;

          tokens.add(
            LspSemanticToken(
              line: line,
              start: startChar,
              length: endChar - startChar,
              typeIndex: kind,
              modifierBitmask: storage,
              tokenTypeName: tokenTypeName,
            ),
          );
        }
      } else if (ranges != null && ranges.isNotEmpty) {
        for (final range in ranges) {
          if (range is! Map<String, dynamic>) continue;
          final startByte = range['L'] as int?;
          final endByte = range['R'] as int?;
          if (startByte == null ||
              endByte == null ||
              startByte < 0 ||
              endByte > maxLen) {
            continue;
          }

          final startLine = getLineAtOffset(startByte);
          final startChar = startByte - getLineStartOffset(startLine);

          final endLine = getLineAtOffset(endByte);
          final endChar = endByte - getLineStartOffset(endLine);

          if (startLine == endLine) {
            tokens.add(
              LspSemanticToken(
                line: startLine,
                start: startChar,
                length: endChar - startChar,
                typeIndex: kind,
                modifierBitmask: storage,
                tokenTypeName: tokenTypeName,
              ),
            );
          }
        }
      }
    }

    return tokens;
  }

  String _cclsSymbolKindToTokenType(int kind) {
    switch (kind) {
      case 0:
        return 'unknown';
      case 1:
        return 'file';
      case 2:
        return 'module';
      case 3:
        return 'namespace';
      case 4:
        return 'package';
      case 5:
        return 'class';
      case 6:
        return 'method';
      case 7:
        return 'property';
      case 8:
        return 'field';
      case 9:
        return 'constructor';
      case 10:
        return 'enum';
      case 11:
        return 'interface';
      case 12:
        return 'function';
      case 13:
        return 'variable';
      case 14:
        return 'constant';
      case 15:
        return 'string';
      case 16:
        return 'number';
      case 17:
        return 'boolean';
      case 18:
        return 'array';
      case 19:
        return 'object';
      case 20:
        return 'key';
      case 21:
        return 'null';
      case 22:
        return 'enumMember';
      case 23:
        return 'struct';
      case 24:
        return 'event';
      case 25:
        return 'operator';
      case 26:
        return 'typeParameter';
      case 252:
        return 'type';
      case 253:
        return 'parameter';
      case 254:
        return 'variable';
      case 255:
        return 'macro';
      default:
        return 'unknown';
    }
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
    if (_preComposingSelection != null) return; // Composing session (including the cleanup phase)
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
    if (_preComposingSelection != null) return; // Composing session (including the cleanup phase)
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

    // Composing has just ended: Only the final result is saved; undoing an action will return you directly to the state prior to composing.
    if (_preComposingSelection != null) {
      final savedSel = _preComposingSelection!;
      _preComposingSelection = null;
      _recordEdit(
        InsertOperation(
          offset: offset,
          text: inserted,
          selectionBefore: savedSel,
          selectionAfter: selAfter,
        ),
      );
      return;
    }

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

  void _scheduleSyncToConnection() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 50), () {
      _syncToConnection();
      _syncTimer = null;
    });
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
    _cachedBufferLines = null;

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

    if (hasMultiCursors &&
        insertedText.isNotEmpty &&
        !insertedText.contains('\n')) {
      insertAtAllCursors(insertedText);
      return;
    }

    final selectionBefore = _selection;
    final currentLength = text.length;
    if (offset < 0 || offset > currentLength) {
      return;
    }

    String actualInsertedText = insertedText;
    TextSelection actualSelection = newSelection;

    // IME composition: Do not pair parentheses; do not modify the original text
    if (!isComposing && insertedText.length == 1) {
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
      final isSingleNewline = actualInsertedText == '\n';

      if (isSingleNewline) {
        final currentText = text;
        final textBeforeCursor = currentText.substring(0, offset);
        final textAfterCursor = currentText.substring(offset);
        final lines = textBeforeCursor.split('\n');

        if (lines.isNotEmpty) {
          final prevLine = lines[lines.length - 1];
          final indentMatch = RegExp(r'^\s*').firstMatch(prevLine);
          final prevIndent = indentMatch?.group(0) ?? '';
          final shouldIndent = RegExp(r'[:{[(]\s*$').hasMatch(prevLine);
          final extraIndent = shouldIndent ? tabSpace : '';
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
      } else {
        actualSelection = TextSelection.collapsed(
          offset: offset + actualInsertedText.length,
        );
      }

      bool insertedViaBuffer = false;
      if (_bufferLineIndex != null && _bufferDirty) {
        final bufferEnd = _bufferLineRopeStart + _bufferLineText!.length;
        if (offset >= _bufferLineRopeStart && offset <= bufferEnd) {
          final localOffset = offset - _bufferLineRopeStart;
          if (localOffset >= 0 && localOffset <= _bufferLineText!.length) {
            _bufferLineText =
                _bufferLineText!.substring(0, localOffset) +
                    actualInsertedText +
                    _bufferLineText!.substring(localOffset);
            _bufferDirty = true;
            _cachedBufferLines = null;
            _selection = actualSelection;
            _currentVersion++;
            dirtyLine = _bufferLineIndex;

            insertedViaBuffer = true;
          }
        }
        if (!insertedViaBuffer) {
          _flushBuffer();
        }
      }

      if (!insertedViaBuffer) {
        final lineIndex = _rope.getLineAtOffset(offset);
        _initBuffer(lineIndex);
        final localOffset = offset - _bufferLineRopeStart;
        if (localOffset >= 0 && localOffset <= _bufferLineText!.length) {
          _bufferLineText =
              _bufferLineText!.substring(0, localOffset) +
                  actualInsertedText +
                  _bufferLineText!.substring(localOffset);
          _bufferDirty = true;
          _cachedBufferLines = null;
          _selection = actualSelection;
          _currentVersion++;
          dirtyLine = lineIndex;

          insertedViaBuffer = true;
        }
      }

      if (insertedViaBuffer) {
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

        _safelySyncEditingState();

        _scheduleFlush();
        notifyListeners();
        return;
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

      _safelySyncEditingState();

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

            _safelySyncEditingState();

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
        _cachedBufferLines = null;
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

        _safelySyncEditingState();

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
      _cachedBufferLines = null;
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

    if (hasMultiCursors &&
        range.end - range.start == 1 &&
        range.end == _selection.extentOffset) {
      backspaceAtAllCursors();
      return;
    }

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
      _cachedBufferLines = null;
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
    final starts = _foldedStartsSorted;
    final ends = _foldedEndsSorted;
    if (starts.isEmpty) return false;

    int lo = 0, hi = starts.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (starts[mid] < lineIndex) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }

    for (int i = hi; i >= 0; i--) {
      if (starts[i] >= lineIndex) continue;
      if (ends[i] >= lineIndex) return true;
      if (lineIndex - starts[i] > 100000) break;
    }
    return false;
  }

  int? _getFoldStartForLine(int lineIndex) {
    final starts = _foldedStartsSorted;
    final ends = _foldedEndsSorted;
    if (starts.isEmpty) return null;
    int lo = 0, hi = starts.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (starts[mid] < lineIndex) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    for (int i = hi; i >= 0; i--) {
      if (starts[i] >= lineIndex) continue;
      if (ends[i] >= lineIndex) return starts[i];
      if (lineIndex - starts[i] > 100000) break;
    }
    return null;
  }

  FoldRange? _getFoldRangeAtCurrentLine(int lineIndex) {
    return foldings[lineIndex];
  }

  static Set<String> _extractWords(String text) {
    final regExp = RegExp(r'[\w\u0600-\u06FF\u08A0-\u08FF\u0590-\u05FF]+');
    final set = <String>{};
    for (final match in regExp.allMatches(text)) {
      set.add(match.group(0)!);
    }
    return set;
  }
}