import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import '../AI_completion/ai.dart';
import '../LSP/lsp.dart';
import 'controller.dart';
import 'scroll.dart';
import 'styling.dart';
import 'syntax_highlighter.dart';

import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/vs2015.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

//TODO: Arrow key navigation in suggestion bar.
//TODO: Store text in a buffer.
//TODO: Rangse wise LSP semantic highlight.
//TODO: Keyboard shortcuts
//TODO: Public API methods in controller.

class CodeForge extends StatefulWidget {
  final CodeForgeController? controller;
  final Map<String, TextStyle>? editorTheme;
  final Mode? language;
  final FocusNode? focusNode;
  final TextStyle? textStyle;
  final AiCompletion? aiCompletion;
  final LspConfig? lspConfig;
  final EdgeInsets? innerPadding;
  final ScrollController? verticalScrollController;
  final ScrollController? horizontalScrollController;
  final CodeSelectionStyle? selectionStyle;
  final GutterStyle? gutterStyle;
  final SuggestionStyle? suggestionStyle;
  final HoverDetailsStyle? hoverDetailsStyle;
  final String? filePath;
  final String? initialText;
  final bool readOnly;
  final bool lineWrap;
  final bool autoFocus;
  final bool enableFolding;
  final bool enableGuideLines;
  final bool enableGutter;
  final bool enableGutterDivider;
  final bool enableSuggestions;

  const CodeForge({
    super.key,
    this.controller,
    this.editorTheme,
    this.language,
    this.aiCompletion,
    this.lspConfig,
    this.filePath,
    this.initialText,
    this.focusNode,
    this.verticalScrollController,
    this.horizontalScrollController,
    this.textStyle,
    this.innerPadding,
    this.readOnly = false,
    this.autoFocus = false,
    this.lineWrap = false,
    this.enableFolding = true,
    this.enableGuideLines = true,
    this.enableSuggestions = true,
    this.enableGutter = true,
    this.enableGutterDivider = false,
    this.selectionStyle,
    this.gutterStyle,
    this.suggestionStyle,
    this.hoverDetailsStyle,
  });

  @override
  State<CodeForge> createState() => _CodeForgeState();
}

class _CodeForgeState extends State<CodeForge>
    with SingleTickerProviderStateMixin {
  static const _semanticTokenDebounce = Duration(milliseconds: 500);
  late final ScrollController _hscrollController, _vscrollController;
  late final CodeForgeController _controller;
  late final FocusNode _focusNode;
  late final AnimationController _caretBlinkController;
  late final Map<String, TextStyle> _editorTheme;
  late final Mode _language;
  late final CodeSelectionStyle _selectionStyle;
  late final GutterStyle _gutterStyle;
  late final SuggestionStyle _suggestionStyle;
  late final HoverDetailsStyle _hoverDetailsStyle;
  late final ValueNotifier<List<dynamic>?> _suggestionNotifier, _hoverNotifier;
  late final ValueNotifier<List<LspErrors>> _diagnosticsNotifier;
  late final ValueNotifier<String?> _aiNotifier;
  late final ValueNotifier<Offset?> _aiOffsetNotifier;
  late final ValueNotifier<Offset> _contextMenuOffsetNotifier;
  late final ValueNotifier<bool> _selectionActiveNotifier, _isHoveringPopup;
  final ValueNotifier<Offset> _offsetNotifier = ValueNotifier(Offset(0, 0));
  final Map<String, String> _cachedResponse = {};
  final _isMobile = Platform.isAndroid || Platform.isIOS;
  final _suggScrollController = ScrollController();
  TextInputConnection? _connection;
  bool _lspReady = false, _isHovering = false, _isTyping = false;
  String _previousValue = "";
  List<LspSemanticToken>? _semanticTokens;
  DateTime? _lastSemanticTokenFetch;
  int _sugSelIndex = 0;
  Timer? _hoverTimer, _aiDebounceTimer;
  List<dynamic> _suggestions = [];
  TextSelection _prevSelection = TextSelection.collapsed(offset: 0);

  @override
  void initState() {
    super.initState();

    _controller = widget.controller ?? CodeForgeController();
    _focusNode = widget.focusNode ?? FocusNode();
    _hscrollController =
        widget.horizontalScrollController ?? ScrollController();
    _vscrollController = widget.verticalScrollController ?? ScrollController();
    _editorTheme = widget.editorTheme ?? vs2015Theme;
    _language = widget.language ?? langPython;
    _suggestionNotifier = ValueNotifier(null);
    _hoverNotifier = ValueNotifier(null);
    _diagnosticsNotifier = ValueNotifier<List<LspErrors>>([]);
    _aiNotifier = ValueNotifier(null);
    _aiOffsetNotifier = ValueNotifier(null);
    _contextMenuOffsetNotifier = ValueNotifier(const Offset(-1, -1));
    _selectionActiveNotifier = ValueNotifier(false);
    _isHoveringPopup = ValueNotifier<bool>(false);
    _controller.manualAiCompletion = getManualAiSuggestion;
    _controller.readOnly = widget.readOnly;
    _selectionStyle = widget.selectionStyle ?? CodeSelectionStyle();

    _gutterStyle =
        widget.gutterStyle ??
        GutterStyle(
          lineNumberStyle: widget.textStyle ?? _editorTheme['root'],
          foldedIconColor: _editorTheme['root']?.color,
          unfoldedIconColor: _editorTheme['root']?.color,
          backgroundColor: _editorTheme['root']?.backgroundColor,
        );

    _suggestionStyle =
        widget.suggestionStyle ??
        SuggestionStyle(
          elevation: 6,
          textStyle: (() {
            TextStyle style = widget.textStyle ?? TextStyle();
            if (style.color == null) {
              style = style.copyWith(color: _editorTheme['root']!.color);
            }
            return style;
          })(),
          backgroundColor: _editorTheme['root']!.backgroundColor!,
          focusColor: Colors.blueAccent.withAlpha(50),
          hoverColor: Colors.grey.withAlpha(15),
          splashColor: Colors.blueAccent.withAlpha(50),
          shape: BeveledRectangleBorder(
            side: BorderSide(
              color: _editorTheme['root']!.color ?? Colors.grey[400]!,
              width: 0.2,
            ),
          ),
        );

    _hoverDetailsStyle =
        widget.hoverDetailsStyle ??
        HoverDetailsStyle(
          shape: BeveledRectangleBorder(
            side: BorderSide(
              color: _editorTheme['root']!.color ?? Colors.grey[400]!,
              width: 0.2,
            ),
          ),
          backgroundColor: _editorTheme['root']!.backgroundColor!,
          focusColor: Colors.blueAccent.withAlpha(50),
          hoverColor: Colors.grey.withAlpha(15),
          splashColor: Colors.blueAccent.withAlpha(50),
          textStyle: (() {
            TextStyle style = widget.textStyle ?? _editorTheme['root']!;
            if (style.color == null) {
              style = style.copyWith(color: _editorTheme['root']!.color);
            }
            return style;
          })(),
        );

    _caretBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    _focusNode.addListener(() {
      if (_focusNode.hasFocus && !widget.readOnly) {
        if (_connection == null || !_connection!.attached) {
          _connection = TextInput.attach(
            _controller,
            const TextInputConfiguration(
              readOnly: false,
              enableDeltaModel: true,
              inputType: TextInputType.multiline,
              inputAction: TextInputAction.newline,
              autocorrect: false,
            ),
          );

          _controller.connection = _connection;
          _connection!.show();
          _connection!.setEditingState(
            TextEditingValue(
              text: _controller.text,
              selection: _controller.selection,
            ),
          );
        }
      }
    });

    if (widget.filePath != null) {
      if (widget.initialText != null) {
        throw ArgumentError(
          'Cannot provide both filePath and initialText to CodeForge.',
        );
      } else if (widget.filePath!.isNotEmpty) {
        _controller.text = File(widget.filePath!).readAsStringSync();
      }
    } else if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _controller.text = widget.initialText!;
    }

    if (widget.lspConfig != null) {
      if ((widget.lspConfig!.filePath != widget.filePath) ||
          widget.filePath == null) {
        throw Exception(
          'File path in LspConfig does not match the provided filePath in CodeForge.',
        );
      }

      (() async {
        final lspConfig = widget.lspConfig;
        try {
          if (lspConfig is LspSocketConfig) {
            await lspConfig.connect();
          }
          await lspConfig!.initialize();
          await Future.delayed(const Duration(milliseconds: 300));
          await lspConfig.openDocument(initialContent: _controller.text);
          setState(() {
            _lspReady = true;
          });
          await _fetchSemanticTokens();
        } catch (e) {
          debugPrint('Error initializing LSP: $e');
        }
      })();

      widget.lspConfig!.responses.listen((data) {
        if (data['method'] == 'textDocument/publishDiagnostics') {
          final diagnostics = data['params']['diagnostics'] as List;
          if (diagnostics.isNotEmpty) {
            final List<LspErrors> errors = [];
            for (final item in diagnostics) {
              final d = item as Map<String, dynamic>;
              int severity = d['severity'] ?? 0;
              if (severity == 1 && widget.lspConfig!.disableError) {
                severity = 0;
              }
              if (severity == 2 && widget.lspConfig!.disableWarning) {
                severity = 0;
              }
              if (severity > 0) {
                errors.add(
                  LspErrors(
                    severity: severity,
                    range: d['range'],
                    message: d['message'] ?? '',
                  ),
                );
              }
            }
            _diagnosticsNotifier.value = errors;
          } else {
            _diagnosticsNotifier.value = [];
          }
        }
      });
    }

    _controller.addListener(() {
      final text = _controller.text;
      final currentSelection = _controller.selection;
      final cursorPosition = currentSelection.extentOffset;
      final line = _controller.getLineAtOffset(cursorPosition);
      final lineStartOffset = _controller.getLineStartOffset(line);
      final character = cursorPosition - lineStartOffset;
      final prefix = _getCurrentWordPrefix(text, cursorPosition);

      _isTyping = false;

      _resetCursorBlink();

      final oldText = _previousValue;
      final oldSelection = _prevSelection;

      if(_hoverNotifier.value != null){
        _hoverNotifier.value = null;
      }

      if (
        widget.lspConfig != null &&
        _lspReady &&
        text != _previousValue
      ) {
        _previousValue = text;
        (() async {
          final lspConfig = widget.lspConfig!;
          await lspConfig.updateDocument(text);
          final suggestion = await lspConfig.getCompletions(
            line,
            character,
          );
          _suggestions = suggestion;
        })();
        _scheduleSemantictokenRefresh();
      }

      _aiDebounceTimer?.cancel();

      if(
        widget.aiCompletion != null &&
        _controller.selection.isValid &&
        widget.aiCompletion!.enableCompletion &&
        _aiNotifier.value == null
      ){
        if(_suggestionNotifier.value != null) return;
        final text = _controller.text;
        final cursorPosition = _controller.selection.extentOffset.clamp(0, _controller.length);
        final textAfterCursor = text.substring(cursorPosition);
        if(cursorPosition <= 0) return;
        bool lineEnd = textAfterCursor.isEmpty ||
              textAfterCursor.startsWith('\n') ||
              textAfterCursor.trim().isEmpty;
        if(!lineEnd) return;
        final codeToSend = "${text.substring(0, cursorPosition)}<|CURSOR|>${text.substring(cursorPosition)}";
        if(
          widget.aiCompletion!.completionType == CompletionType.auto ||
          widget.aiCompletion!.completionType == CompletionType.mixed
        ){
          _aiDebounceTimer = Timer(
            Duration(milliseconds: widget.aiCompletion!.debounceTime),
            () async{
              _aiNotifier.value = await _getCachedResponse(codeToSend);
            }
          );
        }
      }

      if (text.length == oldText.length + 1 &&
          currentSelection.baseOffset == oldSelection.baseOffset + 1) {
        final insertedChar = text.substring(
          _prevSelection.baseOffset,
          currentSelection.baseOffset,
        );
        _isTyping =
            insertedChar.isNotEmpty &&
            RegExp(r'[a-zA-Z]').hasMatch(insertedChar);
        if (widget.enableSuggestions &&
            _isTyping &&
            prefix.isNotEmpty &&
            _controller.selection.extentOffset > 0) {
          if (widget.lspConfig == null) {
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
          }
          _sortSuggestions(prefix);
          final triggerChar = text[cursorPosition - 1];
          if (!RegExp(r'[a-zA-Z]').hasMatch(triggerChar)) {
            _suggestionNotifier.value = null;
            return;
          }
          if (mounted && _suggestions.isNotEmpty) {
            _sugSelIndex = 0;
            _suggestionNotifier.value = _suggestions;
          }
        } else {
          _suggestionNotifier.value = null;
        }
      }

      _previousValue = text;
      _prevSelection = currentSelection;
    });

    WidgetsBinding.instance.addPostFrameCallback((_){
      if(widget.autoFocus){
        _focusNode.requestFocus();
      }
    });
  }

  String _getCurrentWordPrefix(String text, int offset) {
    final safeOffset = offset.clamp(0, text.length);
    final beforeCursor = text.substring(0, safeOffset);
    final match = RegExp(r'([a-zA-Z_][a-zA-Z0-9_]*)$').firstMatch(beforeCursor);
    return match?.group(0) ?? '';
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
      if (charBefore.toLowerCase() == charBefore && matchChar.toUpperCase() == matchChar) {
        score += 5000;
      } else if (charBefore == '_' || charBefore == '-') {
        score += 5000;
      }
    }
    
    score -= label.length;
    
    return score;
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

  Future<void> _fetchSemanticTokens() async {
    if (widget.lspConfig == null || !_lspReady) return;

    try {
      final tokens = await widget.lspConfig!.getSemanticTokensFull();
      setState(() {
        _semanticTokens = tokens;
        _lastSemanticTokenFetch = DateTime.now();
      });
    } catch (e) {
      debugPrint('Error fetching semantic tokens: $e');
    }
  }

  void _scheduleSemantictokenRefresh() {
    final now = DateTime.now();
    if (_lastSemanticTokenFetch == null ||
        now.difference(_lastSemanticTokenFetch!) > _semanticTokenDebounce) {
      Future.delayed(_semanticTokenDebounce, () async{
        if (mounted && _lspReady) {
          await _fetchSemanticTokens();
        }
      });
    }
  }

  void _resetCursorBlink() {
    if (!mounted) return;
    _caretBlinkController.value = 1.0;
    _caretBlinkController
      ..stop()
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.removeListener(_resetCursorBlink);
    _connection?.close();
    _caretBlinkController.dispose();
    _suggestionNotifier.dispose();
    _hoverNotifier.dispose();
    _diagnosticsNotifier.dispose();
    _aiNotifier.dispose();
    _aiOffsetNotifier.dispose();
    _contextMenuOffsetNotifier.dispose();
    _selectionActiveNotifier.dispose();
    _isHoveringPopup.dispose();
    _hoverTimer?.cancel();
    _aiDebounceTimer?.cancel();
    super.dispose();
  }

  void _handleArrowLeft(bool withShift) {
    final sel = _controller.selection;

    int newOffset;
    if (!withShift && sel.start != sel.end) {
      newOffset = sel.start;
    } else if (sel.extentOffset > 0) {
      newOffset = sel.extentOffset - 1;
    } else {
      newOffset = 0;
    }

    if (withShift) {
      _controller.setSelectionSilently(
        TextSelection(baseOffset: sel.baseOffset, extentOffset: newOffset),
      );
    } else {
      _controller.setSelectionSilently(
        TextSelection.collapsed(offset: newOffset),
      );
    }
  }

  void _handleArrowRight(bool withShift) {
    if(_aiNotifier.value != null){
      _acceptAiCompletion();
      return;
    }

    final sel = _controller.selection;
    final textLength = _controller.length;

    int newOffset;
    if (!withShift && sel.start != sel.end) {
      newOffset = sel.end;
    } else if (sel.extentOffset < textLength) {
      newOffset = sel.extentOffset + 1;
    } else {
      newOffset = textLength;
    }

    if (withShift) {
      _controller.setSelectionSilently(
        TextSelection(baseOffset: sel.baseOffset, extentOffset: newOffset),
      );
    } else {
      _controller.setSelectionSilently(
        TextSelection.collapsed(offset: newOffset),
      );
    }
  }

  void _handleArrowUp(bool withShift) {
    final sel = _controller.selection;
    final currentLine = _controller.getLineAtOffset(sel.extentOffset);

    if (currentLine <= 0) {
      if (withShift) {
        _controller.setSelectionSilently(
          TextSelection(baseOffset: sel.baseOffset, extentOffset: 0),
        );
      } else {
        _controller.setSelectionSilently(
          const TextSelection.collapsed(offset: 0),
        );
      }
      return;
    }

    final lineStart = _controller.getLineStartOffset(currentLine);
    final column = sel.extentOffset - lineStart;
    final prevLineStart = _controller.getLineStartOffset(currentLine - 1);
    final prevLineText = _controller.getLineText(currentLine - 1);
    final prevLineLength = prevLineText.length;
    final newColumn = column.clamp(0, prevLineLength);
    final newOffset = (prevLineStart + newColumn).clamp(0, _controller.length);

    if (withShift) {
      _controller.setSelectionSilently(
        TextSelection(baseOffset: sel.baseOffset, extentOffset: newOffset),
      );
    } else {
      _controller.setSelectionSilently(
        TextSelection.collapsed(offset: newOffset),
      );
    }
  }

  void _handleArrowDown(bool withShift) {
    final sel = _controller.selection;
    final currentLine = _controller.getLineAtOffset(sel.extentOffset);
    final lineCount = _controller.lineCount;

    if (currentLine >= lineCount - 1) {
      final endOffset = _controller.length;
      if (withShift) {
        _controller.setSelectionSilently(
          TextSelection(baseOffset: sel.baseOffset, extentOffset: endOffset),
        );
      } else {
        _controller.setSelectionSilently(
          TextSelection.collapsed(offset: endOffset),
        );
      }
      return;
    }

    final lineStart = _controller.getLineStartOffset(currentLine);
    final column = sel.extentOffset - lineStart;
    final nextLineStart = _controller.getLineStartOffset(currentLine + 1);
    final nextLineText = _controller.getLineText(currentLine + 1);
    final nextLineLength = nextLineText.length;
    final newColumn = column.clamp(0, nextLineLength);
    final newOffset = (nextLineStart + newColumn).clamp(0, _controller.length);

    if (withShift) {
      _controller.setSelectionSilently(
        TextSelection(baseOffset: sel.baseOffset, extentOffset: newOffset),
      );
    } else {
      _controller.setSelectionSilently(
        TextSelection.collapsed(offset: newOffset),
      );
    }
  }

  void _handleHome(bool withShift) {
    final sel = _controller.selection;
    final currentLine = _controller.getLineAtOffset(sel.extentOffset);
    final lineStart = _controller.getLineStartOffset(currentLine);

    if (withShift) {
      _controller.setSelectionSilently(
        TextSelection(baseOffset: sel.baseOffset, extentOffset: lineStart),
      );
    } else {
      _controller.setSelectionSilently(
        TextSelection.collapsed(offset: lineStart),
      );
    }
  }

  void _handleEnd(bool withShift) {
    final sel = _controller.selection;
    final currentLine = _controller.getLineAtOffset(sel.extentOffset);
    final lineText = _controller.getLineText(currentLine);
    final lineStart = _controller.getLineStartOffset(currentLine);
    final lineEnd = lineStart + lineText.length;

    if (withShift) {
      _controller.setSelectionSilently(
        TextSelection(baseOffset: sel.baseOffset, extentOffset: lineEnd),
      );
    } else {
      _controller.setSelectionSilently(
        TextSelection.collapsed(offset: lineEnd),
      );
    }
  }

  void _copy() {
    final sel = _controller.selection;
    if (sel.start == sel.end) return;
    final selectedText = _controller.text.substring(sel.start, sel.end);
    Clipboard.setData(ClipboardData(text: selectedText));
  }

  void _cut() {
    final sel = _controller.selection;
    if (sel.start == sel.end) return;
    final selectedText = _controller.text.substring(sel.start, sel.end);
    Clipboard.setData(ClipboardData(text: selectedText));
    _controller.replaceRange(sel.start, sel.end, '');
    _contextMenuOffsetNotifier.value = const Offset(-1, -1);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    final sel = _controller.selection;
    _controller.replaceRange(sel.start, sel.end, data.text!);
    _contextMenuOffsetNotifier.value = const Offset(-1, -1);
  }

  void _selectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.length,
    );
    _contextMenuOffsetNotifier.value = const Offset(-1, -1);
  }

  Widget _buildContextMenu() {
    return ValueListenableBuilder<Offset>(
      valueListenable: _contextMenuOffsetNotifier,
      builder: (context, offset, _) {
        if (offset.dx < 0 || offset.dy < 0) return const SizedBox.shrink();

        final hasSelection =
            _controller.selection.start != _controller.selection.end;

        if (_isMobile) {
          return Positioned(
            left: offset.dx,
            top: offset.dy - 60,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              color: _editorTheme['root']?.backgroundColor ?? Colors.grey[900],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasSelection) ...[
                    _buildContextMenuItem('Cut', Icons.cut, _cut),
                    _buildContextMenuItem('Copy', Icons.copy, _copy),
                  ],
                  _buildContextMenuItem('Paste', Icons.paste, () => _paste()),
                  _buildContextMenuItem(
                    'Select All',
                    Icons.select_all,
                    _selectAll,
                  ),
                ],
              ),
            ),
          );
        } else {
          return Positioned(
            left: offset.dx,
            top: offset.dy,
            child: Card(
              elevation: 8,
              color: _editorTheme['root']?.backgroundColor ?? Colors.grey[900],
              shape: _suggestionStyle.shape,
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasSelection) ...[
                      _buildDesktopContextMenuItem('Cut', 'Ctrl+X', _cut),
                      _buildDesktopContextMenuItem('Copy', 'Ctrl+C', _copy),
                    ],
                    _buildDesktopContextMenuItem(
                      'Paste',
                      'Ctrl+V',
                      () => _paste(),
                    ),
                    _buildDesktopContextMenuItem(
                      'Select All',
                      'Ctrl+A',
                      _selectAll,
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildContextMenuItem(
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: () {
        onTap();
        _contextMenuOffsetNotifier.value = const Offset(-1, -1);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: _editorTheme['root']?.color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: _editorTheme['root']?.color,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopContextMenuItem(
    String label,
    String shortcut,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: () {
        onTap();
        _contextMenuOffsetNotifier.value = const Offset(-1, -1);
      },
      hoverColor: _suggestionStyle.hoverColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: _suggestionStyle.textStyle),
            const SizedBox(width: 24),
            Text(
              shortcut,
              style: _suggestionStyle.textStyle.copyWith(
                color: _suggestionStyle.textStyle.color!.withAlpha(150),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _commonKeyFunctions(){
    if(_aiNotifier.value != null){
      _aiNotifier.value = null;
    }

    _resetCursorBlink();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    return LayoutBuilder(
      builder: (_, constraints) {
        return Stack(
          children: [
            GestureDetector(
              onTap: () {
                _connection?.show();
                _focusNode.requestFocus();
                _contextMenuOffsetNotifier.value = const Offset(-1, -1);
              },
              child: RawScrollbar(
                controller: _vscrollController,
                thumbVisibility: _isHovering,
                child: RawScrollbar(
                  thumbVisibility: _isHovering,
                  controller: _hscrollController,
                  child: MouseRegion(
                    onEnter: (event) => setState(() => _isHovering = true),
                    onExit: (event) => setState(() => _isHovering = false),
                    child: ValueListenableBuilder(
                      valueListenable: _selectionActiveNotifier,
                      builder: (context, selVal, child) {
                        return TwoDimensionalScrollable(
                          horizontalDetails: ScrollableDetails.horizontal(
                            controller: _hscrollController,
                            physics: selVal ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                          ),
                          verticalDetails: ScrollableDetails.vertical(
                            controller: _vscrollController,
                            physics: selVal ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                          ),
                          viewportBuilder: (_, voffset, hoffset) => CustomViewport(
                            verticalOffset: voffset,
                            verticalAxisDirection: AxisDirection.down,
                            horizontalOffset: hoffset,
                            horizontalAxisDirection: AxisDirection.right,
                            mainAxis: Axis.vertical,
                            delegate: TwoDimensionalChildBuilderDelegate(
                              maxXIndex: 0,
                              maxYIndex: 0,
                              builder: (_, vic) {
                                return Focus(
                                  focusNode: _focusNode,
                                  onKeyEvent: (node, event) {
                                    if (event is KeyDownEvent || event is KeyRepeatEvent) {
                                      final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                                      final isCtrlPressed = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
                                      if (_suggestionNotifier.value != null && _suggestionNotifier.value!.isNotEmpty) {
                                        switch (event.logicalKey) {
                                          case LogicalKeyboardKey.arrowDown:
                                            setState(() {
                                              _sugSelIndex = (_sugSelIndex + 1) % _suggestionNotifier.value!.length;
                                            });
                                            return KeyEventResult.handled;
                                          case LogicalKeyboardKey.arrowUp:
                                            setState(() {
                                              _sugSelIndex = (_sugSelIndex - 1 + _suggestionNotifier .value! .length) % _suggestionNotifier.value!.length;
                                            });
                                            return KeyEventResult.handled;
                                          case LogicalKeyboardKey.enter:
                                          case LogicalKeyboardKey.tab:
                                            _acceptSuggestion();
                                            return KeyEventResult.handled;
                                          case LogicalKeyboardKey.escape:
                                            _suggestionNotifier.value = null;
                                            return KeyEventResult.handled;
                                          default:
                                            break;
                                        }
                                      }
                        
                                      if (isCtrlPressed) {
                                        switch (event.logicalKey) {
                                          case LogicalKeyboardKey.keyC:
                                            _copy();
                                            return KeyEventResult.handled;
                                          case LogicalKeyboardKey.keyX:
                                            _cut();
                                            return KeyEventResult.handled;
                                          case LogicalKeyboardKey.keyV:
                                            _paste();
                                            return KeyEventResult.handled;
                                          case LogicalKeyboardKey.keyA:
                                            _selectAll();
                                            return KeyEventResult.handled;
                                          default:
                                            break;
                                        }
                                      }
                        
                                      switch (event.logicalKey) {
                                        case LogicalKeyboardKey.backspace:
                                          _controller.backspace();
                                          if(_suggestionNotifier.value != null){
                                            _suggestionNotifier.value = null;
                                          }
                                          _commonKeyFunctions();
                                          return KeyEventResult.handled;
                        
                                        case LogicalKeyboardKey.delete:
                                          _controller.delete();
                                          if(_suggestionNotifier.value != null){
                                            _suggestionNotifier.value = null;
                                          }
                                          _commonKeyFunctions();
                                          return KeyEventResult.handled;
                        
                                        case LogicalKeyboardKey.arrowDown:
                                          _handleArrowDown(isShiftPressed);
                                          _commonKeyFunctions();
                                          return KeyEventResult.handled;
                        
                                        case LogicalKeyboardKey.arrowUp:
                                          _handleArrowUp(isShiftPressed);
                                          _commonKeyFunctions();
                                          return KeyEventResult.handled;
                        
                                        case LogicalKeyboardKey.arrowRight:
                                          _handleArrowRight(isShiftPressed);
                                          _commonKeyFunctions();
                                          return KeyEventResult.handled;
                        
                                        case LogicalKeyboardKey.arrowLeft:
                                          _handleArrowLeft(isShiftPressed);
                                          _commonKeyFunctions();
                                          return KeyEventResult.handled;
                        
                                        case LogicalKeyboardKey.home:
                                          if(_suggestionNotifier.value != null){
                                              _suggestionNotifier.value = null;
                                          }
                                          _handleHome(isShiftPressed);
                                          _commonKeyFunctions();
                                          return KeyEventResult.handled;
                        
                                        case LogicalKeyboardKey.end:
                                          if(_suggestionNotifier.value != null){
                                            _suggestionNotifier.value = null;
                                          }
                                          _handleEnd(isShiftPressed);
                                          _commonKeyFunctions();
                                          return KeyEventResult.handled;
                        
                                        case LogicalKeyboardKey.escape:
                                          _contextMenuOffsetNotifier.value =
                                              const Offset(-1, -1);
                                          _aiNotifier.value = null;
                                          _suggestionNotifier.value = null;
                                          return KeyEventResult.handled;
                        
                                        case LogicalKeyboardKey.tab:
                                          if(_aiNotifier.value != null){
                                            _acceptAiCompletion();
                                          } else if(_suggestionNotifier.value == null) {
                                            _controller.insertAtCurrentCursor('\t');
                                          }
                                          return KeyEventResult.handled;
                        
                                        case LogicalKeyboardKey.enter:
                                          if(_aiNotifier.value != null){
                                            _aiNotifier.value = null;
                                          }
                                          break;
                                        default:
                                      }
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  child: _CodeField(
                                    context: context,
                                    controller: _controller,
                                    editorTheme: _editorTheme,
                                    language: _language,
                                    languageId: widget.lspConfig?.languageId,
                                    lspConfig: widget.lspConfig,
                                    semanticTokens: _semanticTokens,
                                    innerPadding: widget.innerPadding,
                                    vscrollController: _vscrollController,
                                    hscrollController: _hscrollController,
                                    focusNode: _focusNode,
                                    readOnly: widget.readOnly,
                                    caretBlinkController: _caretBlinkController,
                                    textStyle: widget.textStyle,
                                    enableFolding: widget.enableFolding,
                                    enableGuideLines: widget.enableGuideLines,
                                    enableGutter: widget.enableGutter,
                                    enableGutterDivider: widget.enableGutterDivider,
                                    gutterStyle: _gutterStyle,
                                    selectionStyle: _selectionStyle,
                                    diagnostics: _diagnosticsNotifier.value,
                                    isMobile: _isMobile,
                                    selectionActiveNotifier:
                                        _selectionActiveNotifier,
                                    contextMenuOffsetNotifier:
                                        _contextMenuOffsetNotifier,
                                    hoverNotifier: _hoverNotifier,
                                    lineWrap: widget.lineWrap,
                                    offsetNotifier: _offsetNotifier,
                                    aiNotifier: _aiNotifier,
                                    aiOffsetNotifier: _aiOffsetNotifier,
                                    isHoveringPopup: _isHoveringPopup,
                                    suggestionNotifier: _suggestionNotifier,
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      }
                    ),
                  ),
                ),
              ),
            ),
            _buildContextMenu(),
            ValueListenableBuilder(
              valueListenable: _offsetNotifier,
              builder: (context, offset, child) {
                if(offset.dy < 0 || offset.dx < 0) return SizedBox.shrink();
                return ValueListenableBuilder(
                  valueListenable: _suggestionNotifier,
                  builder: (_, sugg, child) {
                    if(_aiNotifier.value != null) return SizedBox.shrink();
                    if (sugg == null) {
                      _sugSelIndex = 0;
                      return SizedBox.shrink();
                    }
                    return Positioned(
                      width: screenWidth < 700
                          ? screenWidth * 0.63
                          : screenWidth * 0.3,
                      top:
                          offset.dy +
                          (widget.textStyle?.fontSize ?? 14) +
                          10,
                      left: offset.dx,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: 400,
                          maxWidth: 400,
                          minWidth: 70,
                        ),
                        child: Card(
                          shape: _suggestionStyle.shape,
                          elevation: _suggestionStyle.elevation,
                          color: _suggestionStyle.backgroundColor,
                          margin: EdgeInsets.zero,
                          child: RawScrollbar(
                            thumbVisibility: true,
                            thumbColor: _editorTheme['root']!.color!.withAlpha(80),
                            controller: _suggScrollController,
                            child: ListView.builder(
                              itemExtent: (widget.textStyle?.fontSize ?? 14) + 6.5,
                              controller: _suggScrollController,
                              padding: EdgeInsets.only(right: 5),
                              shrinkWrap: true,
                              itemCount: sugg.length,
                              itemBuilder: (_, indx) {
                                final item = sugg[indx];
                                return Container(
                                  color: _sugSelIndex == indx
                                    ? Color(0xff024281)
                                    : Colors.transparent,
                                  child: InkWell(
                                    canRequestFocus: false,
                                    hoverColor: _suggestionStyle.hoverColor,
                                    focusColor: _suggestionStyle.focusColor,
                                    splashColor: _suggestionStyle.splashColor,
                                    onTap: () => setState(() {
                                      _sugSelIndex = indx;
                                      final text = item is LspCompletion ? item.label : item as String;
                                      _controller.insertAtCurrentCursor(text, replaceTypedChar: true);
                                      _suggestionNotifier.value = null;
                                    }),
                                    child: Row(
                                      children: [
                                        if (item is LspCompletion) ...[
                                          item.icon,
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              item.label,
                                              style: _suggestionStyle.textStyle,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if(item.importUri?[0] != null)
                                          Text(
                                            item.importUri![0],
                                            style: _suggestionStyle.textStyle.copyWith(
                                              color: _suggestionStyle.textStyle.color?.withAlpha(150)
                                            )
                                          )
                                        ],
                                        if (item is String)
                                          Expanded(
                                            child: Text(
                                              item,
                                              style: _suggestionStyle.textStyle,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              }
            ),
            ValueListenableBuilder(
              valueListenable: _hoverNotifier,
              builder: (_, hov, c){
                if(hov == null || widget.lspConfig == null) return SizedBox.shrink();
                final Offset position = hov[0];
                final Map<String, int> lineChar = hov[1];
                final hoverScrollController = ScrollController();
                final width = _isMobile ? screenWidth * 0.63 : screenWidth * 0.3;
                final maxHeight = _isMobile ? screenHeight * 0.4 : 550.0;
                return Positioned(
                  top: position.dy,
                  left: position.dx,
                  child: MouseRegion(
                    onEnter: (_) => _isHoveringPopup.value = true,
                    onExit: (_) => _isHoveringPopup.value = false,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: width,
                        maxHeight: maxHeight
                      ),
                      child: Card(
                        color: _hoverDetailsStyle.backgroundColor,
                        shape: _hoverDetailsStyle.shape,
                        child: FutureBuilder<String>(
                            future: (() async{
                              final lspConfig = widget.lspConfig;
                              final line = lineChar['line']!;
                              final character = lineChar['character']!;
                              final diagnostic = _diagnosticsNotifier.value.firstWhere(
                                (diag) {
                                  final diagStartLine = diag.range['start']['line'] as int;
                                  final diagEndLine = diag.range['end']['line'] as int;
                                  final diagStartChar = diag.range['start']['character'] as int;
                                  final diagEndChar = diag.range['end']['character'] as int;
                                  
                                  if (line < diagStartLine || line > diagEndLine) {
                                    return false;
                                  }
                                  
                                  if (line == diagStartLine && line == diagEndLine) {
                                    return character >= diagStartChar && character < diagEndChar;
                                  } else if (line == diagStartLine) {
                                    return character >= diagStartChar;
                                  } else if (line == diagEndLine) {
                                    return character < diagEndChar;
                                  } else {
                                    return true;
                                  }
                                },
                                orElse: () => LspErrors(severity: 0, range: {}, message: ''),
                              );
                        
                              if(diagnostic.message.isNotEmpty){
                                return diagnostic.message;
                              }
                        
                              if(lspConfig != null){
                                return await lspConfig.getHover(line, character);
                              }
                        
                              final hoverDetails = await lspConfig!.getHover(line, character);
                              return hoverDetails;
                            })(),
                            builder: (_, snapShot) {
                              if (snapShot.hasError) {
                                return SizedBox.shrink();
                              }
                              final data = snapShot.data;
                              if (data == null || data.isEmpty) {
                                return SizedBox.shrink();
                              }
                              if (snapShot.connectionState == ConnectionState.waiting) {
                                return Text(
                                  "Loading...",
                                  style: _hoverDetailsStyle.textStyle,
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: RawScrollbar(
                                  controller: hoverScrollController,
                                  thumbVisibility: true,
                                  thumbColor: _editorTheme['root']!.color!.withAlpha(100),
                                  child: SingleChildScrollView(
                                    controller: hoverScrollController,
                                    child: MarkdownBlock(
                                      data: data,
                                      config: MarkdownConfig.darkConfig.copy(
                                        configs: [
                                          PConfig(
                                            textStyle: _hoverDetailsStyle.textStyle
                                          ),
                                          PreConfig(
                                            language: widget.lspConfig?.languageId ?? "dart",
                                            theme: _editorTheme,
                                            textStyle: TextStyle(
                                              fontSize: _hoverDetailsStyle.textStyle.fontSize
                                            ),
                                            styleNotMatched: TextStyle(
                                              color: _editorTheme['root']!.color
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.zero,
                                              border: Border.all(
                                                width: 0.2,
                                                color: _editorTheme['root']!.color ?? Colors.grey
                                              )
                                            )
                                          )
                                        ]
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }
                          ),
                      ),
                    ),
                  ),
                );
              }
            )
          ],
        );
      },
    );
  }

  void _acceptSuggestion() {
    final suggestions = _suggestionNotifier.value;
    if (suggestions == null || suggestions.isEmpty) return;

    final selected = suggestions[_sugSelIndex];
    String insertText = '';

    if (selected is LspCompletion) {
      insertText = selected.label;
    } else if (selected is Map) {
      insertText = selected['insertText'] ?? selected['label'] ?? '';
    } else if (selected is String) {
      insertText = selected;
    }

    if (insertText.isNotEmpty) {
      _controller.insertAtCurrentCursor(insertText, replaceTypedChar: true);
    }

    _suggestionNotifier.value = null;
    _sugSelIndex = 0;
  }

  Future<void> getManualAiSuggestion() async {
    _suggestionNotifier.value = null;
    if (widget.aiCompletion?.completionType == CompletionType.manual ||
        widget.aiCompletion?.completionType == CompletionType.mixed) {
      final String text = _controller.text;
      final int cursorPosition = _controller.selection.extentOffset;
      final String codeToSend = "${text.substring(0, cursorPosition)}<|CURSOR|>${text.substring(cursorPosition)}";
      _aiNotifier.value = await _getCachedResponse(codeToSend);
    }
  }

  Future<String> _getCachedResponse(String codeToSend) async {
    final String key = codeToSend.hashCode.toString();
    if (_cachedResponse.containsKey(key)) {
      return _cachedResponse[key]!;
    }
    final String aiResponse = await widget.aiCompletion!.model.completionResponse(codeToSend);
    _cachedResponse[key] = aiResponse;
    return aiResponse;
  }

  void _acceptAiCompletion() {
    final aiText = _aiNotifier.value;
    if (aiText == null || aiText.isEmpty) return;
    _controller.insertAtCurrentCursor(aiText);
    _aiNotifier.value = null;
    _aiOffsetNotifier.value = null;
  }


}

class _CodeField extends LeafRenderObjectWidget {
  final CodeForgeController controller;
  final Map<String, TextStyle> editorTheme;
  final Mode language;
  final String? languageId;
  final LspConfig? lspConfig;
  final List<LspSemanticToken>? semanticTokens;
  final EdgeInsets? innerPadding;
  final ScrollController vscrollController, hscrollController;
  final FocusNode focusNode;
  final bool readOnly, isMobile, lineWrap;
  final AnimationController caretBlinkController;
  final TextStyle? textStyle;
  final bool enableFolding, enableGuideLines, enableGutter, enableGutterDivider;
  final GutterStyle gutterStyle;
  final CodeSelectionStyle selectionStyle;
  final List<LspErrors> diagnostics;
  final ValueNotifier<bool> selectionActiveNotifier, isHoveringPopup;
  final ValueNotifier<Offset> contextMenuOffsetNotifier, offsetNotifier;
  final ValueNotifier<List<dynamic>?> hoverNotifier, suggestionNotifier;
  final ValueNotifier<String?> aiNotifier;
  final ValueNotifier<Offset?> aiOffsetNotifier;
  final BuildContext context;

  const _CodeField({
    required this.controller,
    required this.editorTheme,
    required this.language,
    required this.vscrollController,
    required this.hscrollController,
    required this.focusNode,
    required this.readOnly,
    required this.caretBlinkController,
    required this.enableFolding,
    required this.enableGuideLines,
    required this.enableGutter,
    required this.enableGutterDivider,
    required this.gutterStyle,
    required this.selectionStyle,
    required this.diagnostics,
    required this.isMobile,
    required this.selectionActiveNotifier,
    required this.contextMenuOffsetNotifier,
    required this.offsetNotifier,
    required this.hoverNotifier,
    required this.suggestionNotifier,
    required this.aiNotifier,
    required this.aiOffsetNotifier,
    required this.isHoveringPopup,
    required this.context,
    required this.lineWrap,
    this.textStyle,
    this.languageId,
    this.lspConfig,
    this.semanticTokens,
    this.innerPadding,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _CodeFieldRenderer(
      context: context,
      controller: controller,
      editorTheme: editorTheme,
      language: language,
      languageId: languageId,
      lspConfig: lspConfig,
      innerPadding: innerPadding,
      vscrollController: vscrollController,
      hscrollController: hscrollController,
      focusNode: focusNode,
      readOnly: readOnly,
      caretBlinkController: caretBlinkController,
      textStyle: textStyle,
      enableFolding: enableFolding,
      enableGuideLines: enableGuideLines,
      enableGutter: enableGutter,
      enableGutterDivider: enableGutterDivider,
      gutterStyle: gutterStyle,
      selectionStyle: selectionStyle,
      diagnostics: diagnostics,
      isMobile: isMobile,
      selectionActiveNotifier: selectionActiveNotifier,
      contextMenuOffsetNotifier: contextMenuOffsetNotifier,
      hoverNotifier: hoverNotifier,
      lineWrap: lineWrap,
      offsetNotifier: offsetNotifier,
      aiNotifier: aiNotifier,
      aiOffsetNotifier: aiOffsetNotifier,
      isHoveringPopup: isHoveringPopup,
      suggestionNotifier: suggestionNotifier
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _CodeFieldRenderer renderObject,
  ) {
    if (semanticTokens != null) {
      renderObject.updateSemanticTokens(semanticTokens!);
    }
    renderObject
      ..updateDiagnostics(diagnostics)
      ..editorTheme = editorTheme
      ..language = language
      ..textStyle = textStyle
      ..innerPadding = innerPadding
      ..readOnly = readOnly
      ..lineWrap = lineWrap
      ..enableFolding = enableFolding
      ..enableGuideLines = enableGuideLines
      ..enableGutter = enableGutter
      ..enableGutterDivider = enableGutterDivider
      ..gutterStyle = gutterStyle
      ..selectionStyle = selectionStyle;
  }
}

class _CodeFieldRenderer extends RenderBox implements MouseTrackerAnnotation {
  final CodeForgeController controller;
  Map<String, TextStyle> _editorTheme;
  Mode _language;
  final String? languageId;
  EdgeInsets? _innerPadding;
  final ScrollController vscrollController, hscrollController;
  final FocusNode focusNode;
  bool _readOnly;
  final AnimationController caretBlinkController;
  TextStyle? _textStyle;
  bool _enableFolding, _enableGuideLines, _enableGutter;
  bool _enableGutterDivider;
  GutterStyle _gutterStyle;
  CodeSelectionStyle _selectionStyle;
  final bool isMobile;
  bool _lineWrap;
  final ValueNotifier<bool> selectionActiveNotifier, isHoveringPopup;
  final ValueNotifier<Offset> contextMenuOffsetNotifier, offsetNotifier;
  final ValueNotifier<List<dynamic>?> hoverNotifier, suggestionNotifier;
  final ValueNotifier<Offset?> aiOffsetNotifier;
  final ValueNotifier<String?> aiNotifier;
  final BuildContext context;
  final Map<int, double> _lineWidthCache = {};
  final Map<int, String> _lineTextCache = {};
  final Map<int, ui.Paragraph> _paragraphCache = {};
  final Map<int, double> _lineHeightCache = {};
  final List<FoldRange> _foldRanges = [];
  final _dtap = DoubleTapGestureRecognizer();
  final _onetap = TapGestureRecognizer();
  late double _lineHeight;
  late final double _gutterPadding;
  late final Paint _caretPainter;
  late final Paint _bracketHighlightPainter;
  late final ui.ParagraphStyle _paragraphStyle;
  late final ui.TextStyle _uiTextStyle;
  late final SyntaxHighlighter _syntaxHighlighter;
  final LspConfig? lspConfig;
  late double _gutterWidth;
  List<LspErrors> _diagnostics;
  int _cachedLineCount = 0;
  int _cachedCaretOffset = -1, _cachedCaretLine = 0, _cachedCaretLineStart = 0;
  int? _dragStartOffset;
  Timer? _selectionTimer, _hoverTimer;
  Offset? _pointerDownPosition;
  Offset _currentPosition = Offset.zero;
  bool _foldRangesNeedsClear = false;
  bool _selectionActive = false, _isDragging = false;
  bool _draggingStartHandle = false, _draggingEndHandle = false;
  bool _showBubble = false, _draggingCHandle = false;
  Rect? _startHandleRect, _endHandleRect, _normalHandle;
  double _longLineWidth = 0.0, _wrapWidth = double.infinity;
  int _extraSpaceToAdd = 0;
  String? _aiResponse, _lastProcessedText;
  TextSelection? _lastSelectionForAi;
  bool _insertingPlaceholder = false;
  int? _placeholderInsertOffset;
  int _placeholderLineCount = 0;
  ui.Paragraph? _cachedMagnifiedParagraph;
  int? _cachedMagnifiedLine;
  int? _cachedMagnifiedOffset;

  void updateSemanticTokens(List<LspSemanticToken> tokens) {
    _syntaxHighlighter.updateSemanticTokens(tokens, controller.text);
    _paragraphCache.clear();
    markNeedsPaint();
  }

  void updateDiagnostics(List<LspErrors> diagnostics) {
    if (_diagnostics != diagnostics) {
      _diagnostics = diagnostics;
      markNeedsPaint();
    }
  }

  ui.Paragraph _buildParagraph(String text, {double? width}) {
    final builder = ui.ParagraphBuilder(_paragraphStyle)
      ..pushStyle(_uiTextStyle)
      ..addText(text.isEmpty ? ' ' : text);
    final p = builder.build();
    p.layout(ui.ParagraphConstraints(width: width ?? double.infinity));
    return p;
  }

  ui.Paragraph _buildHighlightedParagraph(
    int lineIndex,
    String text, {
    double? width,
  }) {
    final fontSize = textStyle?.fontSize ?? 14.0;
    final fontFamily = textStyle?.fontFamily;
    return _syntaxHighlighter.buildHighlightedParagraph(
      lineIndex,
      text,
      _paragraphStyle,
      fontSize,
      fontFamily,
      width: width,
    );
  }

  _CodeFieldRenderer({
    required this.controller,
    required Map<String, TextStyle> editorTheme,
    required Mode language,
    required this.vscrollController,
    required this.hscrollController,
    required this.focusNode,
    required bool readOnly,
    required this.caretBlinkController,
    required bool enableFolding,
    required bool enableGuideLines,
    required bool enableGutter,
    required bool enableGutterDivider,
    required GutterStyle gutterStyle,
    required CodeSelectionStyle selectionStyle,
    required List<LspErrors> diagnostics,
    required this.isMobile,
    required this.selectionActiveNotifier,
    required this.contextMenuOffsetNotifier,
    required this.offsetNotifier,
    required this.hoverNotifier,
    required this.suggestionNotifier,
    required this.aiNotifier,
    required this.aiOffsetNotifier,
    required this.isHoveringPopup,
    required this.context,
    required bool lineWrap,
    this.languageId,
    this.lspConfig,
    EdgeInsets? innerPadding,
    TextStyle? textStyle,
  }) : _editorTheme = editorTheme,
       _language = language,
       _readOnly = readOnly,
       _enableFolding = enableFolding,
       _enableGuideLines = enableGuideLines,
       _enableGutter = enableGutter,
       _enableGutterDivider = enableGutterDivider,
       _gutterStyle = gutterStyle,
       _selectionStyle = selectionStyle,
       _lineWrap = lineWrap,
       _innerPadding = innerPadding,
       _textStyle = textStyle,
       _diagnostics = diagnostics
  {
    final fontSize = _textStyle?.fontSize ?? 14.0;
    final fontFamily = _textStyle?.fontFamily;
    final color =
        _textStyle?.color ?? _editorTheme['root']?.color ?? Colors.black;
    final lineHeightMultiplier = _textStyle?.height ?? 1.2;

    _lineHeight = fontSize * lineHeightMultiplier;

    _syntaxHighlighter = SyntaxHighlighter(
      language: _language,
      editorTheme: _editorTheme,
      baseTextStyle: _textStyle,
      languageId: languageId,
      onHighlightComplete: markNeedsPaint,
    );

    _gutterPadding = fontSize;
    if (_enableGutter) {
      if (_gutterStyle.gutterWidth != null) {
        _gutterWidth = gutterStyle.gutterWidth!;
      } else {
        final digits = controller.lineCount.toString().length;
        final digitWidth = digits * _gutterPadding * 0.6;
        final foldIconSpace = enableFolding ? fontSize + 4 : 0;
        _gutterWidth = digitWidth + foldIconSpace + _gutterPadding;
      }
    } else {
      _gutterWidth = 0;
    }
    _cachedLineCount = controller.lineCount;

    _caretPainter = Paint()
      ..color = _selectionStyle.cursorColor ?? color
      ..style = PaintingStyle.fill;

    _bracketHighlightPainter = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    _paragraphStyle = ui.ParagraphStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: lineHeightMultiplier,
    );
    _uiTextStyle = ui.TextStyle(
      color: color,
      fontSize: fontSize,
      fontFamily: fontFamily,
    );

    vscrollController.addListener((){
      if(
        suggestionNotifier.value != null &&
        offsetNotifier.value.dy >= 0
      ){
        offsetNotifier.value = Offset(
          offsetNotifier.value.dx,
          _getCaretInfo().offset.dy - vscrollController.offset
        );
      }
      markNeedsPaint();
    });

    hscrollController.addListener((){
      if(
        suggestionNotifier.value != null &&
        offsetNotifier.value.dx >= 0
      ){
        offsetNotifier.value = Offset(
          _getCaretInfo().offset.dx - hscrollController.offset,
          offsetNotifier.value.dy
        );
      }
      markNeedsPaint();
    });
    caretBlinkController.addListener(markNeedsPaint);
    controller.addListener(_onControllerChange);
    aiNotifier.addListener((){
      final previousAiResponse = _aiResponse;
      _aiResponse = aiNotifier.value;
      aiOffsetNotifier.value = _getCaretInfo().offset;
      
      final isNewSuggestion = _aiResponse != null && 
        (previousAiResponse == null ||
        !previousAiResponse.endsWith(_aiResponse!));
      
      if(isNewSuggestion){
        final aiLines = _aiResponse!.split('\n');
        final aiLineslen = aiLines.length;
        if(aiLineslen > 1){
          
          if (_placeholderInsertOffset != null && _placeholderLineCount > 0) {
            final placehldr = '\n' * _placeholderLineCount;
            _insertingPlaceholder = true;
            controller.replaceRange(
              _placeholderInsertOffset!,
              _placeholderInsertOffset! + placehldr.length,
              ''
            );
            _insertingPlaceholder = false;
          }
          
          final placehldr = '\n' * (aiLineslen - 1);
          _extraSpaceToAdd = aiLineslen;
          final lastSelection = controller.selection;
          
          _insertingPlaceholder = true;
          _placeholderInsertOffset = controller.selection.extentOffset;
          _placeholderLineCount = aiLineslen - 1;
          controller.insertAtCurrentCursor(placehldr);
          controller.selection = lastSelection;
          _insertingPlaceholder = false;
          
        }
      } else if (_aiResponse == null && previousAiResponse != null) {
        
        if (_placeholderInsertOffset != null && _placeholderLineCount > 0) {
          final currentOffset = controller.selection.extentOffset;
          final placehldr = '\n' * _placeholderLineCount;
          
          _insertingPlaceholder = true;
          
          controller.replaceRange(
            _placeholderInsertOffset!,
            _placeholderInsertOffset! + placehldr.length,
            ''
          );
          
          if (currentOffset > _placeholderInsertOffset!) {
            final adjustedOffset = (currentOffset - placehldr.length).clamp(0, controller.length);
            controller.selection = TextSelection.collapsed(offset: adjustedOffset);
          }
          _insertingPlaceholder = false;
          
          _placeholderInsertOffset = null;
          _placeholderLineCount = 0;
        }
        _extraSpaceToAdd = 0;
      }
      
      markNeedsLayout();
      markNeedsPaint();
    });
  }

  
  Map<String, TextStyle> get editorTheme => _editorTheme;
  Mode get language => _language;
  TextStyle? get textStyle => _textStyle;
  EdgeInsets? get innerPadding => _innerPadding;
  bool get readOnly => _readOnly;
  bool get lineWrap => _lineWrap;
  bool get enableFolding => _enableFolding;
  bool get enableGuideLines => _enableGuideLines;
  bool get enableGutter => _enableGutter;
  bool get enableGutterDivider => _enableGutterDivider;
  GutterStyle get gutterStyle => _gutterStyle;
  CodeSelectionStyle get selectionStyle => _selectionStyle;

  
  set editorTheme(Map<String, TextStyle> theme) {
    if (identical(theme, _editorTheme)) return;
    _editorTheme = theme;
    _syntaxHighlighter.dispose();
    _syntaxHighlighter = SyntaxHighlighter(
      language: language,
      editorTheme: theme,
      baseTextStyle: textStyle,
    );
    _paragraphCache.clear();
    markNeedsLayout();
    markNeedsPaint();
  }

  set language(Mode lang) {
    if (identical(lang, _language)) return;
    _language = lang;
    _syntaxHighlighter.dispose();
    _syntaxHighlighter = SyntaxHighlighter(
      language: lang,
      editorTheme: editorTheme,
      baseTextStyle: textStyle,
    );
    _paragraphCache.clear();
    markNeedsLayout();
    markNeedsPaint();
  }

  set textStyle(TextStyle? style) {
    if (identical(style, _textStyle)) return;
    _textStyle = style;
    
    final fontSize = style?.fontSize ?? 14.0;
    final lineHeightMultiplier = style?.height ?? 1.2;
    
    _lineHeight = fontSize * lineHeightMultiplier;
    
    _syntaxHighlighter.dispose();
    _syntaxHighlighter = SyntaxHighlighter(
      language: language,
      editorTheme: editorTheme,
      baseTextStyle: style,
    );
    
    _paragraphCache.clear();
    _lineWidthCache.clear();
    _lineTextCache.clear();
    _lineHeightCache.clear();
    
    markNeedsLayout();
    markNeedsPaint();
  }

  set innerPadding(EdgeInsets? padding) {
    if (identical(padding, _innerPadding)) return;
    _innerPadding = padding;
    markNeedsLayout();
    markNeedsPaint();
  }

  set readOnly(bool value) {
    if (_readOnly == value) return;
    _readOnly = value;
    markNeedsPaint();
  }

  set lineWrap(bool value) {
    if (_lineWrap == value) return;
    _lineWrap = value;
    _paragraphCache.clear();
    _lineHeightCache.clear();
    markNeedsLayout();
    markNeedsPaint();
  }

  set enableFolding(bool value) {
    if (_enableFolding == value) return;
    _enableFolding = value;
    markNeedsLayout();
    markNeedsPaint();
  }

  set enableGuideLines(bool value) {
    if (_enableGuideLines == value) return;
    _enableGuideLines = value;
    markNeedsPaint();
  }

  set enableGutter(bool value) {
    if (_enableGutter == value) return;
    _enableGutter = value;
    markNeedsLayout();
    markNeedsPaint();
  }

  set enableGutterDivider(bool value) {
    if (_enableGutterDivider == value) return;
    _enableGutterDivider = value;
    markNeedsPaint();
  }

  set gutterStyle(GutterStyle style) {
    if (identical(style, _gutterStyle)) return;
    _gutterStyle = style;
    markNeedsPaint();
  }

  set selectionStyle(CodeSelectionStyle style) {
    if (identical(style, _selectionStyle)) return;
    _selectionStyle = style;
    _caretPainter.color = style.cursorColor ?? _editorTheme['root']!.color!;
    markNeedsPaint();
  }

  void _ensureCaretVisible() {
    if (!vscrollController.hasClients || !hscrollController.hasClients) return;

    final caretInfo = _getCaretInfo();
    final caretX =
        caretInfo.offset.dx + _gutterWidth + (innerPadding?.left ?? 0);
    final caretY = caretInfo.offset.dy + (innerPadding?.top ?? 0);
    final caretHeight = caretInfo.height;
    final vScrollOffset = vscrollController.offset;
    final hScrollOffset = hscrollController.offset;
    final viewportHeight = vscrollController.position.viewportDimension;
    final viewportWidth = hscrollController.position.viewportDimension;

    offsetNotifier.value = Offset(
      (caretX - hScrollOffset) % viewportWidth,
      (caretY - vScrollOffset) % viewportHeight
    );

    if (caretY > 0 && caretY <= vScrollOffset + (innerPadding?.top ?? 0)) {
      vscrollController.animateTo(
        caretY - (innerPadding?.top ?? 0),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    } else if (caretY + caretHeight >= vScrollOffset + viewportHeight) {
      vscrollController.animateTo(
        caretY + caretHeight - viewportHeight + (innerPadding?.bottom ?? 0),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }

    if (caretX < hScrollOffset + (innerPadding?.left ?? 0) + _gutterWidth) {
      hscrollController.animateTo(
        caretX - (innerPadding?.left ?? 0) - _gutterWidth,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    } else if (caretX + 1.5 > hScrollOffset + viewportWidth) {
      hscrollController.animateTo(
        caretX +
            1.5 -
            viewportWidth +
            (innerPadding?.right ?? 0) +
            _gutterWidth,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  void _onControllerChange() {
    if (controller.selectionOnly) {
      controller.selectionOnly = false;
      _ensureCaretVisible();
      
      if (isMobile && controller.selection.isCollapsed) {
        _showBubble = true;
      }
      markNeedsPaint();
      return;
    }

    if (controller.bufferNeedsRepaint) {
      controller.bufferNeedsRepaint = false;
      _ensureCaretVisible();
      markNeedsPaint();
      return;
    }

    
    if (_showBubble && isMobile) {
      _showBubble = false;
    }

    final newLineCount = controller.lineCount;
    final lineCountChanged = newLineCount != _cachedLineCount;

    final affectedLine = controller.dirtyLine;
    if (affectedLine != null) {
      _lineWidthCache.remove(affectedLine);
      _lineTextCache.remove(affectedLine);
      _paragraphCache.remove(affectedLine);
      _lineHeightCache.remove(affectedLine);
      _syntaxHighlighter.invalidateLines({affectedLine});
    }
    controller.clearDirtyRegion();

    if (lineCountChanged) {
      _cachedLineCount = newLineCount;
      _lineTextCache.clear();
      _lineWidthCache.clear();
      _paragraphCache.clear();
      _lineHeightCache.clear();
      _syntaxHighlighter.invalidateAll();

      if (enableGutter && gutterStyle.gutterWidth == null) {
        final fontSize = textStyle?.fontSize ?? 14.0;
        final digits = newLineCount.toString().length;
        final digitWidth = digits * _gutterPadding * 0.6;
        final foldIconSpace = enableFolding ? fontSize + 4 : 0;
        _gutterWidth = digitWidth + foldIconSpace + _gutterPadding;
      }

      if (enableFolding) {
        _foldRangesNeedsClear = true;
      }

      markNeedsLayout();
    } else if (affectedLine != null) {
      final newLineWidth = _getLineWidth(affectedLine);
      final currentContentWidth =
          size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
      if (newLineWidth > currentContentWidth || newLineWidth > _longLineWidth) {
        _longLineWidth = newLineWidth;
        markNeedsLayout();
      } else {
        markNeedsPaint();
      }
    } else {
      markNeedsPaint();
    }

    final newText = controller.text;
    final oldText = _lastProcessedText ?? '';
    final cursorPosition = controller.selection.extentOffset.clamp(0, controller.length);
    final textBeforeCursor = newText.substring(0, cursorPosition);

    if (_lastProcessedText == newText &&
      _aiResponse != null &&
      _aiResponse!.isNotEmpty &&
      _lastSelectionForAi != controller.selection &&
      !_insertingPlaceholder
    ){
      aiNotifier.value = null;
      aiOffsetNotifier.value = null;
    }
    _lastSelectionForAi = controller.selection;
      
    if (_aiResponse != null && _aiResponse!.isNotEmpty && !_insertingPlaceholder) {
      final textLengthDiff = newText.length - oldText.length;
      
      if (textLengthDiff > 0 && cursorPosition >= textLengthDiff) {
        final newlyTypedChars = textBeforeCursor.substring(
          cursorPosition - textLengthDiff,
          cursorPosition
        );
        
        if (_aiResponse!.startsWith(newlyTypedChars)) {
          
          if (_placeholderInsertOffset != null) {
            _placeholderInsertOffset = _placeholderInsertOffset! + newlyTypedChars.length;
          }
          
          _aiResponse = _aiResponse!.substring(newlyTypedChars.length);
          if (_aiResponse!.isEmpty) {
            aiNotifier.value = null;
            aiOffsetNotifier.value = null;
          } else {
            aiNotifier.value = _aiResponse;
          }
        } else {
          _aiResponse = null;
          aiNotifier.value = null;
          aiOffsetNotifier.value = null;
        }
      } else if (textLengthDiff < 0) {
        _aiResponse = null;
        aiNotifier.value = null;
        aiOffsetNotifier.value = null;
      }
    }
    _ensureCaretVisible();
    if (_lastProcessedText == newText) return;
    _lastProcessedText = newText;
  }

  FoldRange? _computeFoldRangeForLine(int lineIndex) {
    if (!enableFolding) return null;

    final line = controller.getLineText(lineIndex);

    if (line.contains('{')) {
      int braceCount = 0;
      bool foundOpen = false;

      for (int i = lineIndex; i < controller.lineCount; i++) {
        final checkLine = controller.getLineText(i);
        for (int c = 0; c < checkLine.length; c++) {
          if (checkLine[c] == '{') {
            if (!foundOpen && i == lineIndex) foundOpen = true;
            braceCount++;
          } else if (checkLine[c] == '}') {
            braceCount--;
            if (braceCount == 0 && foundOpen && i > lineIndex) {
              return FoldRange(lineIndex, i);
            }
          }
        }
      }
    }

    if (line.trim().endsWith(':')) {
      final startIndent = line.length - line.trimLeft().length;
      int endLine = lineIndex;

      for (int j = lineIndex + 1; j < controller.lineCount; j++) {
        final next = controller.getLineText(j);
        if (next.trim().isEmpty) continue;
        final nextIndent = next.length - next.trimLeft().length;
        if (nextIndent <= startIndent) break;
        endLine = j;
      }

      if (endLine > lineIndex) {
        return FoldRange(lineIndex, endLine);
      }
    }

    return null;
  }

  FoldRange? _getOrComputeFoldRange(int lineIndex) {
    if (_foldRangesNeedsClear) {
      _foldRanges.removeWhere((f) => !f.isFolded);
      _foldRangesNeedsClear = false;
    }

    try {
      return _foldRanges.firstWhere((f) => f.startIndex == lineIndex);
    } catch (_) {
      final fold = _computeFoldRangeForLine(lineIndex);
      if (fold != null) {
        _foldRanges.add(fold);
        _foldRanges.sort((a, b) => a.startIndex.compareTo(b.startIndex));
      }
      return fold;
    }
  }

  void _toggleFold(FoldRange fold) {
    if (fold.isFolded) {
      _unfoldWithChildren(fold);
    } else {
      _foldWithChildren(fold);
    }
    markNeedsLayout();
    markNeedsPaint();
  }

  void _foldWithChildren(FoldRange parentFold) {
    parentFold.clearOriginallyFoldedChildren();

    for (final childFold in _foldRanges) {
      if (childFold.isFolded &&
          childFold != parentFold &&
          childFold.startIndex > parentFold.startIndex &&
          childFold.endIndex <= parentFold.endIndex) {
        parentFold.addOriginallyFoldedChild(childFold);
        childFold.isFolded = false;
      }
    }

    parentFold.isFolded = true;
  }

  void _unfoldWithChildren(FoldRange parentFold) {
    parentFold.isFolded = false;
    for (final childFold in parentFold.originallyFoldedChildren) {
      if (childFold.startIndex > parentFold.startIndex &&
          childFold.endIndex <= parentFold.endIndex) {
        childFold.isFolded = true;
      }
    }
    parentFold.clearOriginallyFoldedChildren();
  }

  bool _isLineFolded(int lineIndex) {
    return _foldRanges.any(
      (fold) =>
          fold.isFolded &&
          lineIndex > fold.startIndex &&
          lineIndex <= fold.endIndex,
    );
  }

  int? _findMatchingBracket(String text, int pos) {
    const Map<String, String> pairs = {
      '(': ')',
      '{': '}',
      '[': ']',
      ')': '(',
      '}': '{',
      ']': '[',
    };
    const String openers = '({[';

    if (pos < 0 || pos >= text.length) return null;

    final char = text[pos];
    if (!pairs.containsKey(char)) return null;

    final match = pairs[char]!;
    final isForward = openers.contains(char);

    int depth = 0;
    if (isForward) {
      for (int i = pos + 1; i < text.length; i++) {
        if (text[i] == char) depth++;
        if (text[i] == match) {
          if (depth == 0) return i;
          depth--;
        }
      }
    } else {
      for (int i = pos - 1; i >= 0; i--) {
        if (text[i] == char) depth++;
        if (text[i] == match) {
          if (depth == 0) return i;
          depth--;
        }
      }
    }
    return null;
  }

  (int?, int?) _getBracketPairAtCursor() {
    final cursorOffset = controller.selection.extentOffset;
    final text = controller.text;
    final textLength = text.length;

    if (cursorOffset < 0 || text.isEmpty) return (null, null);

    if (cursorOffset > 0 && cursorOffset <= textLength) {
      final before = text[cursorOffset - 1];
      if ('{}[]()'.contains(before)) {
        final match = _findMatchingBracket(text, cursorOffset - 1);
        if (match != null) {
          return (cursorOffset - 1, match);
        }
      }
    }

    if (cursorOffset >= 0 && cursorOffset < textLength) {
      final after = text[cursorOffset];
      if ('{}[]()'.contains(after)) {
        final match = _findMatchingBracket(text, cursorOffset);
        if (match != null) {
          return (cursorOffset, match);
        }
      }
    }

    return (null, null);
  }

  FoldRange? _getFoldRangeAtLine(int lineIndex) {
    if (!enableFolding) return null;
    return _getOrComputeFoldRange(lineIndex);
  }

  int _findVisibleLineByYPosition(double y) {
    final lineCount = controller.lineCount;
    if (lineCount == 0) return 0;

    final hasActiveFolds = _foldRanges.any((f) => f.isFolded);

    if (!lineWrap && !hasActiveFolds) {
      return (y / _lineHeight).floor().clamp(0, lineCount - 1);
    }

    double currentY = 0;
    for (int i = 0; i < lineCount; i++) {
      if (hasActiveFolds && _isLineFolded(i)) continue;
      final lineHeight = lineWrap ? _getWrappedLineHeight(i) : _lineHeight;
      if (currentY + lineHeight > y) {
        return i;
      }
      currentY += lineHeight;
    }
    return lineCount - 1;
  }

  ({int lineIndex, int columnIndex, Offset offset, double height})
  _getCaretInfo() {
    final lineCount = controller.lineCount;
    if (lineCount == 0) {
      return (
        lineIndex: 0,
        columnIndex: 0,
        offset: Offset.zero,
        height: _lineHeight,
      );
    }

    final hasActiveFolds = _foldRanges.any((f) => f.isFolded);

    if (controller.isBufferActive) {
      final lineIndex = controller.bufferLineIndex!;
      final columnIndex = controller.bufferCursorColumn;
      final lineY = _getLineYOffset(lineIndex, hasActiveFolds);
      final lineText = controller.bufferLineText ?? '';
      final para = _buildHighlightedParagraph(
        lineIndex,
        lineText,
        width: lineWrap ? _wrapWidth : null,
      );
      final clampedCol = columnIndex.clamp(0, lineText.length);

      double caretX = 0.0;
      double caretYInLine = 0.0;
      if (clampedCol > 0) {
        final boxes = para.getBoxesForRange(0, clampedCol);
        if (boxes.isNotEmpty) {
          caretX = boxes.last.right;
          caretYInLine = boxes.last.top;
        }
      }

      return (
        lineIndex: lineIndex,
        columnIndex: columnIndex,
        offset: Offset(caretX, lineY + caretYInLine),
        height: _lineHeight,
      );
    }

    final cursorOffset = controller.selection.extentOffset;

    int lineIndex;
    int lineStartOffset;
    if (cursorOffset == _cachedCaretOffset) {
      lineIndex = _cachedCaretLine;
      lineStartOffset = _cachedCaretLineStart;
    } else {
      lineIndex = controller.getLineAtOffset(cursorOffset);
      lineStartOffset = controller.getLineStartOffset(lineIndex);
      _cachedCaretOffset = cursorOffset;
      _cachedCaretLine = lineIndex;
      _cachedCaretLineStart = lineStartOffset;
    }

    final columnIndex = cursorOffset - lineStartOffset;
    final lineY = _getLineYOffset(lineIndex, hasActiveFolds);

    String lineText;
    if (_lineTextCache.containsKey(lineIndex)) {
      lineText = _lineTextCache[lineIndex]!;
    } else {
      lineText = controller.getLineText(lineIndex);
      _lineTextCache[lineIndex] = lineText;
      _paragraphCache.remove(lineIndex);
    }

    ui.Paragraph para;
    if (_paragraphCache.containsKey(lineIndex)) {
      para = _paragraphCache[lineIndex]!;
    } else {
      para = _buildHighlightedParagraph(
        lineIndex,
        lineText,
        width: lineWrap ? _wrapWidth : null,
      );
      _paragraphCache[lineIndex] = para;
    }

    final clampedCol = columnIndex.clamp(0, lineText.length);
    double caretX = 0.0;
    double caretYInLine = 0.0;
    if (clampedCol > 0) {
      final boxes = para.getBoxesForRange(0, clampedCol);
      if (boxes.isNotEmpty) {
        caretX = boxes.last.right;
        caretYInLine = boxes.last.top;
      }
    }

    return (
      lineIndex: lineIndex,
      columnIndex: columnIndex,
      offset: Offset(caretX, lineY + caretYInLine),
      height: _lineHeight,
    );
  }

  int _getTextOffsetFromPosition(Offset position) {
    final lineCount = controller.lineCount;
    if (lineCount == 0) return 0;

    final tappedLineIndex = _findVisibleLineByYPosition(position.dy);

    String lineText;
    if (_lineTextCache.containsKey(tappedLineIndex)) {
      lineText = _lineTextCache[tappedLineIndex]!;
    } else {
      lineText = controller.getLineText(tappedLineIndex);
      _lineTextCache[tappedLineIndex] = lineText;
      _paragraphCache.remove(tappedLineIndex);
    }

    ui.Paragraph para;
    if (_paragraphCache.containsKey(tappedLineIndex)) {
      para = _paragraphCache[tappedLineIndex]!;
    } else {
      para = _buildHighlightedParagraph(
        tappedLineIndex,
        lineText,
        width: lineWrap ? _wrapWidth : null,
      );
      _paragraphCache[tappedLineIndex] = para;
    }

    final localX = position.dx;

    final hasActiveFolds = _foldRanges.any((f) => f.isFolded);
    final lineStartY = _getLineYOffset(tappedLineIndex, hasActiveFolds);
    final localY = position.dy - lineStartY;

    final textPosition = para.getPositionForOffset(
      Offset(localX, localY.clamp(0, para.height)),
    );
    final columnIndex = textPosition.offset.clamp(0, lineText.length);

    final lineStartOffset = controller.getLineStartOffset(tappedLineIndex);
    final absoluteOffset = lineStartOffset + columnIndex;

    return absoluteOffset.clamp(0, controller.length);
  }

  double _getLineWidth(int lineIndex) {
    final lineText = controller.getLineText(lineIndex);
    final cachedText = _lineTextCache[lineIndex];

    if (cachedText == lineText && _lineWidthCache.containsKey(lineIndex)) {
      return _lineWidthCache[lineIndex]!;
    }

    final para = _buildParagraph(lineText);
    final width = para.maxIntrinsicWidth;
    _lineTextCache[lineIndex] = lineText;
    _lineWidthCache[lineIndex] = width;
    return width;
  }

  @override
  void performLayout() {
    final lineCount = controller.lineCount;

    if (lineCount != _cachedLineCount) {
      _lineWidthCache.removeWhere((key, _) => key >= lineCount);
      _lineTextCache.removeWhere((key, _) => key >= lineCount);
      _lineHeightCache.removeWhere((key, _) => key >= lineCount);
    }

    final hasActiveFolds = _foldRanges.any((f) => f.isFolded);
    double visibleHeight = 0;
    double maxLineWidth = 0;

    if (lineWrap) {
      final viewportWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.of(context).size.width;
      final newWrapWidth =
          viewportWidth - _gutterWidth - (innerPadding?.horizontal ?? 0);
      final clampedWrapWidth = newWrapWidth < 100 ? 100.0 : newWrapWidth;

      if ((_wrapWidth - clampedWrapWidth).abs() > 1) {
        _wrapWidth = clampedWrapWidth;
        _paragraphCache.clear();
        _lineHeightCache.clear();
      }
    } else {
      _wrapWidth = double.infinity;
    }

    for (int i = 0; i < lineCount; i++) {
      if (hasActiveFolds && _isLineFolded(i)) continue;

      if (lineWrap) {
        final lineHeight = _getWrappedLineHeight(i);
        visibleHeight += lineHeight;
      } else {
        visibleHeight += _lineHeight;
        final width = _getLineWidth(i);
        if (width > maxLineWidth) {
          maxLineWidth = width;
        }
      }
    }

    _longLineWidth = maxLineWidth;

    final contentHeight = visibleHeight + (innerPadding?.vertical ?? 0) + _extraSpaceToAdd;
    final contentWidth = lineWrap
      ? constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : MediaQuery.of(context).size.width
      : maxLineWidth + (innerPadding?.horizontal ?? 0) + _gutterWidth;

    size = constraints.constrain(Size(contentWidth, contentHeight));
  }

  double _getWrappedLineHeight(int lineIndex) {
    if (_lineHeightCache.containsKey(lineIndex)) {
      return _lineHeightCache[lineIndex]!;
    }

    final lineText = controller.getLineText(lineIndex);
    final para = _buildHighlightedParagraph(
      lineIndex,
      lineText,
      width: _wrapWidth,
    );
    final height = para.height;

    _lineHeightCache[lineIndex] = height;
    _paragraphCache[lineIndex] = para;
    _lineTextCache[lineIndex] = lineText;

    return height;
  }

  double _getLineYOffset(int targetLine, bool hasActiveFolds) {
    if (!lineWrap && !hasActiveFolds) {
      return targetLine * _lineHeight;
    }

    double y = 0;
    for (int i = 0; i < targetLine; i++) {
      if (hasActiveFolds && _isLineFolded(i)) continue;
      y += lineWrap ? _getWrappedLineHeight(i) : _lineHeight;
    }
    return y;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final viewTop = vscrollController.offset;
    final viewBottom = viewTop + vscrollController.position.viewportDimension;
    final lineCount = controller.lineCount;
    final bufferActive = controller.isBufferActive;
    final bufferLineIndex = controller.bufferLineIndex;
    final bufferLineText = controller.bufferLineText;
    final bgColor = editorTheme['root']?.backgroundColor ?? Colors.white;
    final textColor = textStyle?.color ?? editorTheme['root']!.color!;

    canvas.save();

    canvas.drawPaint(
      Paint()
        ..color = bgColor
        ..style = PaintingStyle.fill,
    );

    final hasActiveFolds = _foldRanges.any((f) => f.isFolded);

    int firstVisibleLine;
    int lastVisibleLine;
    double firstVisibleLineY;

    if (!lineWrap && !hasActiveFolds) {
      firstVisibleLine = (viewTop / _lineHeight).floor().clamp(
        0,
        lineCount - 1,
      );
      lastVisibleLine = (viewBottom / _lineHeight).ceil().clamp(
        0,
        lineCount - 1,
      );
      firstVisibleLineY = firstVisibleLine * _lineHeight;
    } else {
      double currentY = 0;
      firstVisibleLine = 0;
      lastVisibleLine = lineCount - 1;
      firstVisibleLineY = 0;

      for (int i = 0; i < lineCount; i++) {
        if (hasActiveFolds && _isLineFolded(i)) continue;
        final lineHeight = lineWrap ? _getWrappedLineHeight(i) : _lineHeight;
        if (currentY + lineHeight > viewTop) {
          firstVisibleLine = i;
          firstVisibleLineY = currentY;
          break;
        }
        currentY += lineHeight;
      }

      currentY = firstVisibleLineY;
      for (int i = firstVisibleLine; i < lineCount; i++) {
        if (hasActiveFolds && _isLineFolded(i)) continue;
        final lineHeight = lineWrap ? _getWrappedLineHeight(i) : _lineHeight;
        currentY += lineHeight;
        if (currentY >= viewBottom) {
          lastVisibleLine = i;
          break;
        }
      }
    }

    _drawSelection(
      canvas,
      offset,
      firstVisibleLine,
      lastVisibleLine,
      firstVisibleLineY,
      hasActiveFolds,
    );

    if (enableGuideLines && (lastVisibleLine - firstVisibleLine) < 200) {
      _drawIndentGuides(
        canvas,
        offset,
        firstVisibleLine,
        lastVisibleLine,
        firstVisibleLineY,
        hasActiveFolds,
        textColor,
      );
    }

    double currentY = firstVisibleLineY;
    for (int i = firstVisibleLine; i <= lastVisibleLine && i < lineCount; i++) {
      if (hasActiveFolds && _isLineFolded(i)) continue;

      final contentTop = currentY;
      final lineHeight = lineWrap ? _getWrappedLineHeight(i) : _lineHeight;

      ui.Paragraph paragraph;
      String lineText;

      if (bufferActive && i == bufferLineIndex && bufferLineText != null) {
        lineText = bufferLineText;
        paragraph = _buildHighlightedParagraph(
          i,
          bufferLineText,
          width: lineWrap ? _wrapWidth : null,
        );
      } else {
        if (_lineTextCache.containsKey(i)) {
          lineText = _lineTextCache[i]!;
        } else {
          lineText = controller.getLineText(i);
          _lineTextCache[i] = lineText;
        }

        if (_paragraphCache.containsKey(i)) {
          paragraph = _paragraphCache[i]!;
        } else {
          paragraph = _buildHighlightedParagraph(
            i,
            lineText,
            width: lineWrap ? _wrapWidth : null,
          );
          _paragraphCache[i] = paragraph;
        }
      }

      final foldRange = _getFoldRangeAtLine(i);
      final isFoldStart = foldRange != null;

      canvas.drawParagraph(
        paragraph,
        offset +
            Offset(
              _gutterWidth +
                  (innerPadding?.left ?? 0) -
                  (lineWrap ? 0 : hscrollController.offset),
              (innerPadding?.top ?? 0) + contentTop - vscrollController.offset,
            ),
      );

      if (isFoldStart && foldRange.isFolded) {
        final foldIndicator = _buildParagraph(' ...');
        final paraWidth = paragraph.longestLine;
        canvas.drawParagraph(
          foldIndicator,
          offset +
              Offset(
                _gutterWidth +
                    (innerPadding?.left ?? 0) +
                    paraWidth -
                    (lineWrap ? 0 : hscrollController.offset),
                (innerPadding?.top ?? 0) +
                    contentTop -
                    vscrollController.offset,
              ),
        );
      }

      currentY += lineHeight;
    }

    _drawDiagnostics(
      canvas,
      offset,
      firstVisibleLine,
      lastVisibleLine,
      firstVisibleLineY,
      hasActiveFolds,
    );

    if (_aiResponse != null && _aiResponse!.isNotEmpty) {
      _drawAiGhostText(
        canvas,
        offset,
        firstVisibleLine,
        lastVisibleLine,
        firstVisibleLineY,
        hasActiveFolds,
      );
    }

    if (enableGutter) {
      _drawGutter(
        canvas,
        offset,
        viewTop,
        viewBottom,
        lineCount,
        bgColor,
        textStyle,
      );
    }

    if (focusNode.hasFocus) {
      _drawBracketHighlight(
        canvas,
        offset,
        viewTop,
        viewBottom,
        firstVisibleLine,
        lastVisibleLine,
        firstVisibleLineY,
        hasActiveFolds,
        textColor,
      );
    }

    if (focusNode.hasFocus && caretBlinkController.value > 0.5) {
      final caretInfo = _getCaretInfo();

      final caretX =
          _gutterWidth +
          (innerPadding?.left ?? 0) +
          caretInfo.offset.dx -
          (lineWrap ? 0 : hscrollController.offset);
      final caretScreenY =
          (innerPadding?.top ?? 0) +
          caretInfo.offset.dy -
          vscrollController.offset;

      canvas.drawRect(
        Rect.fromLTWH(caretX, caretScreenY, 1.5, caretInfo.height),
        _caretPainter,
      );
    }

    if(isMobile){
      final selection = controller.selection;
      final handleColor = selectionStyle.cursorBubbleColor;
      final handleRadius = (_lineHeight / 2).clamp(6.0, 12.0);

      final handlePaint = Paint()
        ..color = handleColor
        ..style = PaintingStyle.fill;

      if (selection.isCollapsed) {
        if (_showBubble || _selectionActive) {
          final caretInfo = _getCaretInfo();
          final handleSize = caretInfo.height;

          final handleX =
              offset.dx +
              _gutterWidth +
              (innerPadding?.left ?? 0) +
              caretInfo.offset.dx -
              (lineWrap ? 0 : hscrollController.offset);
          final handleY =
              offset.dy +
              (innerPadding?.top ?? 0) +
              caretInfo.offset.dy +
              _lineHeight -
              vscrollController.offset;

          canvas.save();
          canvas.translate(handleX, handleY);
          canvas.rotate(pi / 4);
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromCenter(
                center: Offset((handleSize / 1.5), (handleSize / 1.5)),
                width: handleSize * 1.3,
                height: handleSize * 1.3
              ),
              topRight: Radius.circular(25),
              bottomLeft: Radius.circular(25),
              bottomRight: Radius.circular(25),
            ),
            handlePaint,
          );
          canvas.restore();

          _normalHandle = Rect.fromCenter(
            center: Offset(handleX, handleY + handleRadius),
            width: handleRadius * 2,
            height: handleRadius * 2,
          );

          
          if (_draggingCHandle) {
            _selectionActive = selectionActiveNotifier.value = true;
            final caretLineIndex = controller.getLineAtOffset(controller.selection.baseOffset);
            final lineText = _lineTextCache[caretLineIndex] ?? controller.getLineText(caretLineIndex);
            final lineStartOffset = controller.getLineStartOffset(caretLineIndex);
            final caretInLine = controller.selection.baseOffset - lineStartOffset;
            
            final previewStart = caretInLine.clamp(0, lineText.length);
            final previewEnd = (caretInLine + 10).clamp(0, lineText.length);
            final previewText = lineText.substring(
              max(0, previewStart - 10),
              min(lineText.length, previewEnd),
            );

            
            ui.Paragraph zoomParagraph;
            if (_cachedMagnifiedParagraph != null &&
                _cachedMagnifiedLine == caretLineIndex &&
                _cachedMagnifiedOffset == caretInLine) {
              zoomParagraph = _cachedMagnifiedParagraph!;
            } else {
              
              final zoomFontSize = (textStyle?.fontSize ?? 14) * 1.5;
              final fontFamily = textStyle?.fontFamily;
              zoomParagraph = _syntaxHighlighter.buildHighlightedParagraph(
                caretLineIndex,
                previewText,
                _paragraphStyle,
                zoomFontSize,
                fontFamily,
              );
              _cachedMagnifiedParagraph = zoomParagraph;
              _cachedMagnifiedLine = caretLineIndex;
              _cachedMagnifiedOffset = caretInLine;
            }

            final zoomBoxWidth = min(zoomParagraph.longestLine + 16, size.width * 0.6);
            final zoomBoxHeight = zoomParagraph.height + 12;
            final zoomBoxX = (handleX - zoomBoxWidth / 2).clamp(0.0, size.width - zoomBoxWidth);
            final zoomBoxY = handleY - zoomBoxHeight - 18;

            final rrect = RRect.fromRectAndRadius(
              Rect.fromLTWH(zoomBoxX, zoomBoxY, zoomBoxWidth, zoomBoxHeight),
              Radius.circular(12),
            );

            canvas.drawRRect(
              rrect,
              Paint()
                ..color = editorTheme['root']?.backgroundColor ?? Colors.black
                ..style = PaintingStyle.fill
            );

            canvas.drawRRect(
              rrect,
              Paint()
                ..color = editorTheme['root']?.color ?? Colors.grey
                ..strokeWidth = 0.5
                ..style = PaintingStyle.stroke
            );

            canvas.save();
            canvas.clipRect(rrect.outerRect);
            canvas.drawParagraph(
              zoomParagraph,
              Offset(zoomBoxX + 8, zoomBoxY + 6),
            );
            canvas.restore();
          }
        }
      } else {
        if (_startHandleRect != null) {
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              _startHandleRect!,
              topLeft: Radius.circular(25),
              bottomLeft: Radius.circular(25),
              bottomRight: Radius.circular(25)
            ),
            handlePaint,
          );
        }

        if (_endHandleRect != null) {
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              _endHandleRect!,
              topRight: Radius.circular(25),
              bottomLeft: Radius.circular(25),
              bottomRight: Radius.circular(25)
            ),
            handlePaint,
          );
        }
      }
    }

    canvas.restore();
  }

  void _drawGutter(
    Canvas canvas,
    Offset offset,
    double viewTop,
    double viewBottom,
    int lineCount,
    Color bgColor,
    TextStyle? gutterTextStyle,
  ) {
    final viewportHeight = vscrollController.position.viewportDimension;

    final gutterBgColor = gutterStyle.backgroundColor ?? bgColor;
    canvas.drawRect(
      Rect.fromLTWH(offset.dx, offset.dy, _gutterWidth, viewportHeight),
      Paint()..color = gutterBgColor,
    );

    if (enableGutterDivider) {
      final dividerPaint = Paint()
        ..color = (editorTheme['root']?.color ?? Colors.grey).withAlpha(150)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(offset.dx + _gutterWidth - 1, offset.dy),
        Offset(offset.dx + _gutterWidth - 1, offset.dy + viewportHeight),
        dividerPaint,
      );
    }

    final lineNumberStyle =
        gutterStyle.lineNumberStyle ??
        (() {
          if (gutterTextStyle == null) {
            return editorTheme['root'];
          } else if (gutterTextStyle.color == null) {
            return gutterTextStyle.copyWith(color: editorTheme['root']?.color);
          } else {
            return gutterTextStyle;
          }
        })();

    final hasActiveFolds = _foldRanges.any((f) => f.isFolded);

    int firstVisibleLine;
    double firstVisibleLineY;

    if (!lineWrap && !hasActiveFolds) {
      firstVisibleLine = (viewTop / _lineHeight).floor().clamp(
        0,
        lineCount - 1,
      );
      firstVisibleLineY = firstVisibleLine * _lineHeight;
    } else {
      double currentY = 0;
      firstVisibleLine = 0;
      firstVisibleLineY = 0;

      for (int i = 0; i < lineCount; i++) {
        if (hasActiveFolds && _isLineFolded(i)) continue;
        final lineHeight = lineWrap ? _getWrappedLineHeight(i) : _lineHeight;
        if (currentY + lineHeight > viewTop) {
          firstVisibleLine = i;
          firstVisibleLineY = currentY;
          break;
        }
        currentY += lineHeight;
      }
    }

    double currentY = firstVisibleLineY;
    for (int i = firstVisibleLine; i < lineCount; i++) {
      if (hasActiveFolds && _isLineFolded(i)) continue;

      final contentTop = currentY;
      final lineHeight = lineWrap ? _getWrappedLineHeight(i) : _lineHeight;

      if (contentTop > viewBottom) break;

      if (contentTop + lineHeight >= viewTop) {
        final lineNumPara = _buildLineNumberParagraph(
          (i + 1).toString(),
          lineNumberStyle!,
        );
        final numWidth = lineNumPara.longestLine;

        canvas.drawParagraph(
          lineNumPara,
          offset +
            Offset(
              (_gutterWidth - numWidth) / 2 -
                  (enableFolding ? (lineNumberStyle.fontSize ?? 14) / 2 : 0),
              (innerPadding?.top ?? 0) +
                  contentTop -
                  vscrollController.offset,
            ),
        );

        if (enableFolding) {
          final foldRange = _getFoldRangeAtLine(i);
          if (foldRange != null) {
            final isInsideFoldedParent = _foldRanges.any(
              (parent) =>
                  parent.isFolded &&
                  parent.startIndex < i &&
                  parent.endIndex >= i,
            );

            if (!isInsideFoldedParent) {
              final icon = foldRange.isFolded
                  ? gutterStyle.foldedIcon
                  : gutterStyle.unfoldedIcon;
              final iconColor = foldRange.isFolded
                  ? (gutterStyle.foldedIconColor ?? lineNumberStyle.color)
                  : (gutterStyle.unfoldedIconColor ?? lineNumberStyle.color);

              _drawFoldIcon(
                canvas,
                offset,
                icon,
                iconColor!,
                lineNumberStyle.fontSize ?? 14,
                contentTop - vscrollController.offset,
              );
            }
          }
        }
      }

      currentY += lineHeight;
    }
  }

  ui.Paragraph _buildLineNumberParagraph(String text, TextStyle style) {
    final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontSize: style.fontSize,
            fontFamily: style.fontFamily,
          ),
        )
        ..pushStyle(
          ui.TextStyle(
            color: style.color,
            fontSize: style.fontSize,
            fontFamily: style.fontFamily,
          ),
        )
        ..addText(text);
    final p = builder.build();
    p.layout(const ui.ParagraphConstraints(width: double.infinity));
    return p;
  }

  void _drawFoldIcon(
    Canvas canvas,
    Offset offset,
    IconData icon,
    Color color,
    double fontSize,
    double y,
  ) {
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(
      canvas,
      offset +
      Offset(
        _gutterWidth - iconPainter.width - 2,
        (innerPadding?.top ?? 0)
        + y
        + (_lineHeight - iconPainter.height) / 2,
      ),
    );
  }

  void _drawIndentGuides(
    Canvas canvas,
    Offset offset,
    int firstVisibleLine,
    int lastVisibleLine,
    double firstVisibleLineY,
    bool hasActiveFolds,
    Color textColor,
  ) {
    final viewTop = vscrollController.offset;
    final viewBottom = viewTop + vscrollController.position.viewportDimension;
    final tabSize = 4;
    final cursorOffset = controller.selection.extentOffset;
    final currentLine = controller.getLineAtOffset(cursorOffset);
    List<({int startLine, int endLine, int indentLevel, double guideX})>
    blocks = [];

    void processLine(int i) {
      if (hasActiveFolds && _isLineFolded(i)) return;

      String lineText;
      if (_lineTextCache.containsKey(i)) {
        lineText = _lineTextCache[i]!;
      } else {
        lineText = controller.getLineText(i);
        _lineTextCache[i] = lineText;
      }

      final trimmed = lineText.trimRight();
      if (!trimmed.endsWith('{') && !trimmed.endsWith(':')) return;

      final leadingSpaces = lineText.length - lineText.trimLeft().length;
      final indentLevel = leadingSpaces ~/ tabSize;

      int endLine = i + 1;
      while (endLine < controller.lineCount) {
        if (hasActiveFolds && _isLineFolded(endLine)) {
          endLine++;
          continue;
        }

        String nextLine;
        if (_lineTextCache.containsKey(endLine)) {
          nextLine = _lineTextCache[endLine]!;
        } else {
          nextLine = controller.getLineText(endLine);
          _lineTextCache[endLine] = nextLine;
        }

        if (nextLine.trim().isEmpty) {
          endLine++;
          continue;
        }

        final nextLeading = nextLine.length - nextLine.trimLeft().length;
        if (nextLeading <= leadingSpaces) break;
        endLine++;
      }

      if (endLine <= i + 1) return;

      if (endLine < firstVisibleLine) return;

      ui.Paragraph para;
      if (_paragraphCache.containsKey(i)) {
        para = _paragraphCache[i]!;
      } else {
        para = _buildHighlightedParagraph(i, lineText);
        _paragraphCache[i] = para;
      }

      double guideX;
      if (leadingSpaces > 0) {
        final boxes = para.getBoxesForRange(0, leadingSpaces);
        guideX = boxes.isNotEmpty ? boxes.last.right : 0;
      } else {
        guideX = 0;
      }

      blocks.add((
        startLine: i,
        endLine: endLine,
        indentLevel: indentLevel,
        guideX: guideX,
      ));
    }

    final scanBackLimit = 500;
    final scanStart = (firstVisibleLine - scanBackLimit).clamp(
      0,
      firstVisibleLine,
    );
    for (int i = scanStart; i < firstVisibleLine; i++) {
      processLine(i);
    }

    for (
      int i = firstVisibleLine;
      i <= lastVisibleLine && i < controller.lineCount;
      i++
    ) {
      processLine(i);
    }

    int? selectedBlockIndex;
    int minBlockSize = 999999;

    for (int idx = 0; idx < blocks.length; idx++) {
      final block = blocks[idx];
      if (currentLine >= block.startLine && currentLine < block.endLine) {
        final blockSize = block.endLine - block.startLine;
        if (blockSize < minBlockSize) {
          minBlockSize = blockSize;
          selectedBlockIndex = idx;
        }
      }
    }

    for (int idx = 0; idx < blocks.length; idx++) {
      final block = blocks[idx];
      final isSelected = selectedBlockIndex == idx;

      final guidePaint = Paint()
        ..color = isSelected ? textColor : textColor.withAlpha(100)
        ..strokeWidth = isSelected ? 1.0 : 0.5
        ..style = PaintingStyle.stroke;

      double yTop;
      if (!lineWrap && !hasActiveFolds) {
        yTop = (block.startLine + 1) * _lineHeight;
      } else {
        yTop = _getLineYOffset(block.startLine + 1, hasActiveFolds);
      }

      double yBottom;
      if (!lineWrap && !hasActiveFolds) {
        yBottom = (block.endLine - 1) * _lineHeight + _lineHeight;
      } else {
        yBottom = _getLineYOffset(block.endLine, hasActiveFolds);
      }

      final screenYTop =
          offset.dy +
          (innerPadding?.top ?? 0) +
          yTop -
          vscrollController.offset;
      final screenYBottom =
          offset.dy +
          (innerPadding?.top ?? 0) +
          yBottom -
          vscrollController.offset;

      if (screenYBottom < 0 || screenYTop > viewBottom - viewTop) continue;

      final screenGuideX =
          offset.dx +
          _gutterWidth +
          (innerPadding?.left ?? 0) +
          block.guideX -
          (lineWrap ? 0 : hscrollController.offset);

      if (screenGuideX < offset.dx + _gutterWidth ||
          screenGuideX > offset.dx + size.width) {
        continue;
      }

      final clampedYTop = screenYTop.clamp(0.0, viewBottom - viewTop);
      final clampedYBottom = screenYBottom.clamp(0.0, viewBottom - viewTop);

      canvas.drawLine(
        Offset(screenGuideX, clampedYTop),
        Offset(screenGuideX, clampedYBottom),
        guidePaint,
      );
    }
  }

  void _drawBracketHighlight(
    Canvas canvas,
    Offset offset,
    double viewTop,
    double viewBottom,
    int firstVisibleLine,
    int lastVisibleLine,
    double firstVisibleLineY,
    bool hasActiveFolds,
    Color textColor,
  ) {
    final (bracket1, bracket2) = _getBracketPairAtCursor();
    if (bracket1 == null || bracket2 == null) return;

    final line1 = controller.getLineAtOffset(bracket1);
    final line2 = controller.getLineAtOffset(bracket2);

    if (line1 >= firstVisibleLine &&
        line1 <= lastVisibleLine &&
        (!hasActiveFolds || !_isLineFolded(line1))) {
      _drawBracketBox(
        canvas,
        offset,
        bracket1,
        line1,
        hasActiveFolds,
        textColor,
      );
    }

    if (line2 >= firstVisibleLine &&
        line2 <= lastVisibleLine &&
        (!hasActiveFolds || !_isLineFolded(line2))) {
      _drawBracketBox(
        canvas,
        offset,
        bracket2,
        line2,
        hasActiveFolds,
        textColor,
      );
    }
  }

  void _drawBracketBox(
    Canvas canvas,
    Offset offset,
    int bracketOffset,
    int lineIndex,
    bool hasActiveFolds,
    Color textColor,
  ) {
    final lineStartOffset = controller.getLineStartOffset(lineIndex);
    final columnIndex = bracketOffset - lineStartOffset;

    String lineText;
    if (_lineTextCache.containsKey(lineIndex)) {
      lineText = _lineTextCache[lineIndex]!;
    } else {
      lineText = controller.getLineText(lineIndex);
      _lineTextCache[lineIndex] = lineText;
    }

    if (columnIndex < 0 || columnIndex >= lineText.length) return;

    ui.Paragraph para;
    if (_paragraphCache.containsKey(lineIndex)) {
      para = _paragraphCache[lineIndex]!;
    } else {
      para = _buildHighlightedParagraph(
        lineIndex,
        lineText,
        width: lineWrap ? _wrapWidth : null,
      );
      _paragraphCache[lineIndex] = para;
    }

    final boxes = para.getBoxesForRange(columnIndex, columnIndex + 1);
    if (boxes.isEmpty) return;

    final box = boxes.first;

    final lineY = _getLineYOffset(lineIndex, hasActiveFolds);
    final boxY = lineY + box.top;

    final screenX =
        offset.dx +
        _gutterWidth +
        (innerPadding?.left ?? 0) +
        box.left -
        (lineWrap ? 0 : hscrollController.offset);
    final screenY =
        offset.dy + (innerPadding?.top ?? 0) + boxY - vscrollController.offset;

    final bracketRect = Rect.fromLTWH(
      screenX - 1,
      screenY,
      box.right - box.left + 2,
      _lineHeight,
    );

    _bracketHighlightPainter.color = textColor;
    canvas.drawRect(bracketRect, _bracketHighlightPainter);
  }

  void _drawDiagnostics(
    Canvas canvas,
    Offset offset,
    int firstVisibleLine,
    int lastVisibleLine,
    double firstVisibleLineY,
    bool hasActiveFolds,
  ) {
    if (_diagnostics.isEmpty) return;

    for (final diagnostic in _diagnostics) {
      final range = diagnostic.range;
      final startPos = range['start'] as Map<String, dynamic>;
      final endPos = range['end'] as Map<String, dynamic>;

      final startLine = startPos['line'] as int;
      final startChar = startPos['character'] as int;
      final endLine = endPos['line'] as int;
      final endChar = endPos['character'] as int;

      if (endLine < firstVisibleLine || startLine > lastVisibleLine) continue;

      final Color underlineColor;
      switch (diagnostic.severity) {
        case 1:
          underlineColor = Colors.red;
          break;
        case 2:
          underlineColor = Colors.yellow.shade700;
          break;
        case 3:
          underlineColor = Colors.blue;
          break;
        case 4:
          underlineColor = Colors.grey;
          break;
        default:
          underlineColor = Colors.red;
      }

      final paint = Paint()
        ..color = underlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      for (int lineIndex = startLine; lineIndex <= endLine; lineIndex++) {
        if (lineIndex < firstVisibleLine || lineIndex > lastVisibleLine) {
          continue;
        }
        if (hasActiveFolds && _isLineFolded(lineIndex)) continue;

        String lineText;
        if (_lineTextCache.containsKey(lineIndex)) {
          lineText = _lineTextCache[lineIndex]!;
        } else {
          lineText = controller.getLineText(lineIndex);
          _lineTextCache[lineIndex] = lineText;
        }

        if (lineText.isEmpty) continue;

        ui.Paragraph para;
        if (_paragraphCache.containsKey(lineIndex)) {
          para = _paragraphCache[lineIndex]!;
        } else {
          para = _buildHighlightedParagraph(
            lineIndex,
            lineText,
            width: lineWrap ? _wrapWidth : null,
          );
          _paragraphCache[lineIndex] = para;
        }

        final lineStartChar = (lineIndex == startLine) ? startChar : 0;
        final lineEndChar = (lineIndex == endLine)
            ? endChar.clamp(0, lineText.length)
            : lineText.length;

        if (lineStartChar >= lineEndChar || lineStartChar >= lineText.length) {
          continue;
        }

        final boxes = para.getBoxesForRange(
          lineStartChar.clamp(0, lineText.length),
          lineEndChar.clamp(0, lineText.length),
        );

        if (boxes.isEmpty) continue;

        final lineY = _getLineYOffset(lineIndex, hasActiveFolds);

        for (final box in boxes) {
          final screenX =
              offset.dx +
              _gutterWidth +
              (innerPadding?.left ?? 0) +
              box.left -
              (lineWrap ? 0 : hscrollController.offset);
          final screenY =
              offset.dy
              + (innerPadding?.top ?? 0)
              + lineY
              + box.top
              + _lineHeight
              - vscrollController.offset;

          final width = box.right - box.left;
          _drawSquigglyLine(canvas, screenX, screenY, width, paint);
        }
      }
    }
  }

  void _drawSquigglyLine(
    Canvas canvas,
    double x,
    double y,
    double width,
    Paint paint,
  ) {
    if (width <= 0) return;

    final path = Path();
    const waveHeight = 2.0;
    const waveWidth = 4.0;

    path.moveTo(x, y);

    double currentX = x;
    bool up = true;

    while (currentX < x + width) {
      final nextX = (currentX + waveWidth).clamp(x, x + width);
      final controlY = up ? y - waveHeight : y + waveHeight;

      path.quadraticBezierTo((currentX + nextX) / 2, controlY, nextX, y);

      currentX = nextX;
      up = !up;
    }

    canvas.drawPath(path, paint);
  }

  void _drawSelection(
    Canvas canvas,
    Offset offset,
    int firstVisibleLine,
    int lastVisibleLine,
    double firstVisibleLineY,
    bool hasActiveFolds,
  ) {
    final selection = controller.selection;
    if (selection.isCollapsed) return;

    final start = selection.start;
    final end = selection.end;

    final selectionPaint = Paint()
      ..color = selectionStyle.selectionColor
      ..style = PaintingStyle.fill;

    int startLine = controller.getLineAtOffset(start);
    int endLine = controller.getLineAtOffset(end);

    if (endLine < firstVisibleLine || startLine > lastVisibleLine) return;

    for (int lineIndex = startLine; lineIndex <= endLine; lineIndex++) {
      if (lineIndex < firstVisibleLine || lineIndex > lastVisibleLine) continue;
      if (hasActiveFolds && _isLineFolded(lineIndex)) continue;

      final lineStartOffset = controller.getLineStartOffset(lineIndex);
      final lineText =
          _lineTextCache[lineIndex] ?? controller.getLineText(lineIndex);
      final lineLength = lineText.length;

      int lineSelStart = 0;
      int lineSelEnd = lineLength;

      if (lineIndex == startLine) {
        lineSelStart = start - lineStartOffset;
      }
      if (lineIndex == endLine) {
        lineSelEnd = end - lineStartOffset;
      }

      lineSelStart = lineSelStart.clamp(0, lineLength);
      lineSelEnd = lineSelEnd.clamp(0, lineLength);

      if (lineSelStart >= lineSelEnd && lineIndex != endLine) {
        lineSelEnd = lineLength;
      }

      ui.Paragraph para;
      if (_paragraphCache.containsKey(lineIndex)) {
        para = _paragraphCache[lineIndex]!;
      } else {
        para = _buildHighlightedParagraph(
          lineIndex,
          lineText,
          width: lineWrap ? _wrapWidth : null,
        );
        _paragraphCache[lineIndex] = para;
      }

      final lineY = _getLineYOffset(lineIndex, hasActiveFolds);

      if (lineSelStart < lineSelEnd && lineText.isNotEmpty) {
        final boxes = para.getBoxesForRange(
          lineSelStart.clamp(0, lineText.length),
          lineSelEnd.clamp(0, lineText.length),
        );

        for (final box in boxes) {
          final screenX =
              offset.dx +
              _gutterWidth +
              (innerPadding?.left ?? 0) +
              box.left -
              (lineWrap ? 0 : hscrollController.offset);
          final screenY =
              offset.dy +
              (innerPadding?.top ?? 0) +
              lineY +
              box.top -
              vscrollController.offset;

          canvas.drawRect(
            Rect.fromLTWH(screenX, screenY, box.right - box.left, _lineHeight),
            selectionPaint,
          );
        }
      } else if (lineIndex < endLine) {
        final screenX =
            offset.dx +
            _gutterWidth +
            (innerPadding?.left ?? 0) -
            (lineWrap ? 0 : hscrollController.offset);
        final screenY =
            offset.dy +
            (innerPadding?.top ?? 0) +
            lineY -
            vscrollController.offset;

        canvas.drawRect(
          Rect.fromLTWH(screenX, screenY, 8, _lineHeight),
          selectionPaint,
        );
      }
    }

    _updateSelectionHandleRects(
      offset,
      start,
      end,
      startLine,
      endLine,
      hasActiveFolds,
    );
  }

  void _updateSelectionHandleRects(
    Offset offset,
    int start,
    int end,
    int startLine,
    int endLine,
    bool hasActiveFolds,
  ) {
    final handleRadius = (_lineHeight / 2).clamp(6.0, 12.0);

    final startLineOffset = controller.getLineStartOffset(startLine);
    final startLineText =
        _lineTextCache[startLine] ?? controller.getLineText(startLine);
    final startCol = start - startLineOffset;

    final startY = _getLineYOffset(startLine, hasActiveFolds);

    double startX;
    double startYInLine = 0;
    if (startLineText.isNotEmpty && startCol > 0) {
      final para =
          _paragraphCache[startLine] ??
          _buildHighlightedParagraph(
            startLine,
            startLineText,
            width: lineWrap ? _wrapWidth : null,
          );
      final boxes = para.getBoxesForRange(
        0,
        startCol.clamp(0, startLineText.length),
      );
      if (boxes.isNotEmpty) {
        startX = boxes.last.right;
        startYInLine = boxes.last.top;
      } else {
        startX = 0;
      }
    } else {
      startX = 0;
    }

    final startScreenX =
        offset.dx +
        _gutterWidth +
        (innerPadding?.left ?? 0) +
        startX -
        (lineWrap ? 0 : hscrollController.offset);
    final startScreenY =
        offset.dy +
        (innerPadding?.top ?? 0) +
        startY +
        startYInLine -
        vscrollController.offset;

    _startHandleRect = Rect.fromCenter(
      center: Offset(startScreenX - (textStyle?.fontSize ?? 14 ) / 2, startScreenY + _lineHeight + handleRadius),
      width: handleRadius * 2 * 1.2,
      height: handleRadius * 2 * 1.2,
    );

    final endLineOffset = controller.getLineStartOffset(endLine);
    final endLineText =
        _lineTextCache[endLine] ?? controller.getLineText(endLine);
    final endCol = end - endLineOffset;

    final endY = _getLineYOffset(endLine, hasActiveFolds);

    double endX;
    double endYInLine = 0;
    if (endLineText.isNotEmpty && endCol > 0) {
      final para =
          _paragraphCache[endLine] ??
          _buildHighlightedParagraph(
            endLine,
            endLineText,
            width: lineWrap ? _wrapWidth : null,
          );
      final boxes = para.getBoxesForRange(
        0,
        endCol.clamp(0, endLineText.length),
      );
      if (boxes.isNotEmpty) {
        endX = boxes.last.right;
        endYInLine = boxes.last.top;
      } else {
        endX = 0;
      }
    } else {
      endX = 0;
    }

    final endScreenX =
        offset.dx +
        _gutterWidth +
        (innerPadding?.left ?? 0) +
        endX -
        (lineWrap ? 0 : hscrollController.offset);
    final endScreenY =
        offset.dy +
        (innerPadding?.top ?? 0) +
        endY +
        endYInLine -
        vscrollController.offset;

    _endHandleRect = Rect.fromCenter(
      center: Offset(endScreenX + (textStyle?.fontSize ?? 14 ) / 2, endScreenY + _lineHeight + handleRadius),
      width: handleRadius * 2 * 1.2,
      height: handleRadius * 2 * 1.2,
    );
  }


  void _drawAiGhostText(
    Canvas canvas,
    Offset offset,
    int firstVisibleLine,
    int lastVisibleLine,
    double firstVisibleLineY,
    bool hasActiveFolds,
  ) {
    if (_aiResponse == null || _aiResponse!.isEmpty) return;
    if (!controller.selection.isValid || !controller.selection.isCollapsed) {
      return;
    }

    final cursorOffset = controller.selection.extentOffset;
    final cursorLine = controller.getLineAtOffset(cursorOffset);

    if (cursorLine < firstVisibleLine || cursorLine > lastVisibleLine) return;
    if (hasActiveFolds && _isLineFolded(cursorLine)) return;

    final lineStartOffset = controller.getLineStartOffset(cursorLine);
    final cursorCol = cursorOffset - lineStartOffset;

    final lineText =
        _lineTextCache[cursorLine] ?? controller.getLineText(cursorLine);

    double cursorX;
    double cursorYInLine = 0;
    if (lineText.isNotEmpty && cursorCol > 0) {
      final para =
          _paragraphCache[cursorLine] ??
          _buildHighlightedParagraph(
            cursorLine,
            lineText,
            width: lineWrap ? _wrapWidth : null,
          );
      final boxes = para.getBoxesForRange(
        0,
        cursorCol.clamp(0, lineText.length),
      );
      if (boxes.isNotEmpty) {
        cursorX = boxes.last.right;
        cursorYInLine = boxes.last.top;
      } else {
        cursorX = 0;
      }
    } else {
      cursorX = 0;
    }

    final cursorY = _getLineYOffset(cursorLine, hasActiveFolds) + cursorYInLine;

    final ghostColor =
        (textStyle?.color ?? editorTheme['root']?.color ?? Colors.white)
            .withAlpha(100);
    final ghostStyle = ui.TextStyle(
      color: ghostColor,
      fontSize: textStyle?.fontSize ?? 14.0,
      fontFamily: textStyle?.fontFamily,
      fontStyle: FontStyle.italic,
    );

    final aiLines = _aiResponse?.split('\n') ?? [];

    for (int i = 0; i < aiLines.length; i++) {
      if(aiLines.isEmpty) break;
      final aiLineText = aiLines[i];
      if (aiLineText.isEmpty && i < aiLines.length - 1) continue;

      final lineIndex = cursorLine + i;

      
      if (lineIndex < firstVisibleLine) continue;

      double lineY;
      if (i == 0) {
        lineY = cursorY;
      } else {
        lineY = _getLineYOffset(lineIndex, hasActiveFolds);
      }

      final lineX = (i == 0) ? cursorX : 0;

      final builder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: textStyle?.fontFamily,
                fontSize: textStyle?.fontSize ?? 14.0,
                height: textStyle?.height ?? 1.2,
              ),
            )
            ..pushStyle(ghostStyle)
            ..addText(aiLineText);

      final para = builder.build();
      para.layout(const ui.ParagraphConstraints(width: double.infinity));

      final screenX =
          offset.dx +
          _gutterWidth +
          (innerPadding?.left ?? 0) +
          lineX -
          (lineWrap ? 0 : hscrollController.offset);
      final screenY =
          offset.dy +
          (innerPadding?.top ?? 0) +
          lineY -
          vscrollController.offset;

      canvas.drawParagraph(para, Offset(screenX, screenY));
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChange);
    _syntaxHighlighter.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    final localPosition = event.localPosition;
    _currentPosition = localPosition;

    final contentPosition = Offset(
      localPosition.dx -
          _gutterWidth -
          (innerPadding?.left ?? innerPadding?.right ?? 0) +
          (lineWrap ? 0 : hscrollController.offset),
      localPosition.dy
        - (innerPadding?.top ?? innerPadding?.bottom ?? 0)
        + vscrollController.offset,
    );
    final textOffset = _getTextOffsetFromPosition(contentPosition);

    if(event is PointerHoverEvent){
      if(!(hoverNotifier.value != null && isHoveringPopup.value)){
        hoverNotifier.value = null;
      }
      
      if(
        (hoverNotifier.value == null || !isHoveringPopup.value) &&
        _isOffsetOverWord(textOffset)
      ){
        _hoverTimer?.cancel();
        _hoverTimer = Timer(Duration(milliseconds: 1500), (){
          final lineChar = _offsetToLineChar(textOffset);
          hoverNotifier.value = [event.localPosition, lineChar];
        });
      } else {
        hoverNotifier.value = null;
      }
    }

    if (
      (event is PointerDownEvent && event.buttons == kSecondaryButton) ||
      (
        event is PointerUpEvent && isMobile && _selectionActive &&
        controller.selection.start != controller.selection.end
      )
    ) {
      contextMenuOffsetNotifier.value = localPosition;
      return;
    }

    if (event is PointerDownEvent && event.buttons == kPrimaryButton) {
      if (contextMenuOffsetNotifier.value.dx >= 0) {
        contextMenuOffsetNotifier.value = const Offset(-1, -1);
      }

      if (enableFolding && enableGutter && localPosition.dx < _gutterWidth) {
        final clickY =
            localPosition.dy +
            vscrollController.offset -
            (innerPadding?.top ?? 0);
        final hasActiveFolds = _foldRanges.any((f) => f.isFolded);
        int clickedLine;

        if (!hasActiveFolds) {
          clickedLine = (clickY / _lineHeight).floor().clamp(
            0,
            controller.lineCount - 1,
          );
        } else {
          clickedLine = 0;
          double currentY = 0;
          for (int i = 0; i < controller.lineCount; i++) {
            if (_isLineFolded(i)) continue;
            if (clickY >= currentY && clickY < currentY + _lineHeight) {
              clickedLine = i;
              break;
            }
            currentY += _lineHeight;
          }
        }

        final foldRange = _getFoldRangeAtLine(clickedLine);
        if (foldRange != null) {
          _toggleFold(foldRange);
          return;
        }
        return;
      }

      _onetap.addPointer(event);
      if (isMobile) {
        _dtap.addPointer(event);
        _draggingCHandle = false;
        _draggingStartHandle = false;
        _draggingEndHandle = false;

        _dtap.onDoubleTap = (){
          _selectWordAtOffset(textOffset);
          contextMenuOffsetNotifier.value = localPosition;
        };

        _onetap.onTap = (){
          if(suggestionNotifier.value != null){
            suggestionNotifier.value = null;
          }
          if(hoverNotifier.value != null){
            hoverNotifier.value = null;
          } else if(_isOffsetOverWord(textOffset)){
            final lineChar = _offsetToLineChar(textOffset);
            hoverNotifier.value = [localPosition, lineChar];
          }
        };

        if (controller.selection.start != controller.selection.end) {
          if (_startHandleRect?.contains(localPosition) ?? false) {
            _draggingStartHandle = true;
            _selectionActive = selectionActiveNotifier.value = true;
            _pointerDownPosition = localPosition;
            return;
          }
          if (_endHandleRect?.contains(localPosition) ?? false) {
            _draggingEndHandle = true;
            _selectionActive = selectionActiveNotifier.value = true;
            _pointerDownPosition = localPosition;
            return;
          }
        } else if (controller.selection.isCollapsed && _normalHandle != null) {
          
          final handleRadius = (_lineHeight / 2).clamp(6.0, 12.0);
          final expandedHandle = _normalHandle!.inflate(handleRadius * 1.5);
          if (expandedHandle.contains(localPosition)) {
            _draggingCHandle = true;
            _selectionActive = selectionActiveNotifier.value = true;
            _dragStartOffset = textOffset; 
            controller.selection = TextSelection.collapsed(offset: textOffset);
            _pointerDownPosition = localPosition;
            return;
          }
        }

        _dragStartOffset = textOffset;
        _isDragging = false;
        _pointerDownPosition = localPosition;
        _selectionActive = false;
        selectionActiveNotifier.value = false;

        _selectionTimer?.cancel();
        _selectionTimer = Timer(const Duration(milliseconds: 500), () {
          _selectWordAtOffset(textOffset);
        });
      } else {
        _dragStartOffset = textOffset;
        _onetap.onTap = (){
          if(suggestionNotifier.value != null){
            suggestionNotifier.value = null;
          }
        };
        controller.selection = TextSelection.collapsed(offset: textOffset);
      }
    }

    if (event is PointerMoveEvent && _dragStartOffset != null) {
      if (isMobile) {
        if (_draggingCHandle) {
          controller.selection = TextSelection.collapsed(offset: textOffset);
          _showBubble = true;
          markNeedsLayout();
          markNeedsPaint();
          return;
        }

        if (_draggingStartHandle || _draggingEndHandle) {
          final base = controller.selection.start;
          final extent = controller.selection.end;

          if (_draggingStartHandle) {
            controller.selection = TextSelection(
              baseOffset: textOffset,
              extentOffset: extent,
            );
            if (textOffset > extent) {
              _draggingStartHandle = false;
              _draggingEndHandle = true;
            }
          } else {
            controller.selection = TextSelection(
              baseOffset: base,
              extentOffset: textOffset,
            );
            if (textOffset < base) {
              _draggingEndHandle = false;
              _draggingStartHandle = true;
            }
          }
          markNeedsLayout();
          markNeedsPaint();
          return;
        }

        if ((localPosition - (_pointerDownPosition ?? localPosition)).distance > 10) {
          _isDragging = true;
          
          _selectionTimer?.cancel();
        }

        if (_isDragging && !_selectionActive) {
          return;
        }

        if (_selectionActive) {
          controller.selection = TextSelection(
            baseOffset: _dragStartOffset!,
            extentOffset: textOffset,
          );
        }
      } else {
        
        controller.selection = TextSelection(
          baseOffset: _dragStartOffset!,
          extentOffset: textOffset,
        );
      }
    }

    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (!_isDragging && isMobile && !_selectionActive) {
        controller.selection = TextSelection.collapsed(offset: textOffset);
      }

      _draggingStartHandle = false;
      _draggingEndHandle = false;
      _draggingCHandle = false;
      _pointerDownPosition = null;
      _dragStartOffset = null;
      _selectionTimer?.cancel();
      
      _cachedMagnifiedParagraph = null;
      _cachedMagnifiedLine = null;
      _cachedMagnifiedOffset = null;
      _selectionActive = selectionActiveNotifier.value = false;
      if(readOnly) return;
      if (!_isDragging) {
        controller.notifyListeners();
      } 

      _isDragging = false;

      if (isMobile && controller.selection.isCollapsed) {
        _showBubble = true;
        markNeedsPaint();
      }
    }
  }

  void _selectWordAtOffset(int offset) {
    _selectionActive = selectionActiveNotifier.value = true;

    final text = controller.text;
    int start = offset, end = offset;

    while (start > 0 && !_isWordBoundary(text[start - 1])) {
      start--;
    }
    while (end < text.length && !_isWordBoundary(text[end])) {
      end++;
    }

    controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    markNeedsPaint();
  }

  bool _isWordBoundary(String char) {
    return char.trim().isEmpty || !RegExp(r'\w').hasMatch(char);
  }

  bool _isOffsetOverWord(int offset) {
    final text = controller.text;
    if (offset < 0 || offset >= text.length) return false;
    return RegExp(r'\w').hasMatch(text[offset]);
  }

  Map<String, int> _offsetToLineChar(int offset) {
    int accum = 0;
    for (int i = 0; i < controller.lineCount; i++) {
      final lineLen = controller.getLineText(i).length;
      if (offset >= accum && offset <= accum + lineLen) {
        return {'line': i, 'character': offset - accum};
      }
      accum += lineLen + 1;
    }
    final last = controller.lineCount - 1;
    return {'line': last, 'character': controller.getLineText(last).length};
  }

  @override
  MouseCursor get cursor {
    if (_currentPosition.dx >= 0 && _currentPosition.dx < _gutterWidth) {
      final hasActiveFolds = _foldRanges.any((f) => f.isFolded);
      for (final fold in _foldRanges) {
        if (fold.startIndex >= controller.lineCount) continue;
        final foldY =
            _getLineYOffset(fold.startIndex, hasActiveFolds) +
            (innerPadding?.top ?? 0) -
            vscrollController.offset;
        final lineHeight = lineWrap
            ? _getWrappedLineHeight(fold.startIndex)
            : _lineHeight;
        if (_currentPosition.dy >= foldY &&
            _currentPosition.dy <= foldY + lineHeight) {
          return SystemMouseCursors.click;
        }
      }
      return MouseCursor.defer;
    }
    return SystemMouseCursors.text;
  }

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => (event) {
    _hoverTimer?.cancel();
  };

  @override
  bool get validForMouseTracker => true;
}

class FoldRange {
  final int startIndex;
  final int endIndex;
  bool isFolded = false;
  List<FoldRange> originallyFoldedChildren = [];

  FoldRange(this.startIndex, this.endIndex);

  void addOriginallyFoldedChild(FoldRange child) {
    if (!originallyFoldedChildren.contains(child)) {
      originallyFoldedChildren.add(child);
    }
  }

  void clearOriginallyFoldedChildren() {
    originallyFoldedChildren.clear();
  }

  bool containsLine(int line) {
    return line > startIndex && line <= endIndex;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FoldRange &&
        other.startIndex == startIndex &&
        other.endIndex == endIndex;
  }

  @override
  int get hashCode => startIndex.hashCode ^ endIndex.hashCode;
}
