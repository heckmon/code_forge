import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import '../LSP/lsp.dart';
import 'controller.dart';
import 'find_controller.dart';
import 'scroll.dart';
import 'styling.dart';
import 'syntax_highlighter.dart';
import 'undo_redo.dart';

import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/vs2015.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

const String _wordCharPattern = r'[\w\u0600-\u06FF\u08A0-\u08FF\u0590-\u05FF]';

/// A highly customizable code editor widget for Flutter.
///
/// [CodeForge] provides a feature-rich code editing experience with support for:
/// - Syntax highlighting for multiple languages
/// - Code folding
/// - Line numbers and gutter
/// - Auto-indentation and bracket matching
/// - LSP (Language Server Protocol) integration
/// - AI code completion
/// - Undo/redo functionality
/// - Search highlighting
///
/// Example:
/// ```dart
/// final controller = CodeForgeController();
///
/// CodeForge(
///   controller: controller,
///   language: langDart,
///   enableFolding: true,
///   enableGutter: true,
///   textStyle: TextStyle(
///     fontFamily: 'JetBrains Mono',
///     fontSize: 14,
///   ),
/// )
/// ```
class CodeForge extends StatefulWidget {
  /// The controller for managing the editor's text content and selection.
  ///
  /// If not provided, an internal controller will be created.
  final CodeForgeController? controller;

  /// The finder controller for managing search functionality.
  ///
  /// If not provided, an internal finder controller will be created.
  final FindController? findController;

  /// The controller for managing undo/redo operations.
  ///
  /// If provided, enables undo/redo functionality in the editor.
  final UndoRedoController? undoController;

  /// The syntax highlighting theme as a map of token types to [TextStyle].
  ///
  /// Uses VS2015 dark theme by default if not specified.
  final Map<String, TextStyle>? editorTheme;

  /// The programming language mode for syntax highlighting.
  ///
  /// Determines which language syntax rules to apply. Uses Python mode
  /// by default if not specified.
  final Mode? language;

  /// The focus node for managing keyboard focus.
  ///
  /// If not provided, an internal focus node will be created.
  final FocusNode? focusNode;

  /// The base text style for the editor content.
  ///
  /// Defines the font family, size, and other text properties.
  final TextStyle? textStyle;

  /// The text style for ghost text (inline suggestions).
  ///
  /// This style is applied to the semi-transparent suggestion text
  /// that appears inline. Ghost text is set via the controller's
  /// `setGhostText()` method. If not specified, defaults to the
  /// editor's base text style with reduced opacity.
  ///
  /// Example:
  /// ```dart
  /// CodeForge(
  ///   ghostTextStyle: TextStyle(
  ///     color: Colors.grey.withOpacity(0.5),
  ///     fontStyle: FontStyle.italic,
  ///   ),
  /// )
  /// ```
  final TextStyle? ghostTextStyle;

  /// Padding inside the editor content area.
  final EdgeInsets? innerPadding;

  /// Custom scroll controller for vertical scrolling.
  final ScrollController? verticalScrollController;

  /// Custom scroll controller for horizontal scrolling.
  final ScrollController? horizontalScrollController;

  /// Styling options for text selection and cursor.
  final CodeSelectionStyle? selectionStyle;

  /// Styling options for the gutter (line numbers and fold icons).
  final GutterStyle? gutterStyle;

  /// Styling options for the autocomplete suggestion popup.
  final SuggestionStyle? suggestionStyle;

  /// Styling options for hover documentation popup.
  final HoverDetailsStyle? hoverDetailsStyle;

  /// Styling options for search match highlighting.
  final MatchHighlightStyle? matchHighlightStyle;

  /// The file path for LSP features.
  ///
  /// Required when using LSP integration to identify the document.
  final String? filePath;

  /// Initial text content for the editor.
  ///
  /// Used only during initialization; subsequent changes should use
  /// the controller.
  final String? initialText;

  /// Whether the editor is in read-only mode.
  ///
  /// When true, the user cannot modify the text content.
  final bool readOnly;

  /// Whether to wrap long lines.
  ///
  /// When true, lines wrap at the editor boundary. When false,
  /// horizontal scrolling is enabled.
  final bool lineWrap;

  /// Whether to automatically focus the editor when mounted.
  final bool autoFocus;

  /// Whether to enable code folding functionality.
  ///
  /// When true, fold icons appear in the gutter and code blocks
  /// can be collapsed.
  final bool enableFolding;

  /// Whether to show indentation guide lines.
  ///
  /// Displays vertical lines at each indentation level to help
  /// visualize code structure.
  final bool enableGuideLines;

  /// Whether to show the gutter with line numbers.
  final bool enableGutter;

  /// Whether to show a divider line between gutter and content.
  final bool enableGutterDivider;

  /// Whether to enable autocomplete suggestions.
  ///
  /// Requires LSP integration for language-aware completions.
  final bool enableSuggestions;

  /// Whether to show auto completions in the OS virtual keyboard.
  ///
  /// Defaults to true.
  final bool enableKeyboardSuggestions;

  /// The type of the virtual keyboard that will used by the [CodeForge].
  ///
  /// Defaults to [TextInputType.multiline]
  final TextInputType keyboardType;

  /// The text direction for the editor's content.
  ///
  /// This determines the direction in which text is laid out and rendered.
  /// For left-to-right languages like English, use [TextDirection.ltr].
  /// For right-to-left languages like Arabic or Hebrew, use [TextDirection.rtl].
  ///
  /// Defaults to [TextDirection.ltr].
  final TextDirection textDirection;

  /// If set to true, deleting the first line of a folded block will delete the entire folded region,
  /// else only the first line gets deleted and the rest of the block stays safe.
  /// Defauts to false.
  final bool deleteFoldRangeOnDeletingFirstLine;

  /// Builder for a custom Finder widget.
  ///
  /// This builder is called to create the finder/search widget. It provides
  /// the [FindController] which can be used to control search functionality.
  /// The returned widget should implement [PreferredSizeWidget].
  final PreferredSizeWidget Function(
    BuildContext context,
    FindController findController,
  )?
  finderBuilder;

  /// Creates a [CodeForge] code editor widget.
  const CodeForge({
    super.key,
    this.controller,
    this.undoController,
    this.editorTheme,
    this.language,
    this.ghostTextStyle,
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
    this.enableKeyboardSuggestions = true,
    this.keyboardType = TextInputType.multiline,
    this.textDirection = TextDirection.ltr,
    this.enableGutter = true,
    this.enableGutterDivider = false,
    this.deleteFoldRangeOnDeletingFirstLine = false,
    this.selectionStyle,
    this.gutterStyle,
    this.suggestionStyle,
    this.hoverDetailsStyle,
    this.matchHighlightStyle,
    this.finderBuilder,
    this.findController,
  });

  @override
  State<CodeForge> createState() => _CodeForgeState();
}

class _CodeForgeState extends State<CodeForge> with TickerProviderStateMixin {
  late final ScrollController _hscrollController, _vscrollController;
  late final CodeForgeController _controller;
  late final FocusNode _focusNode;
  late final AnimationController _caretBlinkController;
  late final AnimationController _lineHighlightController;
  late final Map<String, TextStyle> _editorTheme;
  late final Mode _language;
  late final CodeSelectionStyle _selectionStyle;
  late final GutterStyle _gutterStyle;
  late final SuggestionStyle _suggestionStyle;
  late final HoverDetailsStyle _hoverDetailsStyle;
  late final ValueNotifier<List<dynamic>?> _suggestionNotifier;
  late final ValueNotifier<(Offset, Map<String, int>)?> _hoverNotifier;
  late final ValueNotifier<Map<String, dynamic>?> _hoverContentNotifier;
  late final ValueNotifier<List<LspErrors>> _diagnosticsNotifier;
  late final ValueNotifier<LspSignatureHelps?> _lspSignatureNotifier;
  late final ValueNotifier<String?> _aiNotifier;
  late final ValueNotifier<Offset?> _aiOffsetNotifier;
  late final ValueNotifier<Offset> _contextMenuOffsetNotifier;
  late final ValueNotifier<bool> _selectionActiveNotifier, _isHoveringPopup;
  late final ValueNotifier<List<dynamic>?> _lspActionNotifier;
  late final UndoRedoController _undoRedoController;
  late final String? _filePath;
  late final FindController _findController;
  late final VoidCallback _semanticTokensListener;
  late final VoidCallback _controllerListener;
  late final bool _deleteFoldRangeOnDeletingFirstLine;
  final ValueNotifier<Offset> _offsetNotifier = ValueNotifier(Offset(0, 0));
  final ValueNotifier<Offset?> _lspActionOffsetNotifier = ValueNotifier(null);
  final _isMobile = Platform.isAndroid || Platform.isIOS;
  final _suggScrollController = ScrollController();
  final _actionScrollController = ScrollController();
  final Map<String, String> _suggestionDetailsCache = {};
  final Map<String, Map<String, dynamic>> _hoverCache = {};
  late bool _readOnly;
  TextInputConnection? _connection;
  StreamSubscription? _lspResponsesSubscription;
  bool _isHovering = false, _isSignatureInvoked = false;
  bool _isMobileSuggActive = false;
  List<LspSemanticToken>? _semanticTokens;
  List<Map<String, dynamic>> _extraText = [];
  int _semanticTokensVersion = 0;
  int _sugSelIndex = 0, _actionSelIndex = 0;
  String? _selectedSuggestionMd;
  Timer? _hoverTimer;
  bool _hoverSetByTap = false;
  late final VoidCallback _signatureListener;
  late final VoidCallback _hoverListener;
  late final VoidCallback _isHoveringPopupListener;
  late final VoidCallback _selectedSuggestionListener;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? CodeForgeController();
    _findController = widget.findController ?? FindController(_controller);
    _focusNode = widget.focusNode ?? FocusNode();
    _hscrollController =
        widget.horizontalScrollController ?? ScrollController();
    _vscrollController = widget.verticalScrollController ?? ScrollController();
    _editorTheme = widget.editorTheme ?? vs2015Theme;
    _language = widget.language ?? langDart;
    _suggestionNotifier = _controller.suggestionsNotifier;
    _diagnosticsNotifier = _controller.diagnosticsNotifier;
    _lspActionNotifier = _controller.codeActionsNotifier;
    _lspSignatureNotifier = _controller.signatureNotifier;
    _hoverNotifier = ValueNotifier(null);
    _hoverContentNotifier = ValueNotifier(null);
    _aiNotifier = ValueNotifier(null);
    _aiOffsetNotifier = ValueNotifier(null);
    _contextMenuOffsetNotifier = ValueNotifier(const Offset(-1, -1));
    _selectionActiveNotifier = ValueNotifier(false);
    _isHoveringPopup = ValueNotifier<bool>(false);
    _controller.userCodeAction = _fetchCodeActionsForCurrentPosition;
    _selectionStyle = widget.selectionStyle ?? CodeSelectionStyle();
    _undoRedoController = widget.undoController ?? UndoRedoController();
    _filePath = widget.filePath;
    _readOnly = widget.readOnly;
    _deleteFoldRangeOnDeletingFirstLine =
        widget.deleteFoldRangeOnDeletingFirstLine;
    _controller.setUndoController(_undoRedoController);
    _controller.deleteFoldRangeOnDeletingFirstLine =
        _deleteFoldRangeOnDeletingFirstLine;

    if (widget.readOnly && !_controller.readOnly) {
      _controller.readOnly = true;
    } else if (_controller.readOnly && !widget.readOnly) {
      _readOnly = true;
    }

    _gutterStyle =
        widget.gutterStyle ??
        GutterStyle(
          lineNumberStyle: null,
          foldedIconColor: _editorTheme['root']?.color,
          unfoldedIconColor: _editorTheme['root']?.color,
          backgroundColor: _editorTheme['root']?.backgroundColor,
        );

    _suggestionStyle =
        widget.suggestionStyle ??
        SuggestionStyle(
          elevation: 8,
          textStyle: (() {
            TextStyle style = widget.textStyle ?? TextStyle();
            if (style.color == null) {
              style = style.copyWith(color: _editorTheme['root']!.color);
            }
            return style;
          })(),
          backgroundColor: (() {
            final lightnessDelta = 0.03;
            final base = _editorTheme['root']!.backgroundColor!;
            final hsl = HSLColor.fromColor(base);
            final newLightness = (hsl.lightness + lightnessDelta).clamp(
              0.0,
              1.0,
            );
            return hsl.withLightness(newLightness).toColor();
          })(),
          focusColor: ui.Color.fromARGB(108, 2, 66, 129),
          hoverColor: Colors.grey.withAlpha(15),
          splashColor: Colors.blueAccent.withAlpha(50),
          selectedBackgroundColor: Color(0xFF094771),
          borderColor:
              _editorTheme['root']!.color?.withAlpha(50) ?? Colors.grey[400],
          borderWidth: 1.0,
          itemHeight: 24.0,
          iconSize: 16.0,
          methodIconColor: Color(0xFFDCDFE4),
          propertyIconColor: Color(0xFF98C379),
          classIconColor: Color(0xFFE06C75),
          variableIconColor: Color(0xFF61AFEF),
          keywordIconColor: Color(0xFFC678DD),
          labelTextStyle: TextStyle(
            fontSize: widget.textStyle?.fontSize ?? 14,
            fontWeight: FontWeight.w500,
            color: _editorTheme['root']!.color,
          ),
          detailTextStyle: TextStyle(
            fontSize: (widget.textStyle?.fontSize ?? 14) * 0.85,
            color: _editorTheme['root']!.color?.withAlpha(150),
          ),
          typeTextStyle: TextStyle(
            fontSize: (widget.textStyle?.fontSize ?? 14) * 0.9,
            fontStyle: FontStyle.italic,
            color: _editorTheme['root']!.color?.withAlpha(180),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color:
                  _editorTheme['root']!.color?.withAlpha(50) ??
                  Colors.grey[400]!,
              width: 1.0,
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
          backgroundColor: (() {
            final lightnessDelta = 0.03;
            final base = _editorTheme['root']!.backgroundColor!;
            final hsl = HSLColor.fromColor(base);
            final newLightness = (hsl.lightness + lightnessDelta).clamp(
              0.0,
              1.0,
            );
            return hsl.withLightness(newLightness).toColor();
          })(),
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

    _lineHighlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _semanticTokensListener = () {
      final tokens = _controller.semanticTokens.value;
      if (!mounted) return;
      setState(() {
        _semanticTokens = tokens.$1;
        _semanticTokensVersion = tokens.$2;
      });
    };
    _controller.semanticTokens.addListener(_semanticTokensListener);

    _focusNode.addListener(() {
      if (_focusNode.hasFocus && !_readOnly) {
        if (_connection == null || !_connection!.attached) {
          _connection = TextInput.attach(
            _controller,
            TextInputConfiguration(
              readOnly: widget.readOnly,
              enableDeltaModel: true,
              enableSuggestions: widget.enableKeyboardSuggestions,
              inputType: widget.keyboardType,
              inputAction: TextInputAction.newline,
              autocorrect: false,
              viewId: View.of(context).viewId,
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

    Future.microtask(CustomIcons.loadAllCustomFonts);

    if (_filePath == null && _controller.lspConfig != null) {
      throw ArgumentError(
        "The `filePath` parameter cannot be null inorder to use `LspConfig`."
        "A valid file path is required to use the LSP services.",
      );
    }

    if (_filePath != null) {
      if (widget.initialText != null) {
        throw ArgumentError(
          'Cannot provide both filePath and initialText to CodeForge.',
        );
      } else if (_filePath.isNotEmpty) {
        if (_controller.openedFile != _filePath) {
          _controller.openedFile = _filePath;
        }
      }
    } else if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _controller.text = widget.initialText!;
    }

    _controllerListener = () {
      _resetCursorBlink();

      _isMobileSuggActive = _controller.currentlySelectedSuggestion != null;

      if (_readOnly != _controller.readOnly) {
        setState(() {
          _readOnly = _controller.readOnly;
        });
      }

      if (_controller.lastTypedCharacter == '(') {
        _isSignatureInvoked = true;
      } else if (_controller.lastTypedCharacter == ')') {
        _isSignatureInvoked = false;
      }

      if (_isSignatureInvoked) {
        if (_controller.lspConfig != null) {
          (() async => await _controller.callSignatureHelp())();
        }
      } else if (_lspSignatureNotifier.value != null) {
        _lspSignatureNotifier.value = null;
      }

      if (_hoverNotifier.value != null && mounted && !_hoverSetByTap) {
        _hoverTimer?.cancel();
        _hoverNotifier.value = null;
        _hoverContentNotifier.value = null;
      }

      if (_hoverSetByTap) {
        Future.delayed(const Duration(milliseconds: 100), () {
          _hoverSetByTap = false;
        });
      }
    };

    _controller.addListener(_controllerListener);

    _hoverListener = () {
      final hov = _hoverNotifier.value;
      if (hov != null && _controller.lspConfig != null) {
        _fetchHoverContent(hov.$2);
      } else {
        _hoverContentNotifier.value = null;
      }
    };
    _hoverNotifier.addListener(_hoverListener);

    _signatureListener = () {
      if (!mounted) return;
      if (_lspSignatureNotifier.value != null) {
        if (_lspSignatureNotifier.value!.parameters.isEmpty) {
          _lspSignatureNotifier.value = null;
          setState(() {
            _isSignatureInvoked = false;
          });
          return;
        }
      }
    };
    _lspSignatureNotifier.addListener(_signatureListener);

    _isHoveringPopupListener = () {
      if (!_isHoveringPopup.value && _hoverNotifier.value != null) {
        _hoverNotifier.value = null;
      }
    };
    _isHoveringPopup.addListener(_isHoveringPopupListener);

    _selectedSuggestionListener = () {
      if (!mounted) return;
      final selected = _controller.selectedSuggestionNotifier.value;
      if (selected != null && _isMobile) {
        setState(() {
          _sugSelIndex = selected;
        });
        _scrollToSelectedSuggestion();
      }
    };
    _controller.selectedSuggestionNotifier.addListener(
      _selectedSuggestionListener,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.autoFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  void _scrollToSelectedSuggestion() {
    if (!_suggScrollController.hasClients) return;

    final itemExtent = _suggestionStyle.itemHeight ?? 24.0;
    final selectedOffset = _sugSelIndex * itemExtent;
    final currentScroll = _suggScrollController.offset;
    final viewportHeight = _suggScrollController.position.viewportDimension;

    double? targetOffset;

    if (selectedOffset < currentScroll) {
      targetOffset = selectedOffset;
    } else if (selectedOffset + itemExtent > currentScroll + viewportHeight) {
      targetOffset = selectedOffset - viewportHeight + itemExtent;
    }

    if (targetOffset != null) {
      _suggScrollController.jumpTo(
        targetOffset.clamp(
          _suggScrollController.position.minScrollExtent,
          _suggScrollController.position.maxScrollExtent,
        ),
      );
    }
  }

  void _scrollToSelectedAction() {
    if (!_actionScrollController.hasClients) return;

    final itemExtent = _suggestionStyle.itemHeight ?? 24.0;
    final selectedOffset = _actionSelIndex * itemExtent;
    final currentScroll = _actionScrollController.offset;
    final viewportHeight = _actionScrollController.position.viewportDimension;

    double? targetOffset;

    if (selectedOffset < currentScroll) {
      targetOffset = selectedOffset;
    } else if (selectedOffset + itemExtent > currentScroll + viewportHeight) {
      targetOffset = selectedOffset - viewportHeight + itemExtent;
    }

    if (targetOffset != null) {
      _actionScrollController.jumpTo(
        targetOffset.clamp(
          _actionScrollController.position.minScrollExtent,
          _actionScrollController.position.maxScrollExtent,
        ),
      );
    }
  }

  String _getSuggestionCacheKey(dynamic item) {
    if (item is LspCompletion) {
      final map = item.completionItem;
      final id = map['id']?.toString() ?? '';
      final sort = map['sortText']?.toString() ?? '';
      final source = map['source']?.toString() ?? '';
      final label = item.label;
      final importUri = (item.importUri != null && item.importUri!.isNotEmpty)
          ? item.importUri![0]
          : '';
      return 'lsp|$label|$id|$sort|$source|$importUri';
    }
    return 'str|${item.toString()}';
  }

  Future<void> _fetchCodeActionsForCurrentPosition() async {
    if (_controller.lspConfig == null) return;
    final sel = _controller.selection;
    final cursor = sel.extentOffset;
    final line = _controller.getLineAtOffset(cursor);
    final lineStart = _controller.getLineStartOffset(line);
    final character = cursor - lineStart;

    final actions = await _controller.lspConfig!.getCodeActions(
      filePath: _filePath!,
      startLine: line,
      startCharacter: character,
      endLine: line,
      endCharacter: character,
      diagnostics: _diagnosticsNotifier.value
          .map((item) => item.toJson())
          .toList(),
    );

    _suggestionNotifier.value = null;
    _lspActionNotifier.value = actions;
    _actionSelIndex = 0;
    _lspActionOffsetNotifier.value = _offsetNotifier.value;
  }

  Future<void> _fetchHoverContent(Map<String, int> lineChar) async {
    final line = lineChar['line']!;
    final character = lineChar['character']!;
    final cacheKey = '$line:$character';

    if (_hoverCache.containsKey(cacheKey)) {
      if (_hoverNotifier.value != null &&
          _hoverNotifier.value!.$2['line'] == line &&
          _hoverNotifier.value!.$2['character'] == character) {
        _hoverContentNotifier.value = _hoverCache[cacheKey];
      }
      return;
    }

    _hoverContentNotifier.value = null;

    try {
      String diagnosticMessage = '';
      int severity = 0;
      String hoverMessage = '';

      final diagnostic = _diagnosticsNotifier.value.firstWhere((diag) {
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
      }, orElse: () => LspErrors(severity: 0, range: {}, message: ''));

      if (diagnostic.message.isNotEmpty) {
        diagnosticMessage = diagnostic.message;
        severity = diagnostic.severity;
      }

      if (_controller.lspConfig != null) {
        hoverMessage = await _controller.lspConfig!.getHover(
          _filePath!,
          line,
          character,
        );
      }

      final result = {
        'diagnostic': diagnosticMessage,
        'severity': severity,
        'hover': hoverMessage,
      };

      _hoverCache[cacheKey] = result;

      if (_hoverNotifier.value != null &&
          _hoverNotifier.value!.$2['line'] == line &&
          _hoverNotifier.value!.$2['character'] == character) {
        _hoverContentNotifier.value = result;
      }
    } catch (e) {
      debugPrint('Error fetching hover content: $e');
      _hoverContentNotifier.value = {};
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
    _controller.removeListener(_controllerListener);
    _controller.semanticTokens.removeListener(_semanticTokensListener);
    _lspSignatureNotifier.removeListener(_signatureListener);
    _hoverNotifier.removeListener(_hoverListener);
    _isHoveringPopup.removeListener(_isHoveringPopupListener);
    _controller.selectedSuggestionNotifier.removeListener(
      _selectedSuggestionListener,
    );
    _connection?.close();
    _lspResponsesSubscription?.cancel();
    _caretBlinkController.dispose();
    _lineHighlightController.dispose();
    _hoverNotifier.dispose();
    _hoverContentNotifier.dispose();
    _aiNotifier.dispose();
    _aiOffsetNotifier.dispose();
    _contextMenuOffsetNotifier.dispose();
    _selectionActiveNotifier.dispose();
    _isHoveringPopup.dispose();
    _offsetNotifier.dispose();
    _lspActionOffsetNotifier.dispose();
    _suggScrollController.dispose();
    _actionScrollController.dispose();
    _hoverTimer?.cancel();
    super.dispose();
  }

  void _handleArrowRight(bool withShift) {
    final ghost = _controller.ghostText;
    if (ghost != null && !ghost.shouldPersist && !withShift) {
      _acceptControllerGhostText();
      return;
    }

    if (_aiNotifier.value != null) {
      _acceptGhostText();
      return;
    }

    if (_suggestionNotifier.value != null) {
      _suggestionNotifier.value = null;
    }

    if (widget.textDirection == TextDirection.rtl) {
      _controller.pressLetfArrowKey(isShiftPressed: withShift);
    } else {
      _moveSelectionRight(withShift);
    }
  }

  void _handleArrowLeft(bool withShift) {
    if (_suggestionNotifier.value != null) {
      _suggestionNotifier.value = null;
    }

    if (widget.textDirection == TextDirection.rtl) {
      _moveSelectionRight(withShift);
    } else {
      _controller.pressLetfArrowKey(isShiftPressed: withShift);
    }
  }

  void _moveSelectionRight(bool withShift) {
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

  void _handleHomeKey(bool withShift) {
    if (_suggestionNotifier.value != null) {
      _suggestionNotifier.value = null;
    }

    _controller.pressHomeKey(isShiftPressed: withShift);
  }

  void _handleEndKey(bool withShift) {
    if (_suggestionNotifier.value != null) {
      _suggestionNotifier.value = null;
    }

    _controller.pressEndKey(isShiftPressed: withShift);
  }

  Widget _buildContextMenu() {
    return ValueListenableBuilder<Offset>(
      valueListenable: _contextMenuOffsetNotifier,
      builder: (context, offset, _) {
        if (offset.dx < 0 || offset.dy < 0) return const SizedBox.shrink();

        final hasSelection =
            _controller.selection.start != _controller.selection.end;

        if (_isMobile) {
          return TextSelectionToolbar(
            anchorAbove: offset,
            anchorBelow: Offset(offset.dx, offset.dy + 40),
            toolbarBuilder: (BuildContext context, Widget child) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: _hoverDetailsStyle.backgroundColor,
                ),
                child: child,
              );
            },
            children: [
              if (hasSelection) ...[
                if (!_controller.readOnly)
                  TextSelectionToolbarTextButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () {
                      _controller.cut();
                      _contextMenuOffsetNotifier.value = const Offset(-1, -1);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cut,
                          size: 16,
                          color: _editorTheme['root']?.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Cut',
                          style: TextStyle(
                            color: _editorTheme['root']?.color,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                TextSelectionToolbarTextButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: () {
                    _controller.copy();
                    _contextMenuOffsetNotifier.value = const Offset(-1, -1);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.copy,
                        size: 16,
                        color: _editorTheme['root']?.color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Copy',
                        style: TextStyle(
                          color: _editorTheme['root']?.color,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (!_controller.readOnly)
                TextSelectionToolbarTextButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: () async {
                    await _controller.paste();
                    _contextMenuOffsetNotifier.value = const Offset(-1, -1);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.paste,
                        size: 16,
                        color: _editorTheme['root']?.color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Paste',
                        style: TextStyle(
                          color: _editorTheme['root']?.color,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              TextSelectionToolbarTextButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: () {
                  _controller.selectAll();
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.select_all,
                      size: 16,
                      color: _editorTheme['root']?.color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Select All',
                      style: TextStyle(
                        color: _editorTheme['root']?.color,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
                      if (!_controller.readOnly)
                        _buildDesktopContextMenuItem(
                          'Cut',
                          'Ctrl+X',
                          () => _controller.cut(),
                        ),
                      _buildDesktopContextMenuItem(
                        'Copy',
                        'Ctrl+C',
                        () => _controller.copy(),
                      ),
                    ],
                    if (!_controller.readOnly)
                      _buildDesktopContextMenuItem(
                        'Paste',
                        'Ctrl+V',
                        () => _controller.paste(),
                      ),
                    _buildDesktopContextMenuItem(
                      'Select All',
                      'Ctrl+A',
                      () => _controller.selectAll(),
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

  void _commonKeyFunctions() {
    if (_aiNotifier.value != null) {
      _aiNotifier.value = null;
    }

    final ghost = _controller.ghostText;
    if (ghost != null && !ghost.shouldPersist) {
      _controller.clearGhostText();
    }

    _resetCursorBlink();
  }

  void _deleteWordBackward() {
    if (_readOnly) return;
    final selection = _controller.selection;
    final text = _controller.text;

    if (!selection.isCollapsed) {
      _controller.replaceRange(selection.start, selection.end, '');
      return;
    }

    int caret = selection.extentOffset;
    if (caret <= 0) return;

    final prevChar = text[caret - 1];
    if (prevChar == '\n') {
      _controller.replaceRange(caret - 1, caret, '');
      return;
    }

    final before = text.substring(0, caret);
    final lineStart = text.lastIndexOf('\n', caret - 1) + 1;
    final lineText = before.substring(lineStart);

    final match = RegExp(r'(\w+|[^\w\s]+)\s*$').firstMatch(lineText);
    int deleteFrom = caret;
    if (match != null) {
      deleteFrom = lineStart + match.start;
    } else {
      deleteFrom = caret - 1;
    }

    _controller.replaceRange(deleteFrom, caret, '');
  }

  void _deleteWordForward() {
    if (_readOnly) return;
    final selection = _controller.selection;
    final text = _controller.text;

    if (!selection.isCollapsed) {
      _controller.replaceRange(selection.start, selection.end, '');
      return;
    }

    int caret = selection.extentOffset;
    if (caret >= text.length) return;

    final after = text.substring(caret);
    final match = RegExp(r'^(\s*\w+|\s*[^\w\s]+)').firstMatch(after);
    int deleteTo = caret;
    if (match != null) {
      deleteTo = caret + match.end;
    } else {
      deleteTo = caret + 1;
    }

    _controller.replaceRange(caret, deleteTo, '');
  }

  void _moveWordLeft(bool withShift) {
    final selection = _controller.selection;
    final text = _controller.text;
    int caret = selection.extentOffset;

    if (caret <= 0) return;

    final prevNewline = text.lastIndexOf('\n', caret - 1);
    final lineStart = prevNewline == -1 ? 0 : prevNewline + 1;
    if (caret == lineStart && lineStart > 0) {
      final newOffset = lineStart - 1;
      _controller.setSelectionSilently(
        withShift
            ? TextSelection(
                baseOffset: selection.baseOffset,
                extentOffset: newOffset,
              )
            : TextSelection.collapsed(offset: newOffset),
      );
      return;
    }

    final lineText = text.substring(lineStart, caret);
    final wordMatches = RegExp(
      '$_wordCharPattern+|[^$_wordCharPattern\\s]+',
    ).allMatches(lineText).toList();

    int newOffset = lineStart;
    for (final match in wordMatches) {
      if (match.end >= lineText.length) break;
      newOffset = lineStart + match.start;
    }

    _controller.setSelectionSilently(
      withShift
          ? TextSelection(
              baseOffset: selection.baseOffset,
              extentOffset: newOffset,
            )
          : TextSelection.collapsed(offset: newOffset),
    );
  }

  void _moveWordRight(bool withShift) {
    final selection = _controller.selection;
    final text = _controller.text;
    int caret = selection.extentOffset;

    if (caret >= text.length) return;

    if (caret < text.length && text[caret] == '\n') {
      final newOffset = caret + 1;
      _controller.setSelectionSilently(
        withShift
            ? TextSelection(
                baseOffset: selection.baseOffset,
                extentOffset: newOffset,
              )
            : TextSelection.collapsed(offset: newOffset),
      );
      return;
    }

    final regex = RegExp('$_wordCharPattern+|[^$_wordCharPattern\\s]+|\\s+');
    final matches = regex.allMatches(text, caret);

    int newOffset = caret;
    for (final match in matches) {
      if (match.start > caret) {
        newOffset = match.start;
        break;
      }
    }
    if (newOffset == caret) newOffset = text.length;

    _controller.setSelectionSilently(
      withShift
          ? TextSelection(
              baseOffset: selection.baseOffset,
              extentOffset: newOffset,
            )
          : TextSelection.collapsed(offset: newOffset),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    return LayoutBuilder(
      builder: (_, constraints) {
        final editorHeight = constraints.maxHeight;
        return Column(
          children: [
            if (widget.finderBuilder != null)
              ListenableBuilder(
                listenable: _findController,
                builder: (context, _) {
                  if (!_findController.isActive) {
                    return const SizedBox.shrink();
                  }
                  return widget.finderBuilder!(context, _findController);
                },
              ),
            Expanded(
              child: Stack(
                children: [
                  Directionality(
                    textDirection: widget.textDirection,
                    child: RawScrollbar(
                      controller: _vscrollController,
                      thumbVisibility: _isHovering,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: widget.textDirection == TextDirection.rtl
                            ? (Matrix4.identity()
                                ..scaleByVector3(Vector3(-1.0, 1.0, 1.0)))
                            : Matrix4.identity(),
                        child: RawScrollbar(
                          thumbVisibility: _isHovering,
                          controller: _hscrollController,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: widget.textDirection == TextDirection.rtl
                                ? (Matrix4.identity()
                                    ..scaleByVector3(Vector3(-1.0, 1.0, 1.0)))
                                : Matrix4.identity(),
                            child: GestureDetector(
                              onTap: () {
                                _focusNode.requestFocus();
                                if (_contextMenuOffsetNotifier.value.dx >= 0) {
                                  _contextMenuOffsetNotifier.value =
                                      const Offset(-1, -1);
                                }
                                _suggestionNotifier.value = null;
                                _lspSignatureNotifier.value = null;
                              },
                              onDoubleTapDown: (details) {
                                if (_controller.text.isNotEmpty) return;
                                _contextMenuOffsetNotifier.value =
                                    details.localPosition;
                              },
                              child: MouseRegion(
                                onEnter: (event) {
                                  if (mounted) {
                                    setState(() => _isHovering = true);
                                  }
                                },
                                onExit: (event) {
                                  if (mounted) {
                                    setState(() => _isHovering = false);
                                  }
                                },
                                child: ValueListenableBuilder(
                                  valueListenable: _selectionActiveNotifier,
                                  builder: (context, selVal, child) {
                                    return TwoDimensionalScrollable(
                                      horizontalDetails:
                                          ScrollableDetails.horizontal(
                                            controller: _hscrollController,
                                            physics: selVal
                                                ? const NeverScrollableScrollPhysics()
                                                : RTLAwareScrollPhysics(
                                                    isRTL:
                                                        widget.textDirection ==
                                                        TextDirection.rtl,
                                                    isMobile: _isMobile,
                                                  ),
                                          ),
                                      verticalDetails: ScrollableDetails.vertical(
                                        controller: _vscrollController,
                                        physics: selVal
                                            ? const NeverScrollableScrollPhysics()
                                            : const ClampingScrollPhysics(),
                                      ),
                                      viewportBuilder: (_, voffset, hoffset) => CustomViewport(
                                        verticalOffset: voffset,
                                        verticalAxisDirection:
                                            AxisDirection.down,
                                        horizontalOffset: hoffset,
                                        horizontalAxisDirection:
                                            widget.textDirection ==
                                                TextDirection.rtl
                                            ? AxisDirection.left
                                            : AxisDirection.right,
                                        mainAxis: Axis.vertical,
                                        lineWrap: widget.lineWrap,
                                        delegate: TwoDimensionalChildBuilderDelegate(
                                          maxXIndex: 0,
                                          maxYIndex: 0,
                                          builder: (_, vic) {
                                            return Focus(
                                              focusNode: _focusNode,
                                              onKeyEvent: (node, event) {
                                                final isCtrlAltPressed =
                                                    (HardwareKeyboard
                                                            .instance
                                                            .isControlPressed ||
                                                        HardwareKeyboard
                                                            .instance
                                                            .isMetaPressed) &&
                                                    HardwareKeyboard
                                                        .instance
                                                        .isAltPressed;

                                                if (event is KeyDownEvent &&
                                                    isCtrlAltPressed &&
                                                    !_controller
                                                        .inlayHintsVisible) {
                                                  _controller.showInlayHints();
                                                  return KeyEventResult.handled;
                                                }

                                                if (event is KeyUpEvent &&
                                                    _controller
                                                        .inlayHintsVisible) {
                                                  final isStillCtrlAlt =
                                                      (HardwareKeyboard
                                                              .instance
                                                              .isControlPressed ||
                                                          HardwareKeyboard
                                                              .instance
                                                              .isMetaPressed) &&
                                                      HardwareKeyboard
                                                          .instance
                                                          .isAltPressed;
                                                  if (!isStillCtrlAlt) {
                                                    _controller
                                                        .hideInlayHints();
                                                    return KeyEventResult
                                                        .handled;
                                                  }
                                                }

                                                if (event is KeyDownEvent ||
                                                    event is KeyRepeatEvent) {
                                                  final isShiftPressed =
                                                      HardwareKeyboard
                                                          .instance
                                                          .isShiftPressed;
                                                  final isCtrlPressed =
                                                      HardwareKeyboard
                                                          .instance
                                                          .isControlPressed ||
                                                      HardwareKeyboard
                                                          .instance
                                                          .isMetaPressed;
                                                  if (_suggestionNotifier
                                                              .value !=
                                                          null &&
                                                      _suggestionNotifier
                                                          .value!
                                                          .isNotEmpty) {
                                                    final suggestions =
                                                        _suggestionNotifier
                                                            .value!;
                                                    switch (event.logicalKey) {
                                                      case LogicalKeyboardKey
                                                          .arrowDown:
                                                        if (mounted) {
                                                          setState(() {
                                                            _sugSelIndex =
                                                                (_sugSelIndex +
                                                                    1) %
                                                                suggestions
                                                                    .length;
                                                            _scrollToSelectedSuggestion();
                                                          });
                                                        }
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .arrowUp:
                                                        if (mounted) {
                                                          setState(() {
                                                            _sugSelIndex =
                                                                (_sugSelIndex -
                                                                    1 +
                                                                    suggestions
                                                                        .length) %
                                                                suggestions
                                                                    .length;
                                                            _scrollToSelectedSuggestion();
                                                          });
                                                        }
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .enter:
                                                      case LogicalKeyboardKey
                                                          .tab:
                                                        _acceptSuggestion();
                                                        if (_extraText
                                                            .isNotEmpty) {
                                                          _controller
                                                              .applyWorkspaceEdit(
                                                                _extraText,
                                                              );
                                                        }
                                                        setState(() {
                                                          _isSignatureInvoked =
                                                              true;
                                                        });
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .escape:
                                                        _suggestionNotifier
                                                                .value =
                                                            null;
                                                        return KeyEventResult
                                                            .handled;
                                                      default:
                                                        break;
                                                    }
                                                  }

                                                  if (_lspActionNotifier
                                                              .value !=
                                                          null &&
                                                      _lspActionOffsetNotifier
                                                              .value !=
                                                          null &&
                                                      _lspActionNotifier
                                                          .value!
                                                          .isNotEmpty) {
                                                    final actions =
                                                        _lspActionNotifier
                                                            .value!;
                                                    switch (event.logicalKey) {
                                                      case LogicalKeyboardKey
                                                          .arrowDown:
                                                        if (mounted) {
                                                          setState(() {
                                                            _actionSelIndex =
                                                                (_actionSelIndex +
                                                                    1) %
                                                                actions.length;
                                                            _scrollToSelectedAction();
                                                          });
                                                        }
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .arrowUp:
                                                        if (mounted) {
                                                          setState(() {
                                                            _actionSelIndex =
                                                                (_actionSelIndex -
                                                                    1 +
                                                                    actions
                                                                        .length) %
                                                                actions.length;
                                                            _scrollToSelectedAction();
                                                          });
                                                        }
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .enter:
                                                      case LogicalKeyboardKey
                                                          .tab:
                                                        (() async {
                                                          await _controller
                                                              .applyWorkspaceEdit(
                                                                _lspActionNotifier
                                                                    .value![_actionSelIndex],
                                                              );
                                                        })();
                                                        _lspActionNotifier
                                                                .value =
                                                            null;
                                                        _lspActionOffsetNotifier
                                                                .value =
                                                            null;
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .escape:
                                                        _lspActionNotifier
                                                                .value =
                                                            null;
                                                        _lspActionOffsetNotifier
                                                                .value =
                                                            null;
                                                        return KeyEventResult
                                                            .handled;
                                                      default:
                                                        break;
                                                    }
                                                  }

                                                  if (isCtrlPressed &&
                                                      isShiftPressed) {
                                                    switch (event.logicalKey) {
                                                      case LogicalKeyboardKey
                                                          .space:
                                                        setState(() {
                                                          _isSignatureInvoked =
                                                              true;
                                                        });
                                                        (() async =>
                                                            await _controller
                                                                .callSignatureHelp())();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .arrowUp:
                                                        _controller
                                                            .moveLineUp();
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .arrowDown:
                                                        _controller
                                                            .moveLineDown();
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .arrowLeft:
                                                        if (widget
                                                                .textDirection ==
                                                            TextDirection.rtl) {
                                                          _moveWordRight(true);
                                                        } else {
                                                          _moveWordLeft(true);
                                                        }
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .arrowRight:
                                                        if (widget
                                                                .textDirection ==
                                                            TextDirection.rtl) {
                                                          _moveWordLeft(true);
                                                        } else {
                                                          _moveWordRight(true);
                                                        }
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      default:
                                                        break;
                                                    }
                                                  }

                                                  if (isCtrlPressed) {
                                                    switch (event.logicalKey) {
                                                      case LogicalKeyboardKey
                                                          .keyF:
                                                        final isAlt =
                                                            HardwareKeyboard
                                                                .instance
                                                                .isAltPressed;
                                                        _findController
                                                                .isActive =
                                                            true;
                                                        _findController
                                                                .isReplaceMode =
                                                            isAlt;
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .keyH:
                                                        if (!HardwareKeyboard
                                                            .instance
                                                            .isMetaPressed) {
                                                          _findController
                                                                  .isActive =
                                                              true;
                                                          _findController
                                                                  .isReplaceMode =
                                                              true;

                                                          return KeyEventResult
                                                              .handled;
                                                        }
                                                        break;
                                                      case LogicalKeyboardKey
                                                          .keyC:
                                                        _controller.copy();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .keyX:
                                                        if (_readOnly) {
                                                          return KeyEventResult
                                                              .handled;
                                                        }
                                                        _controller.cut();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .keyV:
                                                        if (_readOnly) {
                                                          return KeyEventResult
                                                              .handled;
                                                        }
                                                        _controller.paste();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .keyA:
                                                        _controller.selectAll();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .keyD:
                                                        if (_readOnly) {
                                                          return KeyEventResult
                                                              .handled;
                                                        }
                                                        _controller
                                                            .duplicateLine();
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .keyZ:
                                                        if (_readOnly) {
                                                          return KeyEventResult
                                                              .handled;
                                                        }
                                                        if (_undoRedoController
                                                            .canUndo) {
                                                          _undoRedoController
                                                              .undo();
                                                          _commonKeyFunctions();
                                                        }
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .keyY:
                                                        if (_readOnly) {
                                                          return KeyEventResult
                                                              .handled;
                                                        }
                                                        if (_undoRedoController
                                                            .canRedo) {
                                                          _undoRedoController
                                                              .redo();
                                                          _commonKeyFunctions();
                                                        }
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .backspace:
                                                        if (_readOnly) {
                                                          return KeyEventResult
                                                              .handled;
                                                        }
                                                        _deleteWordBackward();
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .delete:
                                                        if (_readOnly) {
                                                          return KeyEventResult
                                                              .handled;
                                                        }
                                                        _deleteWordForward();
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .arrowLeft:
                                                        if (widget
                                                                .textDirection ==
                                                            TextDirection.rtl) {
                                                          _moveWordRight(false);
                                                        } else {
                                                          _moveWordLeft(false);
                                                        }
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .arrowRight:
                                                        if (widget
                                                                .textDirection ==
                                                            TextDirection.rtl) {
                                                          _moveWordLeft(false);
                                                        } else {
                                                          _moveWordRight(false);
                                                        }
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .period:
                                                        (() async {
                                                          _suggestionNotifier
                                                                  .value =
                                                              null;
                                                          await _fetchCodeActionsForCurrentPosition();
                                                        })();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .home:
                                                        _controller
                                                            .pressDocumentHomeKey(
                                                              isShiftPressed:
                                                                  isShiftPressed,
                                                            );
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .end:
                                                        _controller
                                                            .pressDocumentEndKey(
                                                              isShiftPressed:
                                                                  isShiftPressed,
                                                            );
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      default:
                                                        break;
                                                    }
                                                  }

                                                  if (isShiftPressed &&
                                                      !isCtrlPressed) {
                                                    switch (event.logicalKey) {
                                                      case LogicalKeyboardKey
                                                          .tab:
                                                        if (_readOnly) {
                                                          return KeyEventResult
                                                              .handled;
                                                        }
                                                        _controller.unindent();
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .arrowLeft:
                                                        _handleArrowLeft(true);
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .arrowRight:
                                                        _handleArrowRight(true);
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .arrowUp:
                                                        _controller
                                                            .pressUpArrowKey(
                                                              isShiftPressed:
                                                                  isShiftPressed,
                                                            );
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .arrowDown:
                                                        _controller
                                                            .pressDownArrowKey(
                                                              isShiftPressed:
                                                                  isShiftPressed,
                                                            );
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .home:
                                                        _controller.pressHomeKey(
                                                          isShiftPressed:
                                                              isShiftPressed,
                                                        );
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      case LogicalKeyboardKey
                                                          .end:
                                                        _controller.pressEndKey(
                                                          isShiftPressed:
                                                              isShiftPressed,
                                                        );
                                                        _commonKeyFunctions();
                                                        return KeyEventResult
                                                            .handled;
                                                      default:
                                                        break;
                                                    }
                                                  }

                                                  switch (event.logicalKey) {
                                                    case LogicalKeyboardKey
                                                        .backspace:
                                                      if (_readOnly) {
                                                        return KeyEventResult
                                                            .handled;
                                                      }
                                                      _controller.backspace();
                                                      if (_suggestionNotifier
                                                              .value !=
                                                          null) {
                                                        _suggestionNotifier
                                                                .value =
                                                            null;
                                                      }
                                                      _commonKeyFunctions();
                                                      return KeyEventResult
                                                          .handled;

                                                    case LogicalKeyboardKey
                                                        .delete:
                                                      if (_readOnly) {
                                                        return KeyEventResult
                                                            .handled;
                                                      }
                                                      _controller.delete();
                                                      if (_suggestionNotifier
                                                              .value !=
                                                          null) {
                                                        _suggestionNotifier
                                                                .value =
                                                            null;
                                                      }
                                                      _commonKeyFunctions();
                                                      return KeyEventResult
                                                          .handled;

                                                    case LogicalKeyboardKey
                                                        .arrowDown:
                                                      _controller
                                                          .pressDownArrowKey(
                                                            isShiftPressed:
                                                                isShiftPressed,
                                                          );
                                                      _commonKeyFunctions();
                                                      return KeyEventResult
                                                          .handled;

                                                    case LogicalKeyboardKey
                                                        .arrowUp:
                                                      _controller
                                                          .pressUpArrowKey(
                                                            isShiftPressed:
                                                                isShiftPressed,
                                                          );
                                                      _commonKeyFunctions();
                                                      return KeyEventResult
                                                          .handled;

                                                    case LogicalKeyboardKey
                                                        .arrowRight:
                                                      _handleArrowRight(
                                                        isShiftPressed,
                                                      );
                                                      _commonKeyFunctions();
                                                      return KeyEventResult
                                                          .handled;

                                                    case LogicalKeyboardKey
                                                        .arrowLeft:
                                                      _handleArrowLeft(
                                                        isShiftPressed,
                                                      );
                                                      _commonKeyFunctions();
                                                      return KeyEventResult
                                                          .handled;

                                                    case LogicalKeyboardKey
                                                        .home:
                                                      _handleHomeKey(
                                                        isShiftPressed,
                                                      );
                                                      _commonKeyFunctions();
                                                      return KeyEventResult
                                                          .handled;

                                                    case LogicalKeyboardKey.end:
                                                      _handleEndKey(
                                                        isShiftPressed,
                                                      );
                                                      _commonKeyFunctions();
                                                      return KeyEventResult
                                                          .handled;

                                                    case LogicalKeyboardKey
                                                        .escape:
                                                      _hoverTimer?.cancel();
                                                      _lspSignatureNotifier
                                                              .value =
                                                          null;
                                                      _contextMenuOffsetNotifier
                                                          .value = const Offset(
                                                        -1,
                                                        -1,
                                                      );
                                                      _findController.isActive =
                                                          false;
                                                      _findController
                                                              .isReplaceMode =
                                                          false;
                                                      _aiNotifier.value = null;
                                                      _suggestionNotifier
                                                              .value =
                                                          null;
                                                      _hoverNotifier.value =
                                                          null;
                                                      setState(() {
                                                        _isSignatureInvoked =
                                                            false;
                                                      });
                                                      return KeyEventResult
                                                          .handled;

                                                    case LogicalKeyboardKey.tab:
                                                      if (_readOnly) {
                                                        return KeyEventResult
                                                            .handled;
                                                      }
                                                      final ghost =
                                                          _controller.ghostText;
                                                      if (ghost != null &&
                                                          !ghost
                                                              .shouldPersist) {
                                                        _acceptControllerGhostText();
                                                        return KeyEventResult
                                                            .handled;
                                                      }
                                                      if (_aiNotifier.value !=
                                                          null) {
                                                        _acceptGhostText();
                                                      } else if (_suggestionNotifier
                                                              .value ==
                                                          null) {
                                                        _controller.indent();
                                                        _commonKeyFunctions();
                                                      }
                                                      return KeyEventResult
                                                          .handled;

                                                    case LogicalKeyboardKey
                                                        .enter:
                                                      if (_aiNotifier.value !=
                                                          null) {
                                                        _aiNotifier.value =
                                                            null;
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
                                                languageId: _controller
                                                    .lspConfig
                                                    ?.languageId,
                                                lspConfig:
                                                    _controller.lspConfig,
                                                semanticTokens: _semanticTokens,
                                                semanticTokensVersion:
                                                    _semanticTokensVersion,
                                                innerPadding:
                                                    widget.innerPadding,
                                                vscrollController:
                                                    _vscrollController,
                                                hscrollController:
                                                    _hscrollController,
                                                focusNode: _focusNode,
                                                readOnly: _readOnly,
                                                caretBlinkController:
                                                    _caretBlinkController,
                                                lineHighlightController:
                                                    _lineHighlightController,
                                                textStyle: widget.textStyle,
                                                enableFolding:
                                                    widget.enableFolding,
                                                enableGuideLines:
                                                    widget.enableGuideLines,
                                                enableGutter:
                                                    widget.enableGutter,
                                                enableGutterDivider:
                                                    widget.enableGutterDivider,
                                                gutterStyle: _gutterStyle,
                                                selectionStyle: _selectionStyle,
                                                diagnostics:
                                                    _diagnosticsNotifier.value,
                                                isMobile: _isMobile,
                                                selectionActiveNotifier:
                                                    _selectionActiveNotifier,
                                                contextMenuOffsetNotifier:
                                                    _contextMenuOffsetNotifier,
                                                hoverNotifier: _hoverNotifier,
                                                hoverContentNotifier:
                                                    _hoverContentNotifier,
                                                lineWrap: widget.lineWrap,
                                                offsetNotifier: _offsetNotifier,
                                                aiNotifier: _aiNotifier,
                                                aiOffsetNotifier:
                                                    _aiOffsetNotifier,
                                                isHoveringPopup:
                                                    _isHoveringPopup,
                                                suggestionNotifier:
                                                    _suggestionNotifier,
                                                ghostTextStyle:
                                                    widget.ghostTextStyle,
                                                matchHighlightStyle:
                                                    widget.matchHighlightStyle,
                                                lspActionNotifier:
                                                    _lspActionNotifier,
                                                lspActionOffsetNotifier:
                                                    _lspActionOffsetNotifier,
                                                signatureNotifier:
                                                    _lspSignatureNotifier,
                                                filePath: _filePath,
                                                textDirection:
                                                    widget.textDirection,
                                                onHoverSetByTap: () {
                                                  _hoverSetByTap = true;
                                                },
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _buildContextMenu(),
                  ValueListenableBuilder(
                    valueListenable: _offsetNotifier,
                    builder: (_, offset, __) {
                      return ValueListenableBuilder(
                        valueListenable: _lspSignatureNotifier,
                        builder: (_, signature, __) {
                          if (signature == null ||
                              signature.activeParameter < 0 ||
                              signature.parameters.isEmpty) {
                            return SizedBox.shrink();
                          }
                          final sigScrollCtrl = ScrollController();

                          final desiredWidth = screenWidth < 700
                              ? screenWidth * 0.63
                              : 420.0;
                          final maxBoxHeight = 400.0;
                          final fontSize = widget.textStyle?.fontSize ?? 14;

                          double adjustedLeft = offset.dx;
                          if (adjustedLeft + desiredWidth > screenWidth) {
                            adjustedLeft = screenWidth - desiredWidth;
                          }
                          if (adjustedLeft < 0) {
                            adjustedLeft = 0;
                          }

                          final spaceBelow =
                              editorHeight - offset.dy - fontSize - 10;
                          final spaceAbove = offset.dy - 10;
                          final shouldPositionAbove =
                              maxBoxHeight > spaceBelow &&
                              spaceAbove > maxBoxHeight;

                          double? adjustedTop;
                          double? adjustedBottom;

                          if (shouldPositionAbove) {
                            adjustedBottom = editorHeight - offset.dy + 10;
                          } else {
                            adjustedTop = offset.dy + fontSize + 10;
                          }

                          return Positioned(
                            width: desiredWidth,
                            top: adjustedTop,
                            bottom: adjustedBottom,
                            left: adjustedLeft,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: desiredWidth,
                                maxHeight: maxBoxHeight,
                                minWidth: 70,
                              ),
                              child: Card(
                                color: _hoverDetailsStyle.backgroundColor,
                                shape: _hoverDetailsStyle.shape,
                                child: RawScrollbar(
                                  interactive: true,
                                  controller: sigScrollCtrl,
                                  thumbVisibility: true,
                                  thumbColor: _editorTheme['root']!.color!
                                      .withAlpha(100),
                                  child: SingleChildScrollView(
                                    controller: sigScrollCtrl,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 7,
                                            left: 6.5,
                                          ),
                                          child: RichText(
                                            text: (() {
                                              final label = signature.label;
                                              final activeParamIndex =
                                                  signature.activeParameter;

                                              if (activeParamIndex < 0 ||
                                                  activeParamIndex >=
                                                      signature
                                                          .parameters
                                                          .length) {
                                                return TextSpan(text: label);
                                              }

                                              final paramLabel = signature
                                                  .parameters[activeParamIndex]['label'];

                                              if (paramLabel is List &&
                                                  paramLabel.length >= 2) {
                                                final range = paramLabel
                                                    .cast<int>();
                                                final firstPart = label
                                                    .substring(0, range[0]);
                                                final highlightPart = label
                                                    .substring(
                                                      range[0],
                                                      range[1],
                                                    );
                                                final finalPart = label
                                                    .substring(range[1]);

                                                return TextSpan(
                                                  style: TextStyle(
                                                    fontSize:
                                                        (widget
                                                                .textStyle
                                                                ?.fontSize ??
                                                            15) +
                                                        1.75,
                                                    color: _editorTheme['root']
                                                        ?.color,
                                                  ),
                                                  children: [
                                                    TextSpan(text: firstPart),
                                                    TextSpan(
                                                      text: highlightPart,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.blue,
                                                      ),
                                                    ),
                                                    TextSpan(text: finalPart),
                                                  ],
                                                );
                                              } else if (paramLabel is String) {
                                                final paramText = paramLabel;
                                                final paramIndex = label
                                                    .indexOf(paramText);

                                                if (paramIndex >= 0) {
                                                  final firstPart = label
                                                      .substring(0, paramIndex);
                                                  final highlightPart =
                                                      paramText;
                                                  final finalPart = label
                                                      .substring(
                                                        paramIndex +
                                                            paramText.length,
                                                      );

                                                  return TextSpan(
                                                    style: TextStyle(
                                                      fontSize:
                                                          (widget
                                                                  .textStyle
                                                                  ?.fontSize ??
                                                              15) +
                                                          1.75,
                                                      color:
                                                          _editorTheme['root']
                                                              ?.color,
                                                    ),
                                                    children: [
                                                      TextSpan(text: firstPart),
                                                      TextSpan(
                                                        text: highlightPart,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.blue,
                                                        ),
                                                      ),
                                                      TextSpan(text: finalPart),
                                                    ],
                                                  );
                                                }
                                              }

                                              return TextSpan(
                                                text: label,
                                                style: TextStyle(
                                                  fontSize:
                                                      (widget
                                                              .textStyle
                                                              ?.fontSize ??
                                                          15) +
                                                      1.75,
                                                  color: _editorTheme['root']
                                                      ?.color,
                                                ),
                                              );
                                            })(),
                                          ),
                                        ),
                                        Divider(
                                          color:
                                              signature.documentation.isNotEmpty
                                              ? _editorTheme['root']?.color
                                              : Colors.transparent,
                                          thickness: 0.5,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 6.5,
                                          ),
                                          child: MarkdownBlock(
                                            data: signature.documentation,
                                            config: MarkdownConfig.darkConfig.copy(
                                              configs: [
                                                PConfig(
                                                  textStyle: _hoverDetailsStyle
                                                      .textStyle,
                                                ),
                                                PreConfig(
                                                  language:
                                                      _controller
                                                          .lspConfig
                                                          ?.languageId
                                                          .toLowerCase() ??
                                                      'dart',
                                                  theme: _editorTheme,
                                                  textStyle: TextStyle(
                                                    fontSize: _hoverDetailsStyle
                                                        .textStyle
                                                        .fontSize,
                                                  ),
                                                  styleNotMatched: TextStyle(
                                                    color: _editorTheme['root']!
                                                        .color,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: _editorTheme['root']!
                                                        .backgroundColor!,
                                                    borderRadius:
                                                        BorderRadius.zero,
                                                    border: Border.all(
                                                      width: 0.2,
                                                      color:
                                                          _editorTheme['root']!
                                                              .color ??
                                                          Colors.grey,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  ValueListenableBuilder(
                    valueListenable: _offsetNotifier,
                    builder: (context, offset, child) {
                      if (offset.dy < 0 ||
                          offset.dx < 0 ||
                          !widget.enableSuggestions) {
                        return SizedBox.shrink();
                      }
                      return ValueListenableBuilder(
                        valueListenable: _suggestionNotifier,
                        builder: (_, sugg, child) {
                          if (_aiNotifier.value != null) {
                            return SizedBox.shrink();
                          }
                          if (sugg == null || sugg.isEmpty) {
                            _sugSelIndex = 0;
                            _controller.currentlySelectedSuggestion = null;
                            return SizedBox.shrink();
                          }
                          final completionScrlCtrl = ScrollController();
                          final desiredWidth = screenWidth < 700
                              ? screenWidth * 0.63
                              : screenWidth * 0.3;
                          final suggestionWidth = min(desiredWidth, 400.0);
                          final itemExtent =
                              _suggestionStyle.itemHeight ?? 24.0;
                          final estimatedHeight = min(
                            sugg.length * itemExtent,
                            400.0,
                          );
                          double adjustedLeft = offset.dx;
                          if (adjustedLeft + suggestionWidth > screenWidth) {
                            adjustedLeft = screenWidth - suggestionWidth;
                          }
                          if (adjustedLeft < 0) {
                            adjustedLeft = 0;
                          }
                          final fontSize = widget.textStyle?.fontSize ?? 14;
                          final spaceBelow =
                              editorHeight - offset.dy - fontSize - 10;
                          final spaceAbove = offset.dy - 10;
                          final shouldPositionAbove =
                              estimatedHeight > spaceBelow &&
                              spaceAbove > estimatedHeight;

                          double? adjustedTop;
                          double? adjustedBottom;

                          if (shouldPositionAbove) {
                            adjustedBottom = editorHeight - offset.dy + 10;
                          } else {
                            adjustedTop = offset.dy + fontSize + 10;
                          }

                          return ValueListenableBuilder(
                            valueListenable:
                                _controller.selectedSuggestionNotifier,
                            builder: (context, selected, child) {
                              return Stack(
                                children: [
                                  Positioned(
                                    width: suggestionWidth,
                                    top: adjustedTop,
                                    bottom: adjustedBottom,
                                    left: adjustedLeft,
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
                                          thumbColor: _editorTheme['root']!
                                              .color!
                                              .withAlpha(80),
                                          interactive: true,
                                          controller: _suggScrollController,
                                          child: ListView.builder(
                                            itemExtent:
                                                _suggestionStyle.itemHeight ??
                                                24.0,
                                            controller: _suggScrollController,
                                            padding: EdgeInsets.zero,
                                            shrinkWrap: true,
                                            itemCount: sugg.length,
                                            itemBuilder: (_, indx) {
                                              final item = sugg[indx];
                                              if ((item is LspCompletion) &&
                                                  (indx == _sugSelIndex ||
                                                      (_isMobile &&
                                                          _isMobileSuggActive))) {
                                                final key =
                                                    _getSuggestionCacheKey(
                                                      item,
                                                    );
                                                if (!_suggestionDetailsCache
                                                        .containsKey(key) &&
                                                    _controller.lspConfig !=
                                                        null) {
                                                  (() async {
                                                    try {
                                                      final data = await _controller
                                                          .lspConfig!
                                                          .resolveCompletionItem(
                                                            item.completionItem,
                                                          );
                                                      final mdText =
                                                          "${data['detail'] ?? ''}\n${(() {
                                                            final doc = data['documentation'];
                                                            if (doc == null) {
                                                              return '';
                                                            }

                                                            if (doc is Map<String, dynamic> && doc.containsKey('value')) {
                                                              return doc['value'];
                                                            }

                                                            return doc;
                                                          })()}";
                                                      if (!mounted) return;
                                                      setState(() {
                                                        final edits =
                                                            data['additionalTextEdits'];
                                                        if (edits is List) {
                                                          try {
                                                            _extraText = edits
                                                                .map(
                                                                  (e) =>
                                                                      Map<
                                                                        String,
                                                                        dynamic
                                                                      >.from(
                                                                        e as Map,
                                                                      ),
                                                                )
                                                                .toList();
                                                          } catch (_) {
                                                            _extraText = edits
                                                                .cast<
                                                                  Map<
                                                                    String,
                                                                    dynamic
                                                                  >
                                                                >();
                                                          }
                                                        } else {
                                                          _extraText = [];
                                                        }
                                                        _suggestionDetailsCache[key] =
                                                            mdText;
                                                        _selectedSuggestionMd =
                                                            mdText;
                                                      });
                                                    } catch (e) {
                                                      debugPrint(
                                                        "Completion Resolve failed: ${e.toString()}",
                                                      );
                                                    }
                                                  })();
                                                } else if (_suggestionDetailsCache
                                                    .containsKey(key)) {
                                                  final cached =
                                                      _suggestionDetailsCache[key];
                                                  if (_selectedSuggestionMd !=
                                                      cached) {
                                                    WidgetsBinding.instance
                                                        .addPostFrameCallback((
                                                          _,
                                                        ) {
                                                          if (!mounted) return;
                                                          setState(() {
                                                            _selectedSuggestionMd =
                                                                cached;
                                                          });
                                                        });
                                                  }
                                                }
                                              } else if ((item
                                                      is! LspCompletion) &&
                                                  (indx == _sugSelIndex ||
                                                      (_isMobile &&
                                                          _isMobileSuggActive))) {
                                                if (_selectedSuggestionMd !=
                                                    null) {
                                                  WidgetsBinding.instance
                                                      .addPostFrameCallback((
                                                        _,
                                                      ) {
                                                        if (!mounted) return;
                                                        setState(() {
                                                          _selectedSuggestionMd =
                                                              null;
                                                        });
                                                      });
                                                }
                                              }

                                              return Container(
                                                height:
                                                    _suggestionStyle.itemHeight,
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      ((!_isMobile &&
                                                              (indx ==
                                                                  _sugSelIndex)) ||
                                                          _controller
                                                                  .currentlySelectedSuggestion ==
                                                              indx)
                                                      ? (_suggestionStyle
                                                                .selectedBackgroundColor ??
                                                            _suggestionStyle
                                                                .focusColor)
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                ),
                                                child: InkWell(
                                                  canRequestFocus: false,
                                                  hoverColor: _suggestionStyle
                                                      .hoverColor,
                                                  focusColor: _suggestionStyle
                                                      .focusColor,
                                                  splashColor: _suggestionStyle
                                                      .splashColor,
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                  onTap: () {
                                                    if (mounted) {
                                                      setState(() {
                                                        if (_isMobileSuggActive) {
                                                          _controller
                                                                  .currentlySelectedSuggestion =
                                                              indx;
                                                        } else {
                                                          _sugSelIndex = indx;
                                                        }
                                                        final text =
                                                            item
                                                                is LspCompletion
                                                            ? item.label
                                                            : item as String;
                                                        _controller
                                                            .insertAtCurrentCursor(
                                                              text,
                                                              replaceTypedChar:
                                                                  true,
                                                            );
                                                        if (_extraText
                                                            .isNotEmpty) {
                                                          _controller
                                                              .applyWorkspaceEdit(
                                                                _extraText,
                                                              );
                                                        }
                                                        _suggestionNotifier
                                                                .value =
                                                            null;
                                                        _isSignatureInvoked =
                                                            true;
                                                        _controller
                                                            .callSignatureHelp();
                                                      });
                                                    }
                                                  },
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .center,
                                                    children: [
                                                      if (item
                                                          is LspCompletion) ...[
                                                        item.icon,
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Expanded(
                                                          flex: 3,
                                                          child: Text(
                                                            item.label,
                                                            style:
                                                                _suggestionStyle.labelTextStyle?.copyWith(
                                                                  color:
                                                                      ((!_isMobile &&
                                                                              (indx ==
                                                                                  _sugSelIndex)) ||
                                                                          _controller.currentlySelectedSuggestion ==
                                                                              indx)
                                                                      ? Colors
                                                                            .white
                                                                      : _suggestionStyle
                                                                            .labelTextStyle
                                                                            ?.color,
                                                                ) ??
                                                                _suggestionStyle.textStyle.copyWith(
                                                                  color:
                                                                      ((!_isMobile &&
                                                                              (indx ==
                                                                                  _sugSelIndex)) ||
                                                                          _controller.currentlySelectedSuggestion ==
                                                                              indx)
                                                                      ? Colors
                                                                            .white
                                                                      : _suggestionStyle
                                                                            .textStyle
                                                                            .color,
                                                                ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                        if (item.importUri?[0] !=
                                                            null) ...[
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Expanded(
                                                            flex: 2,
                                                            child: Text(
                                                              item.importUri![0],
                                                              style:
                                                                  _suggestionStyle
                                                                      .detailTextStyle ??
                                                                  _suggestionStyle
                                                                      .textStyle
                                                                      .copyWith(
                                                                        color: _suggestionStyle
                                                                            .textStyle
                                                                            .color
                                                                            ?.withAlpha(
                                                                              150,
                                                                            ),
                                                                      ),
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              textAlign:
                                                                  TextAlign
                                                                      .right,
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                      if (item is String)
                                                        Expanded(
                                                          child: Text(
                                                            item,
                                                            style:
                                                                _suggestionStyle
                                                                    .labelTextStyle ??
                                                                _suggestionStyle
                                                                    .textStyle,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
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
                                  ),
                                  if (_selectedSuggestionMd != null &&
                                      _lspSignatureNotifier.value == null)
                                    Positioned(
                                      width: screenWidth < 700
                                          ? screenWidth * 0.63
                                          : null,
                                      top:
                                          offset.dy +
                                          (widget.textStyle?.fontSize ?? 14) +
                                          10 +
                                          (screenWidth < 700
                                              ? (offset.dy <
                                                            (screenWidth / 2) &&
                                                        400 < screenHeight)
                                                    ? (((widget.textStyle?.fontSize ??
                                                                      14) +
                                                                  6.5) *
                                                              (_suggestionNotifier
                                                                      .value
                                                                      ?.length ??
                                                                  0))
                                                          .clamp(0, 400)
                                                    : -100
                                              : 0),
                                      left: screenWidth < 700
                                          ? offset.dx
                                          : ((adjustedLeft +
                                                        suggestionWidth +
                                                        420) >
                                                    screenWidth
                                                ? adjustedLeft - 420 - 10
                                                : adjustedLeft +
                                                      suggestionWidth),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: 420,
                                          maxHeight: 400,
                                          minWidth: 70,
                                        ),
                                        child: Card(
                                          color: _hoverDetailsStyle
                                              .backgroundColor,
                                          shape: _hoverDetailsStyle.shape,
                                          child: Padding(
                                            padding: EdgeInsets.all(
                                              _selectedSuggestionMd!
                                                      .trim()
                                                      .isEmpty
                                                  ? 0
                                                  : 8.0,
                                            ),
                                            child: RawScrollbar(
                                              interactive: true,
                                              controller: completionScrlCtrl,
                                              thumbVisibility: true,
                                              thumbColor: _editorTheme['root']!
                                                  .color!
                                                  .withAlpha(100),
                                              child: SingleChildScrollView(
                                                controller: completionScrlCtrl,
                                                child: MarkdownBlock(
                                                  data: _selectedSuggestionMd!,
                                                  config: MarkdownConfig.darkConfig.copy(
                                                    configs: [
                                                      PConfig(
                                                        textStyle:
                                                            _hoverDetailsStyle
                                                                .textStyle,
                                                      ),
                                                      PreConfig(
                                                        language:
                                                            _controller
                                                                .lspConfig
                                                                ?.languageId
                                                                .toLowerCase() ??
                                                            'dart',
                                                        theme: _editorTheme,
                                                        textStyle: TextStyle(
                                                          fontSize:
                                                              _hoverDetailsStyle
                                                                  .textStyle
                                                                  .fontSize,
                                                        ),
                                                        styleNotMatched: TextStyle(
                                                          color:
                                                              _editorTheme['root']!
                                                                  .color,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: _editorTheme['root']!
                                                              .backgroundColor!,
                                                          borderRadius:
                                                              BorderRadius.zero,
                                                          border: Border.all(
                                                            width: 0.2,
                                                            color:
                                                                _editorTheme['root']!
                                                                    .color ??
                                                                Colors.grey,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                  ValueListenableBuilder(
                    valueListenable: _hoverNotifier,
                    builder: (_, hov, c) {
                      if (hov == null ||
                          _controller.lspConfig == null ||
                          !widget.enableSuggestions) {
                        return SizedBox.shrink();
                      }
                      final Offset position = hov.$1;
                      final width = _isMobile
                          ? screenWidth * 0.63
                          : screenWidth * 0.3;
                      final maxHeight = _isMobile ? screenHeight * 0.4 : 550.0;

                      double adjustedLeft = position.dx;
                      if (adjustedLeft + width > screenWidth) {
                        adjustedLeft = screenWidth - width;
                      }
                      if (adjustedLeft < 0) {
                        adjustedLeft = 0;
                      }

                      final spaceBelow = editorHeight - position.dy;
                      final spaceAbove = position.dy - 10;
                      final shouldPositionAbove =
                          maxHeight > spaceBelow && spaceAbove > maxHeight;

                      double? adjustedTop;
                      double? adjustedBottom;

                      if (shouldPositionAbove) {
                        adjustedBottom = editorHeight - position.dy + 10;
                      } else {
                        adjustedTop = position.dy;
                      }

                      return Positioned(
                        top: adjustedTop,
                        bottom: adjustedBottom,
                        left: adjustedLeft,
                        width: width,
                        child: MouseRegion(
                          onEnter: (_) => _isHoveringPopup.value = true,
                          onExit: (_) => _isHoveringPopup.value = false,
                          child: ValueListenableBuilder<Map<String, dynamic>?>(
                            valueListenable: _hoverContentNotifier,
                            builder: (_, data, __) {
                              if (data == null) {
                                return ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: width,
                                    maxHeight: maxHeight,
                                  ),
                                  child: Card(
                                    color: _hoverDetailsStyle.backgroundColor,
                                    shape: _hoverDetailsStyle.shape,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        "Loading...",
                                        style: _hoverDetailsStyle.textStyle,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final diagnosticMessage =
                                  data['diagnostic'] ?? '';
                              final severity = data['severity'] ?? 0;
                              final hoverMessage = data['hover'] ?? '';

                              if (diagnosticMessage.isEmpty &&
                                  hoverMessage.isEmpty) {
                                return SizedBox.shrink();
                              }

                              IconData diagnosticIcon;
                              Color diagnosticColor;

                              switch (severity) {
                                case 1:
                                  diagnosticIcon = Icons.error_outline;
                                  diagnosticColor = Colors.red;
                                  break;
                                case 2:
                                  diagnosticIcon = Icons.warning_amber_outlined;
                                  diagnosticColor = Colors.orange;
                                  break;
                                case 3:
                                  diagnosticIcon = Icons.info_outline;
                                  diagnosticColor = Colors.blue;
                                  break;
                                case 4:
                                  diagnosticIcon = Icons.lightbulb_outline;
                                  diagnosticColor = Colors.grey;
                                  break;
                                default:
                                  diagnosticIcon = Icons.info_outline;
                                  diagnosticColor = Colors.grey;
                              }

                              final hoverScrollController = ScrollController();
                              final errorSCrollController = ScrollController();

                              return ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: width,
                                  maxHeight: maxHeight,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (diagnosticMessage.isNotEmpty)
                                      Card(
                                        surfaceTintColor: diagnosticColor,
                                        color:
                                            _hoverDetailsStyle.backgroundColor,
                                        shape: BeveledRectangleBorder(
                                          side: BorderSide(
                                            color: diagnosticColor,
                                            width: 0.2,
                                          ),
                                        ),
                                        margin: EdgeInsets.only(
                                          bottom: hoverMessage.isNotEmpty
                                              ? 4
                                              : 0,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: RawScrollbar(
                                            controller: errorSCrollController,
                                            thumbVisibility: true,
                                            thumbColor: _editorTheme['root']!
                                                .color!
                                                .withAlpha(100),
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              controller: errorSCrollController,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    diagnosticIcon,
                                                    color: diagnosticColor,
                                                    size: 16,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    diagnosticMessage,
                                                    style: _hoverDetailsStyle
                                                        .textStyle,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                    if (hoverMessage.isNotEmpty)
                                      Flexible(
                                        child: Card(
                                          color: _hoverDetailsStyle
                                              .backgroundColor,
                                          shape: _hoverDetailsStyle.shape,
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: RawScrollbar(
                                              controller: hoverScrollController,
                                              thumbVisibility: true,
                                              thumbColor: _editorTheme['root']!
                                                  .color!
                                                  .withAlpha(100),
                                              child: SingleChildScrollView(
                                                controller:
                                                    hoverScrollController,
                                                child: MarkdownBlock(
                                                  data: hoverMessage,
                                                  config: MarkdownConfig.darkConfig.copy(
                                                    configs: [
                                                      PConfig(
                                                        textStyle:
                                                            _hoverDetailsStyle
                                                                .textStyle,
                                                      ),
                                                      PreConfig(
                                                        language:
                                                            _controller
                                                                .lspConfig
                                                                ?.languageId
                                                                .toLowerCase() ??
                                                            "dart",
                                                        theme: _editorTheme,
                                                        textStyle: TextStyle(
                                                          fontSize:
                                                              _hoverDetailsStyle
                                                                  .textStyle
                                                                  .fontSize,
                                                        ),
                                                        styleNotMatched: TextStyle(
                                                          color:
                                                              _editorTheme['root']!
                                                                  .color,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: _editorTheme['root']!
                                                              .backgroundColor!,
                                                          borderRadius:
                                                              BorderRadius.zero,
                                                          border: Border.all(
                                                            width: 0.2,
                                                            color:
                                                                _editorTheme['root']!
                                                                    .color ??
                                                                Colors.grey,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  ValueListenableBuilder<Offset?>(
                    valueListenable: _aiOffsetNotifier,
                    builder: (context, offvalue, child) {
                      return _isMobile &&
                              _aiNotifier.value != null &&
                              offvalue != null &&
                              _aiNotifier.value!.isNotEmpty
                          ? Positioned(
                              top:
                                  offvalue.dy +
                                  (widget.textStyle?.fontSize ?? 14) *
                                      _aiNotifier.value!.split('\n').length +
                                  15,
                              left:
                                  offvalue.dx +
                                  (_aiNotifier.value!.split('\n')[0].length *
                                      (widget.textStyle?.fontSize ?? 14) /
                                      2),
                              child: Row(
                                children: [
                                  InkWell(
                                    onTap: () {
                                      if (_aiNotifier.value == null) return;
                                      _controller.insertAtCurrentCursor(
                                        _aiNotifier.value!,
                                      );
                                      _aiNotifier.value = null;
                                      _aiOffsetNotifier.value = null;
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _editorTheme['root']
                                            ?.backgroundColor,
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(8),
                                        ),
                                        border: BoxBorder.all(
                                          width: 1.5,
                                          color: Color(0xff64b5f6),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.check,
                                        color: _editorTheme['root']?.color,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 30),
                                  InkWell(
                                    onTap: () {
                                      _aiNotifier.value = null;
                                      _aiOffsetNotifier.value = null;
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _editorTheme['root']
                                            ?.backgroundColor,
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(8),
                                        ),
                                        border: BoxBorder.all(
                                          width: 1.5,
                                          color: Colors.red,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.close,
                                        color: _editorTheme['root']?.color,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : SizedBox.shrink();
                    },
                  ),
                  ValueListenableBuilder(
                    valueListenable: _lspActionOffsetNotifier,
                    builder: (_, offset, child) {
                      if (offset == null ||
                          _lspActionNotifier.value == null ||
                          _controller.lspConfig == null ||
                          !widget.enableSuggestions) {
                        return SizedBox.shrink();
                      }

                      return Positioned(
                        width: screenWidth < 700
                            ? screenWidth * 0.63
                            : screenWidth * 0.3,
                        top:
                            offset.dy + (widget.textStyle?.fontSize ?? 14) + 10,
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
                              controller: _actionScrollController,
                              thumbVisibility: true,
                              thumbColor: _editorTheme['root']!.color!
                                  .withAlpha(80),
                              child: ListView.builder(
                                shrinkWrap: true,
                                controller: _actionScrollController,
                                itemExtent: _suggestionStyle.itemHeight ?? 24.0,
                                itemCount: _lspActionNotifier.value!.length,
                                itemBuilder: (_, indx) {
                                  final actionData = _lspActionNotifier.value!
                                      .cast<Map<String, dynamic>>();
                                  return Tooltip(
                                    message: actionData[indx]['title'],
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: indx == _actionSelIndex
                                            ? (_suggestionStyle
                                                      .selectedBackgroundColor ??
                                                  _suggestionStyle.focusColor)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      height: _suggestionStyle.itemHeight,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      child: InkWell(
                                        hoverColor: _suggestionStyle.hoverColor,
                                        splashColor:
                                            _suggestionStyle.splashColor,
                                        borderRadius: BorderRadius.circular(3),
                                        onTap: () {
                                          try {
                                            (() async {
                                              await _controller
                                                  .applyWorkspaceEdit(
                                                    actionData[indx],
                                                  );
                                            })();
                                          } catch (e, st) {
                                            debugPrint(
                                              'Code action failed: $e\n$st',
                                            );
                                          } finally {
                                            _lspActionNotifier.value = null;
                                            _lspActionOffsetNotifier.value =
                                                null;
                                          }
                                        },
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width:
                                                  _suggestionStyle.iconSize ??
                                                  16,
                                              height:
                                                  _suggestionStyle.iconSize ??
                                                  16,
                                              child: Icon(
                                                Icons.lightbulb_outline,
                                                color: Colors.yellowAccent,
                                                size:
                                                    _suggestionStyle.iconSize ??
                                                    16,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                actionData[indx]['title'],
                                                style:
                                                    _suggestionStyle
                                                        .labelTextStyle
                                                        ?.copyWith(
                                                          color:
                                                              indx ==
                                                                  _actionSelIndex
                                                              ? Colors.white
                                                              : _suggestionStyle
                                                                    .labelTextStyle
                                                                    ?.color,
                                                        ) ??
                                                    _suggestionStyle.textStyle
                                                        .copyWith(
                                                          color:
                                                              indx ==
                                                                  _actionSelIndex
                                                              ? Colors.white
                                                              : _suggestionStyle
                                                                    .textStyle
                                                                    .color,
                                                        ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
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
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _acceptSuggestion() {
    _controller.acceptSuggestion(selectedIndex: _sugSelIndex);
    _sugSelIndex = 0;
  }

  void _acceptGhostText() {
    final ghostText = _aiNotifier.value;
    if (ghostText == null || ghostText.isEmpty) return;
    _controller.insertAtCurrentCursor(ghostText);
    _aiNotifier.value = null;
    _aiOffsetNotifier.value = null;
  }

  void _acceptControllerGhostText() {
    final ghost = _controller.ghostText;
    if (ghost == null || ghost.text.isEmpty) return;
    _controller.insertAtCurrentCursor(ghost.text);
    _controller.clearGhostText();
  }
}

class _CodeField extends LeafRenderObjectWidget {
  final CodeForgeController controller;
  final Map<String, TextStyle> editorTheme;
  final Mode language;
  final String? languageId;
  final LspConfig? lspConfig;
  final List<LspSemanticToken>? semanticTokens;
  final int semanticTokensVersion;
  final EdgeInsets? innerPadding;
  final ScrollController vscrollController, hscrollController;
  final FocusNode focusNode;
  final bool readOnly, isMobile, lineWrap;
  final AnimationController caretBlinkController;
  final AnimationController lineHighlightController;
  final TextStyle? textStyle;
  final bool enableFolding, enableGuideLines, enableGutter, enableGutterDivider;
  final GutterStyle gutterStyle;
  final CodeSelectionStyle selectionStyle;
  final List<LspErrors> diagnostics;
  final ValueNotifier<bool> selectionActiveNotifier, isHoveringPopup;
  final ValueNotifier<Offset> contextMenuOffsetNotifier, offsetNotifier;
  final ValueNotifier<(Offset, Map<String, int>)?> hoverNotifier;
  final ValueNotifier<Map<String, dynamic>?> hoverContentNotifier;
  final ValueNotifier<List<dynamic>?> lspActionNotifier, suggestionNotifier;
  final ValueNotifier<String?> aiNotifier;
  final ValueNotifier<LspSignatureHelps?> signatureNotifier;
  final ValueNotifier<Offset?> aiOffsetNotifier, lspActionOffsetNotifier;
  final BuildContext context;
  final TextStyle? ghostTextStyle;
  final String? filePath;
  final MatchHighlightStyle? matchHighlightStyle;
  final VoidCallback? onHoverSetByTap;
  final TextDirection textDirection;

  const _CodeField({
    required this.controller,
    required this.editorTheme,
    required this.language,
    required this.vscrollController,
    required this.hscrollController,
    required this.focusNode,
    required this.readOnly,
    required this.caretBlinkController,
    required this.lineHighlightController,
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
    required this.hoverContentNotifier,
    required this.suggestionNotifier,
    required this.aiNotifier,
    required this.signatureNotifier,
    required this.aiOffsetNotifier,
    required this.lspActionNotifier,
    required this.lspActionOffsetNotifier,
    required this.isHoveringPopup,
    required this.context,
    required this.lineWrap,
    this.textDirection = TextDirection.ltr,
    this.filePath,
    this.textStyle,
    this.languageId,
    this.lspConfig,
    this.semanticTokens,
    this.semanticTokensVersion = 0,
    this.innerPadding,
    this.ghostTextStyle,
    this.matchHighlightStyle,
    this.onHoverSetByTap,
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
      lineHighlightController: lineHighlightController,
      textStyle: textStyle,
      matchHighlightStyle: matchHighlightStyle,
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
      hoverContentNotifier: hoverContentNotifier,
      lineWrap: lineWrap,
      offsetNotifier: offsetNotifier,
      aiNotifier: aiNotifier,
      aiOffsetNotifier: aiOffsetNotifier,
      isHoveringPopup: isHoveringPopup,
      suggestionNotifier: suggestionNotifier,
      lspActionNotifier: lspActionNotifier,
      lspActionOffsetNotifier: lspActionOffsetNotifier,
      signatureNotifier: signatureNotifier,
      ghostTextStyle: ghostTextStyle,
      filePath: filePath,
      onHoverSetByTap: onHoverSetByTap,
      textDirection: textDirection,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _CodeFieldRenderer renderObject,
  ) {
    if (semanticTokens != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        renderObject.updateSemanticTokens(
          semanticTokens!,
          semanticTokensVersion,
        );
      });
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
      ..selectionStyle = selectionStyle
      ..ghostTextStyle = ghostTextStyle
      ..textDirection = textDirection;
  }
}

class _CodeFieldRenderer extends RenderBox implements MouseTrackerAnnotation {
  final CodeForgeController controller;
  final String? languageId, filePath;
  final ScrollController vscrollController, hscrollController;
  final FocusNode focusNode;
  final AnimationController caretBlinkController;
  final AnimationController lineHighlightController;
  final bool isMobile;
  final ValueNotifier<bool> selectionActiveNotifier, isHoveringPopup;
  final ValueNotifier<Offset> contextMenuOffsetNotifier, offsetNotifier;
  final ValueNotifier<(Offset, Map<String, int>)?> hoverNotifier;
  final ValueNotifier<Map<String, dynamic>?> hoverContentNotifier;
  final ValueNotifier<List<dynamic>?> lspActionNotifier, suggestionNotifier;
  final ValueNotifier<Offset?> aiOffsetNotifier, lspActionOffsetNotifier;
  final ValueNotifier<String?> aiNotifier;
  final ValueNotifier<LspSignatureHelps?> signatureNotifier;
  final BuildContext context;
  final LspConfig? lspConfig;
  final VoidCallback? onHoverSetByTap;
  final Map<int, double> _lineWidthCache = {};
  final Map<int, String> _lineTextCache = {};
  final Map<int, Rect> _actionBulbRects = {};
  final Map<Rect, DocumentColor> _colorBoxHitAreas = {};
  final Map<int, ui.Paragraph> _paragraphCache = {};
  final Map<int, double> _lineHeightCache = {};
  final Map<int, FoldRange?> _foldRanges = {};
  final Map<int, int?> _bracketCache = {};
  final Map<
    int,
    List<({int startLine, int endLine, int indentLevel, double guideX})>
  >
  _indentGuideCache = {};
  final Map<String, int> _indentEndLineCache = {};
  final Map<String, List<ui.TextBox>> _diagnosticPathCache = {};
  final Map<String, List<ui.TextBox>> _searchHighlightCache = {};
  final Map<String, double> _lineOffsetCache = {};
  final Map<
    int,
    ({int lineIndex, int columnIndex, Offset offset, double height})
  >
  _caretInfoCache = {};
  final Map<int, int> _lineIndentCache = {};
  final MatchHighlightStyle? _matchHighlightStyle;
  final MatchHighlightStyle? matchHighlightStyle;
  late double _lineHeight;
  final _dtap = DoubleTapGestureRecognizer();
  final _onetap = TapGestureRecognizer();
  late final double _gutterPadding;
  late final Paint _caretPainter;
  late final Paint _bracketHighlightPainter;
  late ui.ParagraphStyle _paragraphStyle;
  late final ui.TextStyle _uiTextStyle;
  late SyntaxHighlighter _syntaxHighlighter;
  late double _gutterWidth;
  TextStyle? _ghostTextStyle;
  Map<String, TextStyle> _editorTheme;
  Mode _language;
  EdgeInsets? _innerPadding;
  double _rightPaddingWidth = 0, _bottomPaddingHeight = 0;
  TextStyle? _textStyle;
  GutterStyle _gutterStyle;
  CodeSelectionStyle _selectionStyle;
  List<LspErrors> _diagnostics;
  int _cachedCaretOffset = -1, _cachedCaretLine = 0, _cachedCaretLineStart = 0;
  int? _dragStartOffset;
  Timer? _selectionTimer, _hoverTimer;
  Offset? _pointerDownPosition;
  Offset _currentPosition = Offset.zero;
  bool _enableFolding, _enableGuideLines, _enableGutter, _enableGutterDivider;
  bool _isFoldToggleInProgress = false, _lineWrap;
  bool _foldRangesNeedsClear = false;
  bool _selectionActive = false, _isDragging = false;
  bool _draggingStartHandle = false, _draggingEndHandle = false;
  bool _showBubble = false, _draggingCHandle = false, _readOnly;
  bool _isDeferringLayout = false, _hasCachedHeight = false;
  TextDirection _textDirection;
  Map<int, FoldRange>? _lastLspFoldRanges;
  Rect? _startHandleRect, _endHandleRect, _normalHandle;
  double _longLineWidth = 0.0, _wrapWidth = double.infinity;
  double _cachedRtlContentWidth = 0.0;
  Timer? _resizeTimer, _layoutDebounceTimer;
  double _cachedTotalHeight = 0.0;
  String? _aiResponse, _lastProcessedText;
  TextSelection? _lastSelectionForAi;
  ui.Paragraph? _cachedMagnifiedParagraph;
  int? _cachedMagnifiedLine, _cachedMagnifiedOffset;
  List<ui.Paragraph>? _cachedSelectionMagnifierParagraphs;
  int? _cachedSelectionMagnifierStartLine, _cachedSelectionMagnifierEndLine;
  int? _ghostTextAnchorLine, _highlightedLine;
  int _lastAppliedSemanticVersion = -1, _lastDocumentVersion = -1;
  int _previousLineCount = 0;
  int _ghostTextLineCount = 0, _cachedLineCount = 0;
  Animation<double>? _lineHighlightAnimation;

  void updateSemanticTokens(List<LspSemanticToken> tokens, int version) {
    if (version < _lastAppliedSemanticVersion) return;
    _lastAppliedSemanticVersion = version;
    _syntaxHighlighter.updateSemanticTokens(tokens, controller.text);
    _paragraphCache.clear();
    _bracketCache.clear();
    _indentGuideCache.clear();
    _indentEndLineCache.clear();
    _diagnosticPathCache.clear();
    _searchHighlightCache.clear();
    _lineOffsetCache.clear();
    _caretInfoCache.clear();
    _lineIndentCache.clear();
  }

  void _checkDocumentVersionAndClearCache() {
    final currentDocVersion = _syntaxHighlighter.documentVersion;
    if (currentDocVersion != _lastDocumentVersion) {
      _lastDocumentVersion = currentDocVersion;
      _paragraphCache.clear();
      _lineTextCache.clear();
      _lineWidthCache.clear();
      _lineHeightCache.clear();
      _bracketCache.clear();
      _indentGuideCache.clear();
      _indentEndLineCache.clear();
      _diagnosticPathCache.clear();
      _searchHighlightCache.clear();
      _lineOffsetCache.clear();
      _caretInfoCache.clear();
      _lineIndentCache.clear();
    }
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
    required this.vscrollController,
    required this.hscrollController,
    required this.focusNode,
    required this.caretBlinkController,
    required this.lineHighlightController,
    required this.isMobile,
    required this.selectionActiveNotifier,
    required this.contextMenuOffsetNotifier,
    required this.offsetNotifier,
    required this.hoverNotifier,
    required this.hoverContentNotifier,
    required this.suggestionNotifier,
    required this.lspActionNotifier,
    required this.lspActionOffsetNotifier,
    required this.aiNotifier,
    required this.aiOffsetNotifier,
    required this.signatureNotifier,
    required this.isHoveringPopup,
    required this.context,
    required bool lineWrap,
    required Map<String, TextStyle> editorTheme,
    required Mode language,
    required bool readOnly,
    required bool enableFolding,
    required bool enableGuideLines,
    required bool enableGutter,
    required bool enableGutterDivider,
    required GutterStyle gutterStyle,
    required CodeSelectionStyle selectionStyle,
    required List<LspErrors> diagnostics,
    this.languageId,
    this.lspConfig,
    this.filePath,
    this.matchHighlightStyle,
    this.onHoverSetByTap,
    EdgeInsets? innerPadding,
    TextStyle? textStyle,
    TextStyle? ghostTextStyle,
    TextDirection textDirection = TextDirection.ltr,
  }) : _editorTheme = editorTheme,
       _ghostTextStyle = ghostTextStyle,
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
       _diagnostics = diagnostics,
       _matchHighlightStyle = matchHighlightStyle,
       _textDirection = textDirection {
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
      textDirection: _textDirection,
      textAlign: ui.TextAlign.start,
    );
    _uiTextStyle = ui.TextStyle(
      color: color,
      fontSize: fontSize,
      fontFamily: fontFamily,
    );

    vscrollController.addListener(() {
      if (suggestionNotifier.value != null && offsetNotifier.value.dy >= 0) {
        offsetNotifier.value = Offset(
          offsetNotifier.value.dx,
          _getCaretInfo().offset.dy - vscrollController.offset,
        );
      }

      if (lspActionOffsetNotifier.value != null) {
        lspActionOffsetNotifier.value = Offset(
          lspActionOffsetNotifier.value!.dx,
          _getCaretInfo().offset.dy - vscrollController.offset,
        );
      }

      if (hoverNotifier.value != null) {
        final lineChar = hoverNotifier.value!.$2;
        final line = lineChar['line']!;
        final hasActiveFolds = _foldRanges.values.any(
          (f) => f != null && f.isFolded,
        );
        final hoveredY = _getLineYOffset(line, hasActiveFolds);
        final screenY =
            hoveredY + (innerPadding?.top ?? 0) - vscrollController.offset;

        hoverNotifier.value = (
          Offset(hoverNotifier.value!.$1.dx, screenY),
          hoverNotifier.value!.$2,
        );
      }

      markNeedsPaint();
    });

    hscrollController.addListener(() {
      if (suggestionNotifier.value != null && offsetNotifier.value.dx >= 0) {
        offsetNotifier.value = Offset(
          _getCaretInfo().offset.dx - _effectiveHScroll,
          offsetNotifier.value.dy,
        );
      }

      if (lspActionOffsetNotifier.value != null) {
        lspActionOffsetNotifier.value = Offset(
          _getCaretInfo().offset.dx - _effectiveHScroll,
          lspActionOffsetNotifier.value!.dy,
        );
      }

      if (hoverNotifier.value != null) {
        final lineChar = hoverNotifier.value!.$2;
        final line = lineChar['line']!;
        final char = lineChar['character']!;
        final lineText = controller.getLineText(line);
        final para =
            _paragraphCache.containsKey(line) &&
                _lineTextCache[line] == lineText
            ? _paragraphCache[line]!
            : _buildParagraph(lineText, width: lineWrap ? _wrapWidth : null);

        double hoveredX = 0.0;
        if (char > 0 && char <= lineText.length) {
          final boxes = para.getBoxesForRange(0, char);
          if (boxes.isNotEmpty) {
            hoveredX = boxes.last.right;
          }
        }

        final screenX = isRTL
            ? size.width -
                  _gutterWidth -
                  (innerPadding?.right ?? 0) -
                  hoveredX +
                  (lineWrap ? 0 : _effectiveHScroll)
            : hoveredX +
                  _gutterWidth +
                  (innerPadding?.left ?? 0) -
                  (lineWrap ? 0 : _effectiveHScroll);

        hoverNotifier.value = (
          Offset(screenX, hoverNotifier.value!.$1.dy),
          hoverNotifier.value!.$2,
        );
      }

      markNeedsPaint();
    });

    caretBlinkController.addListener(markNeedsPaint);
    controller.addListener(_onControllerChange);

    _lineHighlightAnimation = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: lineHighlightController, curve: Curves.easeOut),
    )..addListener(markNeedsPaint);

    if (enableFolding) {
      controller.setFoldCallbacks(
        toggleFold: _toggleFoldAtLine,
        foldAll: _foldAllRanges,
        unfoldAll: _unfoldAllRanges,
      );
    }

    controller.setScrollCallback(_scrollToLine);

    hoverNotifier.addListener(() {
      if (hoverNotifier.value == null) {
        _hoverTimer?.cancel();
      }
    });

    aiNotifier.addListener(() {
      final previousAiResponse = _aiResponse;
      _aiResponse = aiNotifier.value;
      aiOffsetNotifier.value = _getCaretInfo().offset;

      if (_aiResponse != null && _aiResponse!.isNotEmpty) {
        final aiLines = _aiResponse!.split('\n');
        _ghostTextAnchorLine = controller.getLineAtOffset(
          controller.selection.extentOffset.clamp(0, controller.length),
        );
        _ghostTextLineCount = aiLines.length - 1;
      } else if (_aiResponse == null && previousAiResponse != null) {
        _ghostTextAnchorLine = null;
        _ghostTextLineCount = 0;
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
  TextStyle? get ghostTextStyle => _ghostTextStyle;
  set ghostTextStyle(TextStyle? value) {
    if (_ghostTextStyle == value) return;
    _ghostTextStyle = value;
    markNeedsPaint();
  }

  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    final fontSize = _textStyle?.fontSize ?? 14.0;
    final fontFamily = _textStyle?.fontFamily;
    final lineHeightMultiplier = _textStyle?.height ?? 1.2;
    _paragraphStyle = ui.ParagraphStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: lineHeightMultiplier,
      textDirection: _textDirection,
      textAlign: ui.TextAlign.start,
    );
    _paragraphCache.clear();
    _caretInfoCache.clear();
    markNeedsLayout();
    markNeedsPaint();
  }

  bool get isRTL => _textDirection == TextDirection.rtl;

  double get _effectiveHScroll {
    if (!isRTL || lineWrap) return hscrollController.offset;
    if (!hscrollController.hasClients) return 0;
    return -hscrollController.offset;
  }

  CodeSelectionStyle get selectionStyle => _selectionStyle;

  set editorTheme(Map<String, TextStyle> theme) {
    if (identical(theme, _editorTheme)) return;
    _editorTheme = theme;
    try {
      _syntaxHighlighter.dispose();
    } catch (e) {
      //
    }
    _syntaxHighlighter = SyntaxHighlighter(
      language: language,
      editorTheme: theme,
      baseTextStyle: textStyle,
    );
    _paragraphCache.clear();
    _bracketCache.clear();
    markNeedsLayout();
    markNeedsPaint();
  }

  set language(Mode lang) {
    if (identical(lang, _language)) return;
    _language = lang;
    try {
      _syntaxHighlighter.dispose();
    } catch (_) {}
    _syntaxHighlighter = SyntaxHighlighter(
      language: lang,
      editorTheme: editorTheme,
      baseTextStyle: textStyle,
    );
    _paragraphCache.clear();
    _bracketCache.clear();
    markNeedsLayout();
    markNeedsPaint();
  }

  set textStyle(TextStyle? style) {
    if (identical(style, _textStyle)) return;
    _textStyle = style;

    final fontSize = style?.fontSize ?? 14.0;
    final lineHeightMultiplier = style?.height ?? 1.2;

    _lineHeight = fontSize * lineHeightMultiplier;

    try {
      _syntaxHighlighter.dispose();
    } catch (_) {}
    _syntaxHighlighter = SyntaxHighlighter(
      language: language,
      editorTheme: editorTheme,
      baseTextStyle: style,
    );

    _paragraphCache.clear();
    _lineWidthCache.clear();
    _lineTextCache.clear();
    _lineHeightCache.clear();
    _bracketCache.clear();
    _indentGuideCache.clear();
    _indentEndLineCache.clear();
    _diagnosticPathCache.clear();
    _searchHighlightCache.clear();
    _lineOffsetCache.clear();
    _caretInfoCache.clear();
    _lineIndentCache.clear();

    markNeedsLayout();
    markNeedsPaint();
  }

  set innerPadding(EdgeInsets? padding) {
    if (identical(padding, _innerPadding)) return;
    _innerPadding = padding;
    _rightPaddingWidth = padding?.right ?? 0;
    _bottomPaddingHeight = padding?.bottom ?? 0;
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
    _bracketCache.clear();
    _indentGuideCache.clear();
    _indentEndLineCache.clear();
    _diagnosticPathCache.clear();
    _searchHighlightCache.clear();
    _lineOffsetCache.clear();
    _caretInfoCache.clear();
    _lineIndentCache.clear();
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
    final caretX = isRTL
        ? size.width -
              _gutterWidth -
              (innerPadding?.right ?? 0) -
              caretInfo.offset.dx
        : caretInfo.offset.dx + _gutterWidth + (innerPadding?.left ?? 0);
    final caretY = caretInfo.offset.dy + (innerPadding?.top ?? 0);
    final caretHeight = caretInfo.height;
    final vScrollOffset = vscrollController.offset;
    final hScrollOffset = _effectiveHScroll;
    final viewportHeight =
        vscrollController.position.viewportDimension - _bottomPaddingHeight;
    final viewportWidth =
        hscrollController.position.viewportDimension - _rightPaddingWidth;
    final relX = isRTL
        ? (viewportWidth - caretX + hScrollOffset).clamp(0.0, viewportWidth)
        : (caretX - hScrollOffset).clamp(0.0, viewportWidth);
    final relY = (caretY - vScrollOffset).clamp(0.0, viewportHeight);

    offsetNotifier.value = Offset(relX, relY);

    if (caretY > 0 && caretY <= vScrollOffset + (innerPadding?.top ?? 0)) {
      final targetOffset = caretY - (innerPadding?.top ?? 0);
      vscrollController.jumpTo(
        targetOffset.clamp(0, vscrollController.position.maxScrollExtent),
      );
    } else if (caretY + caretHeight >= vScrollOffset + viewportHeight) {
      final targetOffset = caretY + caretHeight - viewportHeight;
      vscrollController.jumpTo(
        targetOffset.clamp(0, vscrollController.position.maxScrollExtent),
      );
    }

    if (isRTL) {
      final maxScroll = hscrollController.position.maxScrollExtent;
      final effectiveScroll = _effectiveHScroll;

      if (caretX > effectiveScroll + viewportWidth - _gutterWidth) {
        final targetEffective = caretX - viewportWidth + _gutterWidth;
        final rawOffset = -targetEffective;
        hscrollController.jumpTo(rawOffset.clamp(0, maxScroll));
      } else if (caretX - 1.5 < effectiveScroll) {
        final targetEffective = caretX - 1.5;
        final rawOffset = -targetEffective;
        hscrollController.jumpTo(rawOffset.clamp(0, maxScroll));
      }
    } else {
      if (caretX < hScrollOffset + (innerPadding?.left ?? 0) + _gutterWidth) {
        final targetOffset = caretX - (innerPadding?.left ?? 0) - _gutterWidth;
        hscrollController.jumpTo(
          targetOffset.clamp(0, hscrollController.position.maxScrollExtent),
        );
      } else if (caretX + 1.5 > hScrollOffset + viewportWidth) {
        final targetOffset = caretX + 1.5 - viewportWidth;
        hscrollController.jumpTo(
          targetOffset.clamp(0, hscrollController.position.maxScrollExtent),
        );
      }
    }
  }

  void _deferLayout() {
    _layoutDebounceTimer?.cancel();
    _isDeferringLayout = true;

    if (_hasCachedHeight) {
      final lineDelta = _cachedLineCount - _previousLineCount;
      _cachedTotalHeight += lineDelta * _lineHeight;
    }
    _previousLineCount = _cachedLineCount;

    if (!_isFoldToggleInProgress) {
      _ensureCaretVisible();
    }
    markNeedsPaint();

    _layoutDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      _isDeferringLayout = false;
      markNeedsLayout();
    });
  }

  void _onControllerChange() {
    if (controller.lspFoldRanges != _lastLspFoldRanges) {
      _lastLspFoldRanges = controller.lspFoldRanges;

      if (controller.lspFoldRanges != null) {
        final newLspRanges = controller.lspFoldRanges!;
        final preservedFoldRanges = <int, FoldRange>{};

        for (final entry in newLspRanges.entries) {
          final lineIndex = entry.key;
          final newFold = entry.value;

          FoldRange? existingFold = _foldRanges[lineIndex];

          if (existingFold != null) {
            newFold.isFolded = existingFold.isFolded;
            newFold.originallyFoldedChildren =
                existingFold.originallyFoldedChildren;
          } else {
            for (
              int offset = 1;
              offset <= 3 && existingFold == null;
              offset++
            ) {
              existingFold =
                  _foldRanges[lineIndex - offset] ??
                  _foldRanges[lineIndex + offset];
              if (existingFold != null) {
                final oldRange =
                    existingFold.endIndex - existingFold.startIndex;
                final newRange = newFold.endIndex - newFold.startIndex;
                final diff = (oldRange - newRange).abs();
                if (diff <= (oldRange * 0.2)) {
                  newFold.isFolded = existingFold.isFolded;
                  newFold.originallyFoldedChildren =
                      existingFold.originallyFoldedChildren;
                } else {
                  existingFold = null;
                }
              }
            }
          }

          preservedFoldRanges[lineIndex] = newFold;
        }

        _foldRanges.clear();
        _foldRanges.addAll(preservedFoldRanges);

        controller.foldings = {
          for (var f in _foldRanges.values.where(
            (f) => f != null && f.isFolded,
          ))
            f!.startIndex: f,
        };
      } else if (!controller.lspFoldRangesWereAdjusted) {
        _foldRangesNeedsClear = true;
      }
    }

    if (controller.searchHighlightsChanged) {
      controller.searchHighlightsChanged = false;
      markNeedsPaint();
      return;
    }

    if (controller.inlayHintsChanged) {
      controller.inlayHintsChanged = false;
      markNeedsPaint();
      return;
    }

    if (controller.documentColorsChanged) {
      controller.documentColorsChanged = false;
      _caretInfoCache.clear();
      markNeedsPaint();
      return;
    }

    if (controller.documentHighlightsChanged) {
      controller.documentHighlightsChanged = false;
      markNeedsPaint();
      return;
    }

    if (controller.decorationsChanged) {
      controller.decorationsChanged = false;
      final ghost = controller.ghostText;
      if (ghost != null && ghost.text.isNotEmpty) {
        _ghostTextAnchorLine = ghost.line;
        final ghostLines = ghost.text.split('\n');
        _ghostTextLineCount = ghostLines.length - 1;
      } else if (_aiResponse == null) {
        _ghostTextAnchorLine = null;
        _ghostTextLineCount = 0;
      }
      markNeedsLayout();
      markNeedsPaint();
      return;
    }

    if (controller.selectionOnly) {
      controller.selectionOnly = false;
      if (!_isFoldToggleInProgress) {
        _ensureCaretVisible();
      }

      if (isMobile && controller.selection.isCollapsed) {
        _showBubble = true;
      }

      if (controller.selection.isCollapsed && controller.lspConfig != null) {
        final offset = controller.selection.baseOffset;
        if (_isOffsetOverWord(offset)) {
          final lineChar = _offsetToLineChar(offset);
          controller.scheduleDocumentHighlightsRefresh(
            lineChar['line']!,
            lineChar['character']!,
          );
        } else {
          controller.clearDocumentHighlights();
        }
      }

      markNeedsPaint();
      return;
    }

    if (controller.bufferNeedsRepaint) {
      controller.bufferNeedsRepaint = false;
      if (!_isFoldToggleInProgress) {
        _ensureCaretVisible();
      }
      markNeedsPaint();
      return;
    }

    if (_showBubble && isMobile) {
      _showBubble = false;
    }

    final newText = controller.text;
    final previousText = _lastProcessedText ?? newText;

    final dirtyRange = controller.dirtyRegion;
    if (dirtyRange != null) {
      final safeEnd = dirtyRange.end.clamp(dirtyRange.start, newText.length);
      final insertedText = newText.substring(dirtyRange.start, safeEnd);
      final delta = newText.length - previousText.length;
      final removedLength = max(insertedText.length - delta, 0);
      final oldEnd = dirtyRange.start + removedLength;

      _syntaxHighlighter.applyDocumentEdit(
        dirtyRange.start,
        oldEnd,
        insertedText,
        newText,
      );

      _paragraphCache.clear();
      _bracketCache.clear();
      _lineTextCache.clear();
      _indentGuideCache.clear();
      _indentEndLineCache.clear();
      _diagnosticPathCache.clear();
      _searchHighlightCache.clear();
      _lineOffsetCache.clear();
      _caretInfoCache.clear();
      _lineIndentCache.clear();
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
      final lineDelta = newLineCount - _cachedLineCount;
      final insertionLine =
          affectedLine ??
          controller.getLineAtOffset(
            controller.selection.extentOffset.clamp(0, controller.length),
          );

      _cachedLineCount = newLineCount;

      final startInvalidation = insertionLine > 0 ? insertionLine - 1 : 0;
      _lineTextCache.removeWhere((key, _) => key >= startInvalidation);
      _lineWidthCache.removeWhere((key, _) => key >= startInvalidation);
      _paragraphCache.removeWhere((key, _) => key >= startInvalidation);
      _lineHeightCache.removeWhere((key, _) => key >= startInvalidation);
      _syntaxHighlighter.invalidateLines(
        Set.from(
          List.generate(
            newLineCount - startInvalidation,
            (i) => startInvalidation + i,
          ),
        ),
      );

      if (enableGutter && gutterStyle.gutterWidth == null) {
        final fontSize = textStyle?.fontSize ?? 14.0;
        final digits = newLineCount.toString().length;
        final digitWidth = digits * _gutterPadding * 0.6;
        final foldIconSpace = enableFolding ? fontSize + 4 : 0;
        _gutterWidth = digitWidth + foldIconSpace + _gutterPadding;
      }

      if (enableFolding) {
        final editLine = insertionLine;

        final adjustedFoldRanges = <int, FoldRange?>{};
        final adjustedControllerFoldings = <int, FoldRange?>{};

        for (final entry in _foldRanges.entries) {
          final oldStartIndex = entry.key;
          final fold = entry.value;
          if (fold == null) continue;

          if (fold.endIndex < editLine) {
            adjustedFoldRanges[oldStartIndex] = fold;
            if (fold.isFolded) {
              adjustedControllerFoldings[oldStartIndex] = fold;
            }
          } else if (fold.startIndex <= editLine && fold.endIndex >= editLine) {
            final newEndIndex = fold.endIndex + lineDelta;
            if (newEndIndex >= oldStartIndex) {
              final newFold = FoldRange(oldStartIndex, newEndIndex);
              newFold.isFolded = fold.isFolded;
              newFold.originallyFoldedChildren = fold.originallyFoldedChildren;
              adjustedFoldRanges[oldStartIndex] = newFold;
              if (newFold.isFolded) {
                adjustedControllerFoldings[oldStartIndex] = newFold;
              }
            }
          } else if (fold.startIndex > editLine) {
            final newStartIndex = fold.startIndex + lineDelta;
            final newEndIndex = fold.endIndex + lineDelta;
            if (newStartIndex >= 0 && newEndIndex >= newStartIndex) {
              final newFold = FoldRange(newStartIndex, newEndIndex);
              newFold.isFolded = fold.isFolded;
              newFold.originallyFoldedChildren = fold.originallyFoldedChildren;
              adjustedFoldRanges[newStartIndex] = newFold;
              if (newFold.isFolded) {
                adjustedControllerFoldings[newStartIndex] = newFold;
              }
            }
          }
        }

        _foldRanges.clear();
        _foldRanges.addAll(adjustedFoldRanges);
        _foldRangesNeedsClear = false;
        controller.foldings = adjustedControllerFoldings;
        controller.adjustLspFoldRangesForLineChange(editLine, lineDelta);
      }

      _deferLayout();
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

    final oldText = previousText;
    final cursorPosition = controller.selection.extentOffset.clamp(
      0,
      controller.length,
    );
    final textBeforeCursor = newText.substring(0, cursorPosition);

    if (_lastProcessedText == newText &&
        _aiResponse != null &&
        _aiResponse!.isNotEmpty &&
        _lastSelectionForAi != controller.selection) {
      aiNotifier.value = null;
      aiOffsetNotifier.value = null;
      _ghostTextAnchorLine = null;
      _ghostTextLineCount = 0;
    }

    final ghost = controller.ghostText;
    if (_lastProcessedText == newText &&
        ghost != null &&
        !ghost.shouldPersist &&
        _lastSelectionForAi != controller.selection) {
      controller.clearGhostText();
    }
    _lastSelectionForAi = controller.selection;

    if (_aiResponse != null && _aiResponse!.isNotEmpty) {
      final textLengthDiff = newText.length - oldText.length;

      if (textLengthDiff > 0 && cursorPosition >= textLengthDiff) {
        final newlyTypedChars = textBeforeCursor.substring(
          cursorPosition - textLengthDiff,
          cursorPosition,
        );

        if (_aiResponse!.startsWith(newlyTypedChars)) {
          _aiResponse = _aiResponse!.substring(newlyTypedChars.length);
          if (_aiResponse!.isEmpty) {
            aiNotifier.value = null;
            aiOffsetNotifier.value = null;
            _ghostTextAnchorLine = null;
            _ghostTextLineCount = 0;
          } else {
            aiNotifier.value = _aiResponse;
            final aiLines = _aiResponse!.split('\n');
            _ghostTextLineCount = aiLines.length - 1;
          }
        } else {
          _aiResponse = null;
          aiNotifier.value = null;
          aiOffsetNotifier.value = null;
          _ghostTextAnchorLine = null;
          _ghostTextLineCount = 0;
        }
      } else if (textLengthDiff < 0) {
        _aiResponse = null;
        aiNotifier.value = null;
        aiOffsetNotifier.value = null;
        _ghostTextAnchorLine = null;
        _ghostTextLineCount = 0;
      }
    }

    final ctrlGhost = controller.ghostText;
    if (ctrlGhost != null && !ctrlGhost.shouldPersist) {
      final textLengthDiff = newText.length - oldText.length;

      if (textLengthDiff > 0 && cursorPosition >= textLengthDiff) {
        final newlyTypedChars = textBeforeCursor.substring(
          cursorPosition - textLengthDiff,
          cursorPosition,
        );

        if (ctrlGhost.text.startsWith(newlyTypedChars)) {
          final remainingText = ctrlGhost.text.substring(
            newlyTypedChars.length,
          );
          if (remainingText.isEmpty) {
            controller.clearGhostText();
          } else {
            controller.setGhostText(
              GhostText(
                line: ctrlGhost.line,
                column: ctrlGhost.column + newlyTypedChars.length,
                text: remainingText,
                style: ctrlGhost.style,
                shouldPersist: false,
              ),
            );
          }
        } else {
          controller.clearGhostText();
        }
      } else if (textLengthDiff < 0) {
        controller.clearGhostText();
      }
    }

    if (focusNode.hasFocus &&
        !_isFoldToggleInProgress &&
        _lastProcessedText != newText) {
      _ensureCaretVisible();
    }

    if (_lastProcessedText == newText) return;
    _lastProcessedText = newText;
  }

  FoldRange? _computeFoldRangeForLine(int lineIndex) {
    const folds = {'{': '}', '[': ']', '(': ')'};
    if (!enableFolding) return null;

    final line = controller.getLineText(lineIndex);

    if (folds.keys.any((k) => line.contains(k))) {
      final List<String> stack = [];

      final checkLine = controller.getLineText(lineIndex);
      for (int c = 0; c < checkLine.length; c++) {
        final ch = checkLine[c];
        if (folds.containsKey(ch)) {
          stack.add(ch);
        } else if (stack.isNotEmpty && ch == folds[stack.last]) {
          stack.removeLast();
        }
      }

      if (stack.isEmpty) return null;

      for (int i = lineIndex + 1; i < controller.lineCount; i++) {
        final checkLine = controller.getLineText(i);
        for (int c = 0; c < checkLine.length; c++) {
          final ch = checkLine[c];
          if (folds.containsKey(ch)) {
            stack.add(ch);
          } else if (stack.isNotEmpty && ch == folds[stack.last]) {
            stack.removeLast();
            if (stack.isEmpty) {
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

    final openingTagName = _extractOpeningTagName(line);
    if (openingTagName != null) {
      final matchLine = _findMatchingClosingTagLine(openingTagName, lineIndex);
      if (matchLine != null && matchLine > lineIndex) {
        return FoldRange(lineIndex, matchLine);
      }
    }

    return null;
  }

  FoldRange? _getOrComputeFoldRange(int lineIndex) {
    if (_foldRangesNeedsClear) {
      _foldRanges.clear();
      _caretInfoCache.clear();
      _cachedCaretOffset = -1;
      _foldRangesNeedsClear = false;
    }

    if (_foldRanges.containsKey(lineIndex)) {
      final cached = _foldRanges[lineIndex];
      return cached;
    }

    final lspFoldRanges = controller.lspFoldRanges;
    final fold = (lspFoldRanges != null && lspFoldRanges.containsKey(lineIndex))
        ? lspFoldRanges[lineIndex]
        : _computeFoldRangeForLine(lineIndex);

    _foldRanges[lineIndex] = fold;
    return fold;
  }

  void _toggleFold(FoldRange fold) {
    try {
      _isFoldToggleInProgress = true;
      if (fold.isFolded) {
        _unfoldWithChildren(fold);
      } else {
        _foldWithChildren(fold);
      }

      controller.foldings = {
        for (var f in _foldRanges.values.where((f) => f != null))
          f!.startIndex: f,
      };
      _caretInfoCache.clear();
      _cachedCaretOffset = -1;
      _paragraphCache.clear();
      _lineTextCache.clear();
      markNeedsLayout();
      markNeedsPaint();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isFoldToggleInProgress = false;
      });
    } catch (e) {
      debugPrint('Error toggling fold: $e');
      _isFoldToggleInProgress = false;
    }
  }

  void _toggleFoldAtLine(int lineNumber) {
    if (!enableFolding) return;
    if (lineNumber < 0 || lineNumber >= controller.lineCount) return;

    final foldRange = _getFoldRangeAtLine(lineNumber);
    if (foldRange != null) {
      _toggleFold(foldRange);
    }
  }

  void _foldAllRanges() {
    if (!enableFolding) return;
    _isFoldToggleInProgress = true;

    for (int i = 0; i < controller.lineCount; i++) {
      _getOrComputeFoldRange(i);
    }

    for (final fold in _foldRanges.values.where((f) => f != null)) {
      if (!fold!.isFolded) {
        final isNested = _foldRanges.values.any(
          (other) =>
              other != fold &&
              other!.startIndex < fold.startIndex &&
              other.endIndex >= fold.endIndex,
        );
        if (!isNested) {
          _foldWithChildren(fold);
        }
      }
    }

    controller.foldings = {
      for (var f in _foldRanges.values.where((f) => f != null))
        f!.startIndex: f,
    };
    markNeedsLayout();
    markNeedsPaint();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isFoldToggleInProgress = false;
    });
  }

  void _unfoldAllRanges() {
    if (!enableFolding) return;
    _isFoldToggleInProgress = true;

    for (final fold in _foldRanges.values.where((f) => f != null)) {
      if (fold!.isFolded) {
        fold.isFolded = false;
        fold.clearOriginallyFoldedChildren();
      }
    }

    controller.foldings = {
      for (var f in _foldRanges.values.where((f) => f != null))
        f!.startIndex: f,
    };
    markNeedsLayout();
    markNeedsPaint();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isFoldToggleInProgress = false;
    });
  }

  void _scrollToLine(int line) {
    if (line < 0 || line >= controller.lineCount) return;

    for (final fold in _foldRanges.values.where((f) => f != null)) {
      if (fold!.isFolded && line > fold.startIndex && line <= fold.endIndex) {
        _unfoldWithChildren(fold);
        controller.foldings = {
          for (var f in _foldRanges.values.where((f) => f != null))
            f!.startIndex: f,
        };
        markNeedsLayout();
        break;
      }
    }

    final hasActiveFolds = _foldRanges.values.any(
      (f) => f != null && f.isFolded,
    );
    final targetY = _getLineYOffset(line, hasActiveFolds);
    final viewportHeight = vscrollController.position.viewportDimension;
    final maxScroll = vscrollController.position.maxScrollExtent;
    double scrollTarget = targetY - (viewportHeight / 2) + (_lineHeight / 2);

    scrollTarget = scrollTarget.clamp(0.0, maxScroll);

    vscrollController
        .animateTo(
          scrollTarget,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        )
        .then((_) {
          _highlightedLine = line;
          lineHighlightController.forward(from: 0.0);
        });
  }

  void _foldWithChildren(FoldRange parentFold) {
    parentFold.clearOriginallyFoldedChildren();

    for (final childFold in _foldRanges.values.where((f) => f != null)) {
      if (childFold!.isFolded &&
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
    return _foldRanges.values.any(
      (fold) =>
          fold != null &&
          fold.isFolded &&
          lineIndex > fold.startIndex &&
          lineIndex <= fold.endIndex,
    );
  }

  int? _findMatchingBracket(String text, int pos) {
    if (_bracketCache.containsKey(pos)) {
      return _bracketCache[pos];
    }

    const Map<String, String> pairs = {
      '(': ')',
      '{': '}',
      '[': ']',
      ')': '(',
      '}': '{',
      ']': '[',
    };
    const String openers = '({[';

    if (pos < 0 || pos >= text.length) {
      _bracketCache[pos] = null;
      return null;
    }

    final char = text[pos];
    if (!pairs.containsKey(char)) {
      _bracketCache[pos] = null;
      return null;
    }

    final match = pairs[char]!;
    final isForward = openers.contains(char);

    int depth = 0;
    if (isForward) {
      for (int i = pos + 1; i < text.length; i++) {
        if (text[i] == char) depth++;
        if (text[i] == match) {
          if (depth == 0) {
            _bracketCache[pos] = i;
            return i;
          }
          depth--;
        }
      }
    } else {
      for (int i = pos - 1; i >= 0; i--) {
        if (text[i] == char) depth++;
        if (text[i] == match) {
          if (depth == 0) {
            _bracketCache[pos] = i;
            return i;
          }
          depth--;
        }
      }
    }
    _bracketCache[pos] = null;
    return null;
  }

  String? _extractOpeningTagName(String lineText) {
    final trimmed = lineText.trimRight();
    final openTagMatch = RegExp(r'<(\w+)(?:\s[^>]*)?>$').firstMatch(trimmed);
    if (openTagMatch != null) {
      final tagName = openTagMatch.group(1);
      if (!trimmed.endsWith('/>') && !trimmed.endsWith('-->')) {
        return tagName;
      }
    }
    return null;
  }

  int? _findMatchingClosingTagLine(String tagName, int startLine) {
    final closeTagPattern = RegExp(r'</' + RegExp.escape(tagName) + r'\s*>');
    int depth = 1;

    for (int i = startLine + 1; i < controller.lineCount; i++) {
      String lineText;
      if (_lineTextCache.containsKey(i)) {
        lineText = _lineTextCache[i]!;
      } else {
        lineText = controller.getLineText(i);
        _lineTextCache[i] = lineText;
      }

      final openMatches = RegExp(
        r'<' + RegExp.escape(tagName) + r'(?:\s[^>]*)?>',
      ).allMatches(lineText);
      for (final match in openMatches) {
        final fullMatch = match.group(0)!;
        if (!fullMatch.endsWith('/>')) {
          depth++;
        }
      }

      final closeMatches = closeTagPattern.allMatches(lineText);
      for (final _ in closeMatches) {
        depth--;
        if (depth == 0) {
          return i;
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

    final hasActiveFolds = _foldRanges.values.any(
      (f) => f != null && f.isFolded,
    );

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
    final cursorOffset = controller.selection.extentOffset;

    final lineCount = controller.lineCount;
    if (lineCount == 0) {
      final result = (
        lineIndex: 0,
        columnIndex: 0,
        offset: Offset.zero,
        height: _lineHeight,
      );
      _caretInfoCache[cursorOffset] = result;
      return result;
    }

    final hasActiveFolds = _foldRanges.values.any(
      (f) => f != null && f.isFolded,
    );

    if (controller.isBufferActive) {
      final lineIndex = controller.bufferLineIndex!;
      final columnIndex = controller.bufferCursorColumn;
      final lineY = _getLineYOffset(lineIndex, hasActiveFolds);
      final lineText = controller.bufferLineText ?? '';

      final contentWidth =
          size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
      final paragraphWidth = lineWrap
          ? _wrapWidth
          : (isRTL ? max(contentWidth * 3, 10000.0) : null);

      final para = _buildHighlightedParagraph(
        lineIndex,
        lineText,
        width: paragraphWidth,
      );
      final clampedCol = columnIndex.clamp(0, lineText.length);

      double caretX = 0.0;
      double caretYInLine = 0.0;

      if (isRTL) {
        final paragraphOffset = lineWrap
            ? 0.0
            : (contentWidth - (paragraphWidth ?? 0));

        if (lineText.isEmpty) {
          caretX = contentWidth;
        } else if (clampedCol == 0) {
          final boxes = para.getBoxesForRange(0, 1);
          if (boxes.isNotEmpty) {
            caretX = boxes.first.right + paragraphOffset;
            caretYInLine = boxes.first.top;
          } else {
            caretX = contentWidth;
          }
        } else if (clampedCol >= lineText.length) {
          final boxes = para.getBoxesForRange(
            lineText.length - 1,
            lineText.length,
          );
          if (boxes.isNotEmpty) {
            caretX = boxes.first.left + paragraphOffset;
            caretYInLine = boxes.first.top;
          } else {
            caretX = paragraphOffset;
          }
        } else {
          final boxes = para.getBoxesForRange(clampedCol - 1, clampedCol);
          if (boxes.isNotEmpty) {
            caretX = boxes.first.left + paragraphOffset;
            caretYInLine = boxes.first.top;
          } else {
            caretX = contentWidth;
          }
        }
      } else {
        if (lineText.isEmpty) {
          caretX = 0;
        } else if (clampedCol > 0) {
          final boxes = para.getBoxesForRange(clampedCol - 1, clampedCol);
          if (boxes.isNotEmpty) {
            caretX = boxes.first.right;
            caretYInLine = boxes.first.top;
          }
        }
      }

      final ghostOffset = _getGhostTextVisualOffset(lineIndex);

      return (
        lineIndex: lineIndex,
        columnIndex: columnIndex,
        offset: Offset(caretX, lineY + caretYInLine + ghostOffset),
        height: _lineHeight,
      );
    }

    if (!isRTL && _caretInfoCache.containsKey(cursorOffset)) {
      return _caretInfoCache[cursorOffset]!;
    }

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
    final lineText = controller.getLineText(lineIndex);
    final contentWidth =
        size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
    final paragraphWidth = lineWrap
        ? _wrapWidth
        : (isRTL ? max(contentWidth * 3, 10000.0) : null);

    ui.Paragraph para;
    if (_paragraphCache.containsKey(lineIndex) &&
        _lineTextCache[lineIndex] == lineText &&
        !isRTL) {
      para = _paragraphCache[lineIndex]!;
    } else {
      para = _buildParagraph(lineText, width: paragraphWidth);
    }

    final clampedCol = columnIndex.clamp(0, lineText.length);
    double caretX = 0.0;
    double caretYInLine = 0.0;

    if (isRTL) {
      final paragraphOffset = lineWrap
          ? 0.0
          : (contentWidth - (paragraphWidth ?? 0));

      if (lineText.isEmpty) {
        caretX = contentWidth;
      } else if (clampedCol == 0) {
        final boxes = para.getBoxesForRange(0, 1);
        if (boxes.isNotEmpty) {
          caretX = boxes.first.right + paragraphOffset;
          caretYInLine = boxes.first.top;
        } else {
          caretX = contentWidth;
        }
      } else if (clampedCol >= lineText.length) {
        final boxes = para.getBoxesForRange(
          lineText.length - 1,
          lineText.length,
        );
        if (boxes.isNotEmpty) {
          caretX = boxes.first.left + paragraphOffset;
          caretYInLine = boxes.first.top;
        } else {
          caretX = paragraphOffset;
        }
      } else {
        final boxes = para.getBoxesForRange(clampedCol - 1, clampedCol);
        if (boxes.isNotEmpty) {
          caretX = boxes.first.left + paragraphOffset;
          caretYInLine = boxes.first.top;
        } else {
          caretX = contentWidth;
        }
      }
    } else {
      if (lineText.isEmpty) {
        caretX = 0;
      } else if (clampedCol > 0) {
        final boxes = para.getBoxesForRange(clampedCol - 1, clampedCol);
        if (boxes.isNotEmpty) {
          caretX = boxes.first.right;
          caretYInLine = boxes.first.top;
        }
      }
    }

    final colorBoxOffset = _getColorBoxOffsetForLine(lineIndex, clampedCol);
    caretX += colorBoxOffset;

    final ghostOffset = _getGhostTextVisualOffset(lineIndex);

    final result = (
      lineIndex: lineIndex,
      columnIndex: columnIndex,
      offset: Offset(caretX, lineY + caretYInLine + ghostOffset),
      height: _lineHeight,
    );
    _caretInfoCache[cursorOffset] = result;
    return result;
  }

  double _getColorBoxOffsetForLine(int line, int column) {
    final colors = controller.documentColors;
    if (colors.isEmpty) return 0;

    final fontSize = textStyle?.fontSize ?? 14.0;
    final colorBoxSize = fontSize * 0.85;
    final colorBoxSpacing = 4.0;
    final totalColorWidth = colorBoxSize + colorBoxSpacing;

    double offset = 0;
    for (final docColor in colors) {
      if (docColor.line == line && docColor.startColumn < column) {
        offset += totalColorWidth;
      }
    }
    return offset;
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

    final contentWidth =
        size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
    final paragraphWidth = lineWrap
        ? _wrapWidth
        : (isRTL ? max(contentWidth * 3, 10000.0) : null);

    ui.Paragraph para;
    if (_paragraphCache.containsKey(tappedLineIndex) && !isRTL) {
      para = _paragraphCache[tappedLineIndex]!;
    } else {
      para = _buildHighlightedParagraph(
        tappedLineIndex,
        lineText,
        width: paragraphWidth,
      );
      if (!isRTL) {
        _paragraphCache[tappedLineIndex] = para;
      }
    }

    double localX = position.dx;

    if (isRTL && !lineWrap && paragraphWidth != null) {
      final contentWidth =
          size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
      final paragraphOffset = contentWidth - paragraphWidth;
      localX = localX - paragraphOffset;
    }

    final colors =
        controller.documentColors
            .where((c) => c.line == tappedLineIndex)
            .toList()
          ..sort((a, b) => a.startColumn.compareTo(b.startColumn));

    if (colors.isNotEmpty) {
      final fontSize = textStyle?.fontSize ?? 14.0;
      final colorBoxSize = fontSize * 0.85;
      final colorBoxSpacing = 4.0;
      final totalColorWidth = colorBoxSize + colorBoxSpacing;

      double totalAdjustment = 0;
      for (final docColor in colors) {
        final textX =
            para
                .getBoxesForRange(
                  0,
                  docColor.startColumn.clamp(0, lineText.length),
                )
                .lastOrNull
                ?.right ??
            0;

        final colorBoxStartX = textX + totalAdjustment;
        final colorBoxEndX = colorBoxStartX + totalColorWidth;

        if (localX > colorBoxEndX) {
          totalAdjustment += totalColorWidth;
        } else if (localX > colorBoxStartX && localX <= colorBoxEndX) {
          localX = textX + totalAdjustment;
          break;
        } else {
          break;
        }
      }
      localX -= totalAdjustment;
    }

    final hasActiveFolds = _foldRanges.values.any(
      (f) => f != null && f.isFolded,
    );
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
  void detach() {
    _resizeTimer?.cancel();
    _layoutDebounceTimer?.cancel();
    super.detach();
  }

  double get _ghostTextExtraHeight => _ghostTextLineCount * _lineHeight;

  double _getGhostTextVisualOffset(int lineIndex) {
    if (_ghostTextAnchorLine == null || _ghostTextLineCount <= 0) return 0;
    if (lineIndex <= _ghostTextAnchorLine!) return 0;
    return _ghostTextExtraHeight;
  }

  @override
  void performLayout() {
    final lineCount = controller.lineCount;

    if (lineCount != _cachedLineCount) {
      _lineWidthCache.removeWhere((key, _) => key >= lineCount);
      _lineTextCache.removeWhere((key, _) => key >= lineCount);
      _lineHeightCache.removeWhere((key, _) => key >= lineCount);
    }

    if (isRTL && !lineWrap) {
      final viewportWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.of(context).size.width;
      final newContentWidth =
          viewportWidth - _gutterWidth - (innerPadding?.horizontal ?? 0);
      if ((_cachedRtlContentWidth - newContentWidth).abs() > 1) {
        _cachedRtlContentWidth = newContentWidth;
        _paragraphCache.clear();
        _bracketCache.clear();
        _indentGuideCache.clear();
        _diagnosticPathCache.clear();
        _searchHighlightCache.clear();
        _lineOffsetCache.clear();
        _caretInfoCache.clear();
        _lineIndentCache.clear();
      }
    }

    if (_isDeferringLayout && _hasCachedHeight) {
      final contentHeight =
          _cachedTotalHeight + (innerPadding?.top ?? 0) + _ghostTextExtraHeight;
      final computedWidth = lineWrap
          ? (constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.of(context).size.width)
          : _longLineWidth + (innerPadding?.left ?? 0) + _gutterWidth;
      final minWidth = lineWrap ? 0.0 : MediaQuery.of(context).size.width;
      final contentWidth = max(computedWidth, minWidth);
      size = constraints.constrain(
        Size(
          contentWidth + (innerPadding?.right ?? 0),
          contentHeight + (innerPadding?.bottom ?? 0),
        ),
      );
      return;
    }

    final hasActiveFolds = _foldRanges.values.any(
      (f) => f != null && f.isFolded,
    );
    double visibleHeight = 0;
    double maxLineWidth = _longLineWidth;

    if (lineWrap) {
      final viewportWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.of(context).size.width;
      final newWrapWidth =
          viewportWidth - _gutterWidth - (innerPadding?.horizontal ?? 0);
      final clampedWrapWidth = newWrapWidth < 100 ? 100.0 : newWrapWidth;

      if ((_wrapWidth - clampedWrapWidth).abs() > 1) {
        _resizeTimer?.cancel();
        _resizeTimer = Timer(const Duration(milliseconds: 150), () {
          _wrapWidth = clampedWrapWidth;
          _paragraphCache.clear();
          _lineHeightCache.clear();
          _bracketCache.clear();
          _indentGuideCache.clear();
          _diagnosticPathCache.clear();
          _searchHighlightCache.clear();
          _lineOffsetCache.clear();
          _caretInfoCache.clear();
          _lineIndentCache.clear();
          markNeedsLayout();
        });
        if (_wrapWidth == double.infinity) {
          _wrapWidth = clampedWrapWidth;
        }
      }

      if (hasActiveFolds) {
        for (int i = 0; i < lineCount; i++) {
          if (_isLineFolded(i)) continue;
          visibleHeight += _getWrappedLineHeight(i);
        }
      } else {
        double cachedHeight = 0;
        int cachedCount = 0;
        for (final entry in _lineHeightCache.entries) {
          if (entry.key < lineCount) {
            cachedHeight += entry.value;
            cachedCount++;
          }
        }
        final uncachedCount = lineCount - cachedCount;
        final avgHeight = cachedCount > 0
            ? cachedHeight / cachedCount
            : _lineHeight;
        visibleHeight = cachedHeight + (uncachedCount * avgHeight);
      }
    } else {
      _wrapWidth = double.infinity;

      if (hasActiveFolds) {
        int visibleLines = 0;
        for (int i = 0; i < lineCount; i++) {
          if (!_isLineFolded(i)) visibleLines++;
        }
        visibleHeight = visibleLines * _lineHeight;
      } else {
        visibleHeight = lineCount * _lineHeight;
      }

      if (_longLineWidth == 0 && lineCount > 0) {
        final viewTop = vscrollController.hasClients
            ? vscrollController.offset
            : 0.0;
        final viewBottom =
            viewTop +
            (vscrollController.hasClients
                ? vscrollController.position.viewportDimension
                : MediaQuery.of(context).size.height);
        final firstVisible = (viewTop / _lineHeight).floor().clamp(
          0,
          lineCount - 1,
        );
        final lastVisible = (viewBottom / _lineHeight).ceil().clamp(
          0,
          lineCount - 1,
        );
        final buffer = 50;
        final start = (firstVisible - buffer).clamp(0, lineCount - 1);
        final end = (lastVisible + buffer).clamp(0, lineCount - 1);

        for (int i = start; i <= end; i++) {
          final width = _getLineWidth(i);
          if (width > maxLineWidth) {
            maxLineWidth = width;
          }
        }
      }
    }

    _longLineWidth = maxLineWidth;
    _cachedTotalHeight = visibleHeight;
    _hasCachedHeight = true;
    _previousLineCount = lineCount;

    final contentHeight =
        visibleHeight + (innerPadding?.top ?? 0) + _ghostTextExtraHeight;
    final computedWidth = lineWrap
        ? (constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.of(context).size.width)
        : maxLineWidth + (innerPadding?.left ?? 0) + _gutterWidth;

    final minWidth = lineWrap ? 0.0 : MediaQuery.of(context).size.width;
    final contentWidth = max(computedWidth, minWidth);

    size = constraints.constrain(
      Size(
        contentWidth + (innerPadding?.right ?? 0),
        contentHeight + (innerPadding?.bottom ?? 0),
      ),
    );
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
    final cacheKey = '${targetLine}_$hasActiveFolds';
    if (_lineOffsetCache.containsKey(cacheKey)) {
      return _lineOffsetCache[cacheKey]!;
    }

    double y;
    if (!lineWrap && !hasActiveFolds) {
      y = targetLine * _lineHeight;
    } else {
      y = 0;
      for (int i = 0; i < targetLine; i++) {
        if (hasActiveFolds && _isLineFolded(i)) continue;
        y += lineWrap ? _getWrappedLineHeight(i) : _lineHeight;
      }
    }
    _lineOffsetCache[cacheKey] = y;
    return y;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _checkDocumentVersionAndClearCache();

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

    final hasActiveFolds = _foldRanges.values.any(
      (f) => f != null && f.isFolded,
    );

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

    _drawSearchHighlights(
      canvas,
      offset,
      firstVisibleLine,
      lastVisibleLine,
      firstVisibleLineY,
      hasActiveFolds,
    );

    _drawLineDecorations(
      canvas,
      offset,
      firstVisibleLine,
      lastVisibleLine,
      firstVisibleLineY,
      hasActiveFolds,
    );

    _drawLineHighlight(
      canvas,
      offset,
      firstVisibleLine,
      lastVisibleLine,
      firstVisibleLineY,
      hasActiveFolds,
    );

    _drawFoldedLineHighlights(
      canvas,
      offset,
      firstVisibleLine,
      lastVisibleLine,
      firstVisibleLineY,
      hasActiveFolds,
    );

    if (controller.documentHighlights.isNotEmpty) {
      _drawDocumentHighlights(
        canvas,
        offset,
        firstVisibleLine,
        lastVisibleLine,
        firstVisibleLineY,
        hasActiveFolds,
      );
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
      double lineHeight = lineWrap ? _getWrappedLineHeight(i) : _lineHeight;
      final visualYOffset = _getGhostTextVisualOffset(i);

      ui.Paragraph paragraph;
      String lineText;

      final contentWidth =
          size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
      final paragraphWidth = lineWrap
          ? _wrapWidth
          : (isRTL ? max(contentWidth * 3, 10000.0) : null);

      if (bufferActive && i == bufferLineIndex && bufferLineText != null) {
        lineText = bufferLineText;
        paragraph = _buildHighlightedParagraph(
          i,
          bufferLineText,
          width: paragraphWidth,
        );
        if (isRTL && lineWrap) {
          lineHeight = paragraph.height;
        }
      } else {
        if (_lineTextCache.containsKey(i)) {
          lineText = _lineTextCache[i]!;
        } else {
          lineText = controller.getLineText(i);
          _lineTextCache[i] = lineText;
        }

        if (_paragraphCache.containsKey(i) && !isRTL) {
          paragraph = _paragraphCache[i]!;
        } else {
          paragraph = _buildHighlightedParagraph(
            i,
            lineText,
            width: paragraphWidth,
          );
          if (!isRTL) {
            _paragraphCache[i] = paragraph;
          }

          if (lineWrap) {
            _lineHeightCache[i] = paragraph.height;
            if (isRTL) {
              lineHeight = paragraph.height;
            }
          }
        }
      }

      final foldRange = _getFoldRangeAtLine(i);
      final isFoldStart = foldRange != null;

      final textX = isRTL
          ? (lineWrap
                ? (innerPadding?.left ?? 0)
                : (innerPadding?.left ?? 0) +
                      contentWidth -
                      (paragraphWidth ?? 0) -
                      _effectiveHScroll)
          : _gutterWidth +
                (innerPadding?.left ?? 0) -
                (lineWrap ? 0 : _effectiveHScroll);

      canvas.drawParagraph(
        paragraph,
        offset +
            Offset(
              textX,
              (innerPadding?.top ?? 0) +
                  contentTop +
                  visualYOffset -
                  vscrollController.offset,
            ),
      );

      if (isFoldStart && foldRange.isFolded) {
        final foldIndicator = _buildParagraph(' ...');
        final paraWidth = paragraph.longestLine;
        final foldX = isRTL
            ? (innerPadding?.left ?? 0) +
                  contentWidth -
                  paraWidth -
                  foldIndicator.longestLine -
                  (lineWrap ? 0 : _effectiveHScroll)
            : _gutterWidth +
                  (innerPadding?.left ?? 0) +
                  paraWidth -
                  (lineWrap ? 0 : _effectiveHScroll);
        canvas.drawParagraph(
          foldIndicator,
          offset +
              Offset(
                foldX,
                (innerPadding?.top ?? 0) +
                    contentTop +
                    visualYOffset -
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

    _colorBoxHitAreas.clear();
    if (controller.documentColors.isNotEmpty) {
      _drawDocumentColors(
        canvas,
        offset,
        firstVisibleLine,
        lastVisibleLine,
        firstVisibleLineY,
        hasActiveFolds,
      );
    }

    if (controller.inlayHintsVisible && controller.inlayHints.isNotEmpty) {
      _drawInlayHints(
        canvas,
        offset,
        firstVisibleLine,
        lastVisibleLine,
        firstVisibleLineY,
        hasActiveFolds,
      );
    }

    if (controller.ghostText != null) {
      _drawGhostText(
        canvas,
        offset,
        firstVisibleLine,
        lastVisibleLine,
        firstVisibleLineY,
        hasActiveFolds,
      );
    } else if (_aiResponse != null && _aiResponse!.isNotEmpty) {
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

    if (_rightPaddingWidth > 0) {
      canvas.drawRect(
        Rect.fromLTWH(
          offset.dx + size.width - _rightPaddingWidth,
          offset.dy,
          _rightPaddingWidth,
          size.height,
        ),
        Paint()..color = Colors.transparent,
      );
    }

    if (_bottomPaddingHeight > 0) {
      canvas.drawRect(
        Rect.fromLTWH(
          offset.dx,
          offset.dy + size.height - _bottomPaddingHeight,
          size.width,
          _bottomPaddingHeight,
        ),
        Paint()..color = Colors.transparent,
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

      final scroll = lineWrap ? 0.0 : _effectiveHScroll;
      final textX = isRTL
          ? (innerPadding?.left ?? 0) - scroll
          : _gutterWidth + (innerPadding?.left ?? 0) - scroll;
      final caretScreenX = offset.dx + textX + caretInfo.offset.dx;
      final caretScreenY =
          offset.dy +
          (innerPadding?.top ?? 0) +
          caretInfo.offset.dy -
          vscrollController.offset;

      canvas.drawRect(
        Rect.fromLTWH(caretScreenX, caretScreenY, 1.5, caretInfo.height),
        _caretPainter,
      );
    }

    if (isMobile) {
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

          final scroll = lineWrap ? 0.0 : _effectiveHScroll;
          final textX = isRTL
              ? (innerPadding?.left ?? 0) - scroll
              : _gutterWidth + (innerPadding?.left ?? 0) - scroll;
          final handleX = offset.dx + textX + caretInfo.offset.dx;
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
                height: handleSize * 1.3,
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
            final caretLineIndex = controller.getLineAtOffset(
              controller.selection.baseOffset,
            );
            final lineText =
                _lineTextCache[caretLineIndex] ??
                controller.getLineText(caretLineIndex);
            final lineStartOffset = controller.getLineStartOffset(
              caretLineIndex,
            );
            final caretInLine =
                controller.selection.baseOffset - lineStartOffset;

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

            final zoomBoxWidth = min(
              zoomParagraph.longestLine + 16,
              size.width * 0.6,
            );
            final zoomBoxHeight = zoomParagraph.height + 12;
            final zoomBoxX = (handleX - zoomBoxWidth / 2).clamp(
              0.0,
              size.width - zoomBoxWidth,
            );
            final zoomBoxY = handleY - zoomBoxHeight - 18;

            final rrect = RRect.fromRectAndRadius(
              Rect.fromLTWH(zoomBoxX, zoomBoxY, zoomBoxWidth, zoomBoxHeight),
              Radius.circular(12),
            );

            canvas.drawRRect(
              rrect,
              Paint()
                ..color = editorTheme['root']?.backgroundColor ?? Colors.black
                ..style = PaintingStyle.fill,
            );

            canvas.drawRRect(
              rrect,
              Paint()
                ..color = editorTheme['root']?.color ?? Colors.grey
                ..strokeWidth = 0.5
                ..style = PaintingStyle.stroke,
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
              bottomRight: Radius.circular(25),
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
              bottomRight: Radius.circular(25),
            ),
            handlePaint,
          );
        }

        if (_draggingStartHandle ||
            _draggingEndHandle ||
            (_selectionActive && _isDragging)) {
          final selection = controller.selection;
          final dragOffset = _draggingStartHandle
              ? selection.start
              : selection.end;
          final dragLine = controller.getLineAtOffset(dragOffset);
          final startLine = max(0, dragLine - 1);
          final endLine = min(controller.lineCount - 1, dragLine + 1);

          List<ui.Paragraph> zoomParagraphs;
          if (_cachedSelectionMagnifierParagraphs != null &&
              _cachedSelectionMagnifierStartLine == startLine &&
              _cachedSelectionMagnifierEndLine == endLine) {
            zoomParagraphs = _cachedSelectionMagnifierParagraphs!;
          } else {
            zoomParagraphs = [];
            final zoomFontSize = (textStyle?.fontSize ?? 14) * 1.4;
            final fontFamily = textStyle?.fontFamily;

            for (int line = startLine; line <= endLine; line++) {
              final lineText = controller.getLineText(line);
              final lineStartOffset = controller.getLineStartOffset(line);

              String displayText;
              if (line == dragLine) {
                final colInLine = dragOffset - lineStartOffset;
                final previewStart = max(0, colInLine - 15);
                final previewEnd = min(lineText.length, colInLine + 15);
                displayText = lineText.substring(previewStart, previewEnd);
              } else {
                displayText = lineText.length > 30
                    ? lineText.substring(0, 30)
                    : lineText;
              }

              if (displayText.isEmpty) displayText = ' ';

              final para = _syntaxHighlighter.buildHighlightedParagraph(
                line,
                displayText,
                _paragraphStyle,
                zoomFontSize,
                fontFamily,
              );
              zoomParagraphs.add(para);
            }
            _cachedSelectionMagnifierParagraphs = zoomParagraphs;
            _cachedSelectionMagnifierStartLine = startLine;
            _cachedSelectionMagnifierEndLine = endLine;
          }

          double maxWidth = 0;
          double totalHeight = 0;
          for (final para in zoomParagraphs) {
            maxWidth = max(maxWidth, para.longestLine);
            totalHeight += para.height;
          }

          final zoomBoxWidth = min(maxWidth + 24, size.width * 0.7);
          final zoomBoxHeight = totalHeight + 18;
          double handleCenterX;
          double handleTopY;
          Rect? activeHandleRect;

          if (_draggingStartHandle && _startHandleRect != null) {
            handleCenterX = _startHandleRect!.center.dx;
            handleTopY = _startHandleRect!.top;
            activeHandleRect = _startHandleRect;
          } else if (_draggingEndHandle && _endHandleRect != null) {
            handleCenterX = _endHandleRect!.center.dx;
            handleTopY = _endHandleRect!.top;
            activeHandleRect = _endHandleRect;
          } else {
            handleCenterX = _currentPosition.dx;
            handleTopY = _currentPosition.dy;
            activeHandleRect = null;
          }

          final fingerOffsetY = 60.0;
          final fingerOffsetX = _draggingStartHandle
              ? 30.0
              : (_draggingEndHandle ? -30.0 : 0.0);
          var zoomBoxX = (handleCenterX + fingerOffsetX - zoomBoxWidth / 2)
              .clamp(4.0, size.width - zoomBoxWidth - 4);
          var zoomBoxY = handleTopY - zoomBoxHeight - fingerOffsetY;
          final viewportTop = 0.0;
          final viewportBottom = size.height;

          if (zoomBoxY < viewportTop + 4) {
            final handleBottom = activeHandleRect?.bottom ?? (handleTopY + 40);
            zoomBoxY = handleBottom + fingerOffsetY;

            if (zoomBoxY + zoomBoxHeight > viewportBottom - 4) {
              zoomBoxY = viewportBottom - zoomBoxHeight - 4;
            }
          }

          zoomBoxY = zoomBoxY.clamp(
            viewportTop + 4,
            viewportBottom - zoomBoxHeight - 4,
          );

          final rrect = RRect.fromRectAndRadius(
            Rect.fromLTWH(zoomBoxX, zoomBoxY, zoomBoxWidth, zoomBoxHeight),
            Radius.circular(12),
          );

          canvas.drawRRect(
            rrect,
            Paint()
              ..color = editorTheme['root']?.backgroundColor ?? Colors.black
              ..style = PaintingStyle.fill,
          );

          canvas.drawRRect(
            rrect,
            Paint()
              ..color = editorTheme['root']?.color ?? Colors.grey
              ..strokeWidth = 0.5
              ..style = PaintingStyle.stroke,
          );

          canvas.save();
          canvas.clipRect(rrect.outerRect);

          double yOffset = zoomBoxY + 9;
          for (int i = 0; i < zoomParagraphs.length; i++) {
            final para = zoomParagraphs[i];
            final lineIndex = startLine + i;

            if (lineIndex == dragLine) {
              canvas.drawRect(
                Rect.fromLTWH(
                  zoomBoxX,
                  yOffset - 2,
                  zoomBoxWidth,
                  para.height + 4,
                ),
                Paint()
                  ..color = (selectionStyle.selectionColor).withValues(
                    alpha: 0.3,
                  )
                  ..style = PaintingStyle.fill,
              );
            }

            canvas.drawParagraph(para, Offset(zoomBoxX + 12, yOffset));
            yOffset += para.height;
          }

          canvas.restore();
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
    final gutterX = isRTL ? offset.dx + size.width - _gutterWidth : offset.dx;
    canvas.drawRect(
      Rect.fromLTWH(gutterX, offset.dy, _gutterWidth, viewportHeight),
      Paint()..color = gutterBgColor,
    );

    if (enableGutterDivider) {
      final dividerPaint = Paint()
        ..color = (editorTheme['root']?.color ?? Colors.grey).withAlpha(150)
        ..strokeWidth = 1;
      final dividerX = isRTL ? gutterX : gutterX + _gutterWidth - 1;
      canvas.drawLine(
        Offset(dividerX, offset.dy),
        Offset(dividerX, offset.dy + viewportHeight),
        dividerPaint,
      );
    }

    final baseLineNumberStyle = (() {
      if (gutterStyle.lineNumberStyle != null) {
        if (gutterStyle.lineNumberStyle!.fontSize == null) {
          return gutterStyle.lineNumberStyle!.copyWith(
            fontSize: gutterTextStyle?.fontSize,
          );
        }
        return gutterStyle.lineNumberStyle;
      } else {
        if (gutterTextStyle == null) {
          return editorTheme['root'];
        } else if (gutterTextStyle.color == null) {
          return gutterTextStyle.copyWith(color: editorTheme['root']?.color);
        } else {
          return gutterTextStyle;
        }
      }
    })();

    final hasActiveFolds = _foldRanges.values.any(
      (f) => f != null && f.isFolded,
    );
    final cursorOffset = controller.selection.extentOffset;
    final currentLine = controller.getLineAtOffset(cursorOffset);
    final selection = controller.selection;
    int? selectionStartLine;
    int? selectionEndLine;
    if (selection.start != selection.end) {
      selectionStartLine = controller.getLineAtOffset(selection.start);
      selectionEndLine = controller.getLineAtOffset(selection.end);

      if (selectionStartLine > selectionEndLine) {
        final temp = selectionStartLine;
        selectionStartLine = selectionEndLine;
        selectionEndLine = temp;
      }
    }

    final Map<int, int> lineSeverityMap = {};
    for (final diagnostic in _diagnostics) {
      final startLine = diagnostic.range['start']?['line'] as int?;
      final endLine = diagnostic.range['end']?['line'] as int?;
      if (startLine != null) {
        final severity = diagnostic.severity;
        if (severity == 1 || severity == 2) {
          final rangeEnd = endLine ?? startLine;
          for (int line = startLine; line <= rangeEnd; line++) {
            final existing = lineSeverityMap[line];
            if (existing == null || severity < existing) {
              lineSeverityMap[line] = severity;
            }
          }
        }
      }
    }

    final activeLineColor =
        gutterStyle.activeLineNumberColor ??
        (baseLineNumberStyle?.color ?? Colors.white);
    final inactiveLineColor =
        gutterStyle.inactiveLineNumberColor ??
        (baseLineNumberStyle?.color?.withAlpha(120) ?? Colors.grey);
    final errorColor = gutterStyle.errorLineNumberColor;
    final warningColor = gutterStyle.warningLineNumberColor;

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

    _actionBulbRects.clear();

    double currentY = firstVisibleLineY;
    for (int i = firstVisibleLine; i < lineCount; i++) {
      if (hasActiveFolds && _isLineFolded(i)) continue;

      final contentTop = currentY;
      final lineHeight = lineWrap ? _getWrappedLineHeight(i) : _lineHeight;

      final visualYOffset = _getGhostTextVisualOffset(i);

      if (contentTop + visualYOffset > viewBottom) break;

      if (contentTop + visualYOffset + lineHeight >= viewTop) {
        _drawGutterDecorations(
          canvas,
          offset,
          i,
          contentTop + visualYOffset,
          lineHeight,
        );

        Color lineNumberColor;
        final severity = lineSeverityMap[i];
        if (severity == 1) {
          lineNumberColor = errorColor;
        } else if (severity == 2) {
          lineNumberColor = warningColor;
        } else if (i == currentLine) {
          lineNumberColor = activeLineColor;
        } else if (selectionStartLine != null &&
            selectionEndLine != null &&
            i >= selectionStartLine &&
            i <= selectionEndLine) {
          lineNumberColor = activeLineColor;
        } else {
          lineNumberColor = inactiveLineColor;
        }

        final lineNumberStyle = baseLineNumberStyle!.copyWith(
          color: lineNumberColor,
        );

        final lineNumPara = _buildLineNumberParagraph(
          (i + 1).toString(),
          lineNumberStyle,
        );
        final numWidth = lineNumPara.longestLine;

        canvas.drawParagraph(
          lineNumPara,
          offset +
              Offset(
                (isRTL ? size.width - _gutterWidth : 0) +
                    (_gutterWidth - numWidth) / 2 -
                    (enableFolding ? (lineNumberStyle.fontSize ?? 14) / 2 : 0),
                (innerPadding?.top ?? 0) +
                    contentTop +
                    visualYOffset -
                    vscrollController.offset,
              ),
        );

        if (lspActionNotifier.value != null && lspConfig != null) {
          final actions = lspActionNotifier.value!.cast<Map<String, dynamic>>();
          if (actions.any((item) {
            try {
              return (item['arguments'][0]['range']['start']['line'] as int) ==
                  i;
            } on NoSuchMethodError {
              try {
                final fileUri = Uri.file(filePath!).toString();
                return (item['edit']['changes'][fileUri][0]['range']['start']['line']
                        as int) ==
                    i;
              } catch (e) {
                return false;
              }
            } catch (e) {
              return false;
            }
          })) {
            final icon = Icons.lightbulb_outline;
            final actionBulbPainter = TextPainter(
              text: TextSpan(
                text: String.fromCharCode(icon.codePoint),
                style: TextStyle(
                  fontSize: textStyle?.fontSize ?? 14,
                  color: Colors.yellowAccent,
                  fontFamily: icon.fontFamily,
                  package: icon.fontPackage,
                ),
              ),
              textDirection: _textDirection,
            );
            actionBulbPainter.layout();

            final bulbX = isRTL
                ? (isMobile
                      ? offset.dx + size.width - actionBulbPainter.width - 4
                      : offset.dx + size.width - _gutterWidth + 4)
                : (isMobile
                      ? offset.dx +
                            _gutterWidth -
                            actionBulbPainter.width -
                            (baseLineNumberStyle.fontSize ?? 14) +
                            4
                      : offset.dx + 4);
            final bulbY =
                offset.dy +
                (innerPadding?.top ?? 0) +
                contentTop +
                visualYOffset -
                vscrollController.offset +
                (_lineHeight - actionBulbPainter.height) / 2;

            _actionBulbRects[i] = Rect.fromLTWH(
              bulbX,
              bulbY,
              actionBulbPainter.width,
              actionBulbPainter.height,
            );

            actionBulbPainter.paint(canvas, Offset(bulbX, bulbY));
          }
        }

        if (enableFolding) {
          final foldRange = _getFoldRangeAtLine(i);
          if (foldRange != null) {
            final isInsideFoldedParent = _foldRanges.values.any(
              (parent) =>
                  parent != null &&
                  parent.isFolded &&
                  parent.startIndex < i &&
                  parent.endIndex >= i,
            );

            if (!isInsideFoldedParent) {
              final icon = foldRange.isFolded
                  ? (isRTL
                        ? Icons.chevron_left_outlined
                        : gutterStyle.foldedIcon)
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
                contentTop + visualYOffset - vscrollController.offset,
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
      textDirection: _textDirection,
    );
    iconPainter.layout();
    final iconX = isRTL
        ? offset.dx + size.width - iconPainter.width - 2
        : offset.dx + _gutterWidth - iconPainter.width - 2;
    iconPainter.paint(
      canvas,
      Offset(
        iconX,
        offset.dy +
            (innerPadding?.top ?? 0) +
            y +
            (_lineHeight - iconPainter.height) / 2,
      ),
    );
  }

  int _findIndentBasedEndLine(
    int startLine,
    int leadingSpaces,
    bool hasActiveFolds,
  ) {
    final key = '$startLine-$leadingSpaces-${hasActiveFolds ? 1 : 0}';
    if (_indentEndLineCache.containsKey(key)) {
      return _indentEndLineCache[key]!;
    }

    int endLine = startLine + 1;
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

    _indentEndLineCache[key] = endLine;
    return endLine;
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
      final endsWithBracket =
          trimmed.endsWith('{') ||
          trimmed.endsWith('(') ||
          trimmed.endsWith('[') ||
          trimmed.endsWith(':');

      final openingTagName = _extractOpeningTagName(lineText);
      final isTagBasedLanguage =
          _language.name == 'html' ||
          _language.name == 'xml' ||
          (_language.aliases?.contains('html') ?? false) ||
          (_language.aliases?.contains('xml') ?? false) ||
          (languageId?.contains('html') ?? false) ||
          (languageId?.contains('xml') ?? false);

      if (!endsWithBracket && (!isTagBasedLanguage || openingTagName == null)) {
        return;
      }

      final leadingSpaces = lineText.length - lineText.trimLeft().length;
      final indentLevel = _lineIndentCache.containsKey(i)
          ? _lineIndentCache[i]!
          : leadingSpaces ~/ tabSize;
      if (!_lineIndentCache.containsKey(i)) {
        _lineIndentCache[i] = indentLevel;
      }
      final lastChar = trimmed[trimmed.length - 1];
      int endLine = i + 1;

      if (lastChar == '{' || lastChar == '(' || lastChar == '[') {
        final lineStartOffset = controller.getLineStartOffset(i);
        final bracketPos = lineStartOffset + trimmed.length - 1;
        final matchPos = _findMatchingBracket(controller.text, bracketPos);

        if (matchPos != null) {
          endLine = controller.getLineAtOffset(matchPos) + 1;
        } else {
          endLine = _findIndentBasedEndLine(i, leadingSpaces, hasActiveFolds);
        }
      } else if (openingTagName != null && isTagBasedLanguage) {
        final matchLine = _findMatchingClosingTagLine(openingTagName, i);
        if (matchLine != null) {
          endLine = matchLine + 1;
        } else {
          endLine = _findIndentBasedEndLine(i, leadingSpaces, hasActiveFolds);
        }
      } else {
        endLine = _findIndentBasedEndLine(i, leadingSpaces, hasActiveFolds);
      }

      if (endLine <= i + 1) return;

      if (endLine < firstVisibleLine) return;

      double guideX = 0;
      if (leadingSpaces > 0) {
        ui.Paragraph para;
        if (_paragraphCache.containsKey(i)) {
          para = _paragraphCache[i]!;
        } else {
          para = _buildHighlightedParagraph(i, lineText);
          _paragraphCache[i] = para;
        }
        final boxes = para.getBoxesForRange(0, leadingSpaces);
        guideX = boxes.isNotEmpty ? boxes.last.right : 0;
      }

      bool wouldPassThroughText = false;
      for (
        int checkLine = i + 1;
        checkLine < endLine - 1 && checkLine < controller.lineCount;
        checkLine++
      ) {
        if (hasActiveFolds && _isLineFolded(checkLine)) continue;

        String checkLineText;
        if (_lineTextCache.containsKey(checkLine)) {
          checkLineText = _lineTextCache[checkLine]!;
        } else {
          checkLineText = controller.getLineText(checkLine);
          _lineTextCache[checkLine] = checkLineText;
        }

        if (checkLineText.trim().isEmpty) continue;

        final checkLeadingSpaces =
            checkLineText.length - checkLineText.trimLeft().length;

        if (checkLeadingSpaces <= leadingSpaces) {
          wouldPassThroughText = true;
          break;
        }
      }

      if (wouldPassThroughText) return;

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

      final screenGuideX = isRTL
          ? offset.dx +
                size.width -
                _gutterWidth -
                (innerPadding?.right ?? 0) -
                block.guideX +
                (lineWrap ? 0 : _effectiveHScroll)
          : offset.dx +
                _gutterWidth +
                (innerPadding?.left ?? 0) +
                block.guideX -
                (lineWrap ? 0 : _effectiveHScroll);

      if (isRTL) {
        if (screenGuideX > offset.dx + size.width - _gutterWidth ||
            screenGuideX < offset.dx) {
          continue;
        }
      } else {
        if (screenGuideX < offset.dx + _gutterWidth ||
            screenGuideX > offset.dx + size.width) {
          continue;
        }
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

    final contentWidth =
        size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
    final paragraphWidth = lineWrap
        ? _wrapWidth
        : (isRTL ? contentWidth : null);

    ui.Paragraph para;
    if (_paragraphCache.containsKey(lineIndex)) {
      para = _paragraphCache[lineIndex]!;
    } else {
      para = _buildHighlightedParagraph(
        lineIndex,
        lineText,
        width: paragraphWidth,
      );
      _paragraphCache[lineIndex] = para;
    }

    final boxes = para.getBoxesForRange(columnIndex, columnIndex + 1);
    if (boxes.isEmpty) return;

    final box = boxes.first;

    final lineY = _getLineYOffset(lineIndex, hasActiveFolds);
    final boxY = lineY + box.top;
    final colorBoxOffset = _getColorBoxOffsetForLine(lineIndex, columnIndex);

    final scroll = lineWrap ? 0.0 : _effectiveHScroll;
    final textX = isRTL
        ? (innerPadding?.left ?? 0) - scroll
        : _gutterWidth + (innerPadding?.left ?? 0) - scroll;
    final screenX = offset.dx + textX + box.left + colorBoxOffset;
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

    final sortedDiagnostics = List<LspErrors>.from(_diagnostics)
      ..sort((a, b) => (b.severity).compareTo(a.severity));

    for (final diagnostic in sortedDiagnostics) {
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

        final boxKey = '$lineIndex-$lineStartChar-$lineEndChar';
        final boxes = _diagnosticPathCache.containsKey(boxKey)
            ? _diagnosticPathCache[boxKey] as List<ui.TextBox>
            : para.getBoxesForRange(
                lineStartChar.clamp(0, lineText.length),
                lineEndChar.clamp(0, lineText.length),
              );
        if (!_diagnosticPathCache.containsKey(boxKey)) {
          _diagnosticPathCache[boxKey] = boxes;
        }

        if (boxes.isEmpty) continue;

        final lineY = _getLineYOffset(lineIndex, hasActiveFolds);

        for (final box in boxes) {
          final screenX = isRTL
              ? offset.dx +
                    size.width -
                    _gutterWidth -
                    (innerPadding?.right ?? 0) -
                    box.right +
                    (lineWrap ? 0 : _effectiveHScroll)
              : offset.dx +
                    _gutterWidth +
                    (innerPadding?.left ?? 0) +
                    box.left -
                    (lineWrap ? 0 : _effectiveHScroll);
          final screenY =
              offset.dy +
              (innerPadding?.top ?? 0) +
              lineY +
              box.top +
              _lineHeight -
              vscrollController.offset;

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

  void _drawSearchHighlights(
    Canvas canvas,
    Offset offset,
    int firstVisibleLine,
    int lastVisibleLine,
    double firstVisibleLineY,
    bool hasActiveFolds,
  ) {
    final highlights = controller.searchHighlights;
    if (highlights.isEmpty) return;

    for (final highlight in highlights) {
      final start = highlight.start;
      final end = highlight.end;

      int startLine = controller.getLineAtOffset(start);
      int endLine = controller.getLineAtOffset(end);

      if (endLine < firstVisibleLine || startLine > lastVisibleLine) continue;

      final highlightStyle = highlight.isCurrentMatch
          ? (_matchHighlightStyle?.currentMatchStyle ??
                const TextStyle(backgroundColor: Color(0xFF01A2FF)))
          : (_matchHighlightStyle?.otherMatchStyle ??
                const TextStyle(
                  backgroundColor: Color.fromARGB(163, 72, 215, 255),
                ));

      final highlightPaint = Paint()
        ..color = highlightStyle.backgroundColor ?? Colors.amberAccent
        ..style = PaintingStyle.fill;

      for (int lineIndex = startLine; lineIndex <= endLine; lineIndex++) {
        if (lineIndex < firstVisibleLine || lineIndex > lastVisibleLine) {
          continue;
        }
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

        if (lineSelStart >= lineSelEnd) continue;

        final contentWidth =
            size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
        final paragraphWidth = lineWrap
            ? _wrapWidth
            : (isRTL ? contentWidth : null);

        ui.Paragraph para;
        if (_paragraphCache.containsKey(lineIndex)) {
          para = _paragraphCache[lineIndex]!;
        } else {
          para = _buildHighlightedParagraph(
            lineIndex,
            lineText,
            width: paragraphWidth,
          );
          _paragraphCache[lineIndex] = para;
        }

        final lineY = _getLineYOffset(lineIndex, hasActiveFolds);

        final scroll = lineWrap ? 0.0 : _effectiveHScroll;
        final textX = isRTL
            ? (innerPadding?.left ?? 0) - scroll
            : _gutterWidth + (innerPadding?.left ?? 0) - scroll;

        if (lineText.isNotEmpty) {
          final boxKey = '$lineIndex-$lineSelStart-$lineSelEnd';
          final boxes = _searchHighlightCache.containsKey(boxKey)
              ? _searchHighlightCache[boxKey] as List<ui.TextBox>
              : para.getBoxesForRange(
                  lineSelStart.clamp(0, lineText.length),
                  lineSelEnd.clamp(0, lineText.length),
                );
          if (!_searchHighlightCache.containsKey(boxKey)) {
            _searchHighlightCache[boxKey] = boxes;
          }

          for (final box in boxes) {
            final screenX = offset.dx + textX + box.left;
            final screenY =
                offset.dy +
                (innerPadding?.top ?? 0) +
                lineY +
                box.top -
                vscrollController.offset;

            canvas.drawRect(
              Rect.fromLTWH(
                screenX,
                screenY,
                box.right - box.left,
                _lineHeight,
              ),
              highlightPaint,
            );
          }
        }
      }
    }
  }

  void _drawFoldedLineHighlights(
    Canvas canvas,
    Offset offset,
    int firstVisibleLine,
    int lastVisibleLine,
    double firstVisibleLineY,
    bool hasActiveFolds,
  ) {
    if (!hasActiveFolds) return;

    final highlightColor =
        gutterStyle.foldedLineHighlightColor ??
        selectionStyle.selectionColor.withAlpha(60);

    final highlightPaint = Paint()
      ..color = highlightColor
      ..style = PaintingStyle.fill;

    for (final foldRange in controller.foldings.values.where(
      (f) => f != null,
    )) {
      if (!foldRange!.isFolded) continue;

      final foldStartLine = foldRange.startIndex;

      if (foldStartLine < firstVisibleLine || foldStartLine > lastVisibleLine) {
        continue;
      }

      final lineY = _getLineYOffset(foldStartLine, hasActiveFolds);
      final lineHeight = lineWrap
          ? _getWrappedLineHeight(foldStartLine)
          : _lineHeight;

      final screenY =
          offset.dy +
          (innerPadding?.top ?? 0) +
          lineY -
          vscrollController.offset;

      final highlightX = isRTL ? offset.dx : offset.dx + _gutterWidth;
      final highlightWidth = size.width - _gutterWidth;

      canvas.drawRect(
        Rect.fromLTWH(highlightX, screenY, highlightWidth, lineHeight),
        highlightPaint,
      );
    }
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

      final contentWidth =
          size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
      final paragraphWidth = lineWrap
          ? _wrapWidth
          : (isRTL ? contentWidth : null);

      ui.Paragraph para;
      if (_paragraphCache.containsKey(lineIndex)) {
        para = _paragraphCache[lineIndex]!;
      } else {
        para = _buildHighlightedParagraph(
          lineIndex,
          lineText,
          width: paragraphWidth,
        );
        _paragraphCache[lineIndex] = para;
      }

      final lineY = _getLineYOffset(lineIndex, hasActiveFolds);

      final colorBoxOffsetStart = _getColorBoxOffsetForLine(
        lineIndex,
        lineSelStart,
      );
      final colorBoxOffsetEnd = _getColorBoxOffsetForLine(
        lineIndex,
        lineSelEnd,
      );

      final scroll = lineWrap ? 0.0 : _effectiveHScroll;
      final textX = isRTL
          ? (innerPadding?.left ?? 0) - scroll
          : _gutterWidth + (innerPadding?.left ?? 0) - scroll;

      if (lineSelStart < lineSelEnd && lineText.isNotEmpty) {
        final boxes = para.getBoxesForRange(
          lineSelStart.clamp(0, lineText.length),
          lineSelEnd.clamp(0, lineText.length),
        );

        for (int i = 0; i < boxes.length; i++) {
          final box = boxes[i];
          final adjustedLeft = box.left + colorBoxOffsetStart;
          final adjustedRight = box.right + colorBoxOffsetEnd;

          final screenX = offset.dx + textX + adjustedLeft;
          final screenY =
              offset.dy +
              (innerPadding?.top ?? 0) +
              lineY +
              box.top -
              vscrollController.offset;

          canvas.drawRect(
            Rect.fromLTWH(
              screenX,
              screenY,
              adjustedRight - adjustedLeft,
              _lineHeight,
            ),
            selectionPaint,
          );
        }
      } else if (lineIndex < endLine) {
        final screenX = isRTL
            ? offset.dx + textX + contentWidth - 8
            : offset.dx + textX;
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

  void _drawDocumentHighlights(
    Canvas canvas,
    Offset offset,
    int firstVisibleLine,
    int lastVisibleLine,
    double firstVisibleLineY,
    bool hasActiveFolds,
  ) {
    final highlights = controller.documentHighlights;
    if (highlights.isEmpty) return;

    final highlightPaint = Paint()
      ..color = (editorTheme['root']?.color ?? Colors.white).withValues(
        alpha: 0.2,
      )
      ..style = PaintingStyle.fill;

    for (final highlight in highlights) {
      final startLine = highlight.startLine;
      final endLine = highlight.endLine;

      if (endLine < firstVisibleLine || startLine > lastVisibleLine) continue;

      for (int lineIndex = startLine; lineIndex <= endLine; lineIndex++) {
        if (lineIndex < firstVisibleLine || lineIndex > lastVisibleLine) {
          continue;
        }
        if (hasActiveFolds && _isLineFolded(lineIndex)) continue;

        final lineText =
            _lineTextCache[lineIndex] ?? controller.getLineText(lineIndex);
        final lineLength = lineText.length;

        int lineHighStart = 0;
        int lineHighEnd = lineLength;

        if (lineIndex == startLine) {
          lineHighStart = highlight.startColumn;
        }
        if (lineIndex == endLine) {
          lineHighEnd = highlight.endColumn;
        }

        lineHighStart = lineHighStart.clamp(0, lineLength);
        lineHighEnd = lineHighEnd.clamp(0, lineLength);

        if (lineHighStart >= lineHighEnd) continue;

        final contentWidth =
            size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
        final paragraphWidth = lineWrap
            ? _wrapWidth
            : (isRTL ? contentWidth : null);

        ui.Paragraph para;
        if (_paragraphCache.containsKey(lineIndex)) {
          para = _paragraphCache[lineIndex]!;
        } else {
          para = _buildHighlightedParagraph(
            lineIndex,
            lineText,
            width: paragraphWidth,
          );
        }

        final lineY = _getLineYOffset(lineIndex, hasActiveFolds);
        final colorBoxOffset = _getColorBoxOffsetForLine(
          lineIndex,
          lineHighStart,
        );
        final boxes = para.getBoxesForRange(lineHighStart, lineHighEnd);

        final scroll = lineWrap ? 0.0 : _effectiveHScroll;
        final textX = isRTL
            ? (innerPadding?.left ?? 0) - scroll
            : _gutterWidth + (innerPadding?.left ?? 0) - scroll;

        for (final box in boxes) {
          final adjustedLeft = box.left + colorBoxOffset;
          final adjustedRight = box.right + colorBoxOffset;

          final screenX = offset.dx + textX + adjustedLeft;
          final screenY =
              offset.dy +
              (innerPadding?.top ?? 0) +
              lineY +
              box.top -
              vscrollController.offset;

          canvas.drawRect(
            Rect.fromLTWH(
              screenX,
              screenY,
              adjustedRight - adjustedLeft,
              box.bottom - box.top,
            ),
            highlightPaint,
          );
        }
      }
    }
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
    final contentWidth =
        size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
    final paragraphWidth = lineWrap
        ? _wrapWidth
        : (isRTL ? contentWidth : null);
    final scroll = lineWrap ? 0.0 : _effectiveHScroll;
    final textX = isRTL
        ? (innerPadding?.left ?? 0) - scroll
        : _gutterWidth + (innerPadding?.left ?? 0) - scroll;

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
            width: paragraphWidth,
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

    startX += _getColorBoxOffsetForLine(startLine, startCol);

    final startScreenX = offset.dx + textX + startX;
    final startScreenY =
        offset.dy +
        (innerPadding?.top ?? 0) +
        startY +
        startYInLine -
        vscrollController.offset;

    _startHandleRect = Rect.fromCenter(
      center: Offset(
        isRTL
            ? startScreenX + (textStyle?.fontSize ?? 14) / 2
            : startScreenX - (textStyle?.fontSize ?? 14) / 2,
        startScreenY + _lineHeight + handleRadius,
      ),
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
            width: paragraphWidth,
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

    endX += _getColorBoxOffsetForLine(endLine, endCol);

    final endScreenX = offset.dx + textX + endX;
    final endScreenY =
        offset.dy +
        (innerPadding?.top ?? 0) +
        endY +
        endYInLine -
        vscrollController.offset;

    _endHandleRect = Rect.fromCenter(
      center: Offset(
        isRTL
            ? endScreenX - (textStyle?.fontSize ?? 14) / 2
            : endScreenX + (textStyle?.fontSize ?? 14) / 2,
        endScreenY + _lineHeight + handleRadius,
      ),
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
    if (_ghostTextAnchorLine == null) return;
    if (!controller.selection.isValid || !controller.selection.isCollapsed) {
      return;
    }

    final cursorOffset = controller.selection.extentOffset;
    final cursorLine = _ghostTextAnchorLine!;

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

    final defaultGhostColor =
        (textStyle?.color ?? editorTheme['root']?.color ?? Colors.white)
            .withAlpha(100);
    final ghostStyle = ui.TextStyle(
      color: _ghostTextStyle?.color ?? defaultGhostColor,
      fontSize: _ghostTextStyle?.fontSize ?? textStyle?.fontSize ?? 14.0,
      fontFamily: _ghostTextStyle?.fontFamily ?? textStyle?.fontFamily,
      fontStyle: _ghostTextStyle?.fontStyle ?? FontStyle.italic,
      fontWeight: _ghostTextStyle?.fontWeight,
      letterSpacing: _ghostTextStyle?.letterSpacing,
      wordSpacing: _ghostTextStyle?.wordSpacing,
      decoration: _ghostTextStyle?.decoration,
      decorationColor: _ghostTextStyle?.decorationColor,
    );

    final aiLines = _aiResponse?.split('\n') ?? [];
    final isSingleLineGhost = aiLines.length == 1;
    final clampedCol = cursorCol.clamp(0, lineText.length);

    if (isSingleLineGhost && aiLines.isNotEmpty && aiLines[0].isNotEmpty) {
      final ghostBuilder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: textStyle?.fontFamily,
                fontSize: textStyle?.fontSize ?? 14.0,
                height: textStyle?.height ?? 1.2,
                textDirection: textDirection,
              ),
            )
            ..pushStyle(ghostStyle)
            ..addText(aiLines[0]);
      final ghostPara = ghostBuilder.build();
      ghostPara.layout(const ui.ParagraphConstraints(width: double.infinity));
      final firstLineGhostWidth = ghostPara.longestLine;

      final screenY =
          offset.dy +
          (innerPadding?.top ?? 0) +
          cursorY -
          vscrollController.offset;

      final screenX = isRTL
          ? offset.dx +
                size.width -
                _gutterWidth -
                (innerPadding?.right ?? 0) -
                cursorX +
                (lineWrap ? 0 : _effectiveHScroll) -
                firstLineGhostWidth
          : offset.dx +
                _gutterWidth +
                (innerPadding?.left ?? 0) +
                cursorX -
                (lineWrap ? 0 : _effectiveHScroll);

      final bgColor = editorTheme['root']?.backgroundColor ?? Colors.black;
      final originalPara = _paragraphCache[cursorLine];
      if (originalPara != null && clampedCol < lineText.length) {
        final remainingWidth = originalPara.longestLine - cursorX;
        if (remainingWidth > 0) {
          canvas.drawRect(
            Rect.fromLTWH(screenX, screenY, remainingWidth + 2, _lineHeight),
            Paint()..color = bgColor,
          );
        }
      }

      canvas.drawParagraph(ghostPara, Offset(screenX, screenY));

      if (clampedCol < lineText.length) {
        final remainingText = lineText.substring(clampedCol);

        final normalStyle = ui.TextStyle(
          color: textStyle?.color ?? editorTheme['root']?.color ?? Colors.white,
          fontSize: textStyle?.fontSize ?? 14.0,
          fontFamily: textStyle?.fontFamily,
          fontWeight: textStyle?.fontWeight,
        );

        final remainingBuilder =
            ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  fontFamily: textStyle?.fontFamily,
                  fontSize: textStyle?.fontSize ?? 14.0,
                  height: textStyle?.height ?? 1.2,
                ),
              )
              ..pushStyle(normalStyle)
              ..addText(remainingText);

        final remainingPara = remainingBuilder.build();
        remainingPara.layout(
          const ui.ParagraphConstraints(width: double.infinity),
        );

        canvas.drawParagraph(
          remainingPara,
          Offset(screenX + firstLineGhostWidth, screenY),
        );
      }
      return;
    }

    if (aiLines.isNotEmpty && aiLines[0].isNotEmpty) {
      final ghostBuilder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: textStyle?.fontFamily,
                fontSize: textStyle?.fontSize ?? 14.0,
                height: textStyle?.height ?? 1.2,
                textDirection: textDirection,
              ),
            )
            ..pushStyle(ghostStyle)
            ..addText(aiLines[0]);
      final ghostPara = ghostBuilder.build();
      ghostPara.layout(const ui.ParagraphConstraints(width: double.infinity));
      final firstGhostWidth = ghostPara.longestLine;

      final screenY =
          offset.dy +
          (innerPadding?.top ?? 0) +
          cursorY -
          vscrollController.offset;

      final screenX = isRTL
          ? offset.dx +
                size.width -
                _gutterWidth -
                (innerPadding?.right ?? 0) -
                cursorX +
                (lineWrap ? 0 : _effectiveHScroll) -
                firstGhostWidth
          : offset.dx +
                _gutterWidth +
                (innerPadding?.left ?? 0) +
                cursorX -
                (lineWrap ? 0 : _effectiveHScroll);

      final bgColor = editorTheme['root']?.backgroundColor ?? Colors.black;
      final originalPara = _paragraphCache[cursorLine];
      if (originalPara != null && clampedCol < lineText.length) {
        final remainingWidth = originalPara.longestLine - cursorX;
        if (remainingWidth > 0) {
          canvas.drawRect(
            Rect.fromLTWH(screenX, screenY, remainingWidth + 2, _lineHeight),
            Paint()..color = bgColor,
          );
        }
      }

      canvas.drawParagraph(ghostPara, Offset(screenX, screenY));
    }

    double lastGhostLineWidth = 0;
    double lastGhostLineScreenY = 0;
    double lastGhostLineScreenX = 0;

    for (int i = 1; i < aiLines.length; i++) {
      final aiLineText = aiLines[i];
      final isLastLine = i == aiLines.length - 1;

      final lineY = cursorY + (i * _lineHeight);

      final screenY =
          offset.dy +
          (innerPadding?.top ?? 0) +
          lineY -
          vscrollController.offset;

      ui.Paragraph? para;
      double paraWidth = 0;
      if (aiLineText.isNotEmpty || isLastLine) {
        final builder =
            ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  fontFamily: textStyle?.fontFamily,
                  fontSize: textStyle?.fontSize ?? 14.0,
                  height: textStyle?.height ?? 1.2,
                  textDirection: textDirection,
                ),
              )
              ..pushStyle(ghostStyle)
              ..addText(aiLineText);

        para = builder.build();
        para.layout(const ui.ParagraphConstraints(width: double.infinity));
        paraWidth = para.longestLine;
      }

      final screenX = isRTL
          ? offset.dx +
                size.width -
                _gutterWidth -
                (innerPadding?.right ?? 0) +
                (lineWrap ? 0 : _effectiveHScroll) -
                paraWidth
          : offset.dx +
                _gutterWidth +
                (innerPadding?.left ?? 0) -
                (lineWrap ? 0 : _effectiveHScroll);

      if (screenY + _lineHeight < offset.dy ||
          screenY > offset.dy + vscrollController.position.viewportDimension) {
        if (isLastLine) {
          lastGhostLineScreenY = screenY;
          lastGhostLineScreenX = screenX;
          lastGhostLineWidth = paraWidth;
        }
        continue;
      }

      if (para != null) {
        canvas.drawParagraph(para, Offset(screenX, screenY));

        if (isLastLine) {
          lastGhostLineWidth = paraWidth;
          lastGhostLineScreenY = screenY;
          lastGhostLineScreenX = screenX;
        }
      }
    }

    if (clampedCol < lineText.length && aiLines.length > 1) {
      final remainingText = lineText.substring(clampedCol);

      final normalStyle = ui.TextStyle(
        color: textStyle?.color ?? editorTheme['root']?.color ?? Colors.white,
        fontSize: textStyle?.fontSize ?? 14.0,
        fontFamily: textStyle?.fontFamily,
        fontWeight: textStyle?.fontWeight,
      );

      final remainingBuilder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: textStyle?.fontFamily,
                fontSize: textStyle?.fontSize ?? 14.0,
                height: textStyle?.height ?? 1.2,
              ),
            )
            ..pushStyle(normalStyle)
            ..addText(remainingText);

      final remainingPara = remainingBuilder.build();
      remainingPara.layout(
        const ui.ParagraphConstraints(width: double.infinity),
      );

      canvas.drawParagraph(
        remainingPara,
        Offset(lastGhostLineScreenX + lastGhostLineWidth, lastGhostLineScreenY),
      );
    }
  }

  void _drawLineDecorations(
    Canvas canvas,
    Offset offset,
    int firstVisibleLine,
    int lastVisibleLine,
    double firstVisibleLineY,
    bool hasActiveFolds,
  ) {
    final decorations = controller.lineDecorations;
    if (decorations.isEmpty) return;

    for (final decoration in decorations) {
      if (decoration.endLine < firstVisibleLine ||
          decoration.startLine > lastVisibleLine) {
        continue;
      }

      final paint = Paint()
        ..color = decoration.color
        ..style = PaintingStyle.fill;

      double currentY = firstVisibleLineY;
      for (
        int i = firstVisibleLine;
        i <= lastVisibleLine && i < controller.lineCount;
        i++
      ) {
        if (hasActiveFolds && _isLineFolded(i)) continue;

        final lineHeight = lineWrap ? _getWrappedLineHeight(i) : _lineHeight;

        if (i >= decoration.startLine && i <= decoration.endLine) {
          final screenY =
              offset.dy +
              (innerPadding?.top ?? 0) +
              currentY -
              vscrollController.offset;
          final screenX =
              offset.dx +
              _gutterWidth +
              (innerPadding?.left ?? 0) -
              (lineWrap ? 0 : _effectiveHScroll);

          switch (decoration.type) {
            case LineDecorationType.background:
              final width =
                  size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
              canvas.drawRect(
                Rect.fromLTWH(screenX, screenY, width, lineHeight),
                paint,
              );
              break;

            case LineDecorationType.leftBorder:
              paint.style = PaintingStyle.fill;
              canvas.drawRect(
                Rect.fromLTWH(
                  offset.dx + _gutterWidth,
                  screenY,
                  decoration.thickness,
                  lineHeight,
                ),
                paint,
              );
              break;

            case LineDecorationType.underline:
              paint.style = PaintingStyle.stroke;
              paint.strokeWidth = decoration.thickness;
              final width =
                  size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
              canvas.drawLine(
                Offset(screenX, screenY + lineHeight - decoration.thickness),
                Offset(
                  screenX + width,
                  screenY + lineHeight - decoration.thickness,
                ),
                paint,
              );
              break;

            case LineDecorationType.wavyUnderline:
              paint.style = PaintingStyle.stroke;
              paint.strokeWidth = decoration.thickness;
              final width =
                  size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
              final path = Path();
              final waveHeight = decoration.thickness * 2;
              final waveWidth = waveHeight * 2;
              double x = screenX;
              final y = screenY + lineHeight - decoration.thickness;
              path.moveTo(x, y);
              while (x < screenX + width) {
                path.quadraticBezierTo(
                  x + waveWidth / 4,
                  y - waveHeight,
                  x + waveWidth / 2,
                  y,
                );
                path.quadraticBezierTo(
                  x + waveWidth * 3 / 4,
                  y + waveHeight,
                  x + waveWidth,
                  y,
                );
                x += waveWidth;
              }
              canvas.drawPath(path, paint);
              break;
          }
        }

        currentY += lineHeight;
      }
    }
  }

  void _drawLineHighlight(
    Canvas canvas,
    Offset offset,
    int firstVisibleLine,
    int lastVisibleLine,
    double firstVisibleLineY,
    bool hasActiveFolds,
  ) {
    if (_highlightedLine == null || _lineHighlightAnimation == null) return;

    final highlightLine = _highlightedLine!;

    if (highlightLine < firstVisibleLine || highlightLine > lastVisibleLine) {
      return;
    }

    if (hasActiveFolds && _isLineFolded(highlightLine)) return;

    final opacity = _lineHighlightAnimation!.value;
    if (opacity <= 0.0) {
      _highlightedLine = null;
      return;
    }

    final lineY = _getLineYOffset(highlightLine, hasActiveFolds);
    final lineHeight = lineWrap
        ? _getWrappedLineHeight(highlightLine)
        : _lineHeight;

    final screenY =
        offset.dy + (innerPadding?.top ?? 0) + lineY - vscrollController.offset;
    final screenX =
        offset.dx +
        _gutterWidth +
        (innerPadding?.left ?? 0) -
        (lineWrap ? 0 : _effectiveHScroll);

    final highlightColor =
        (textStyle?.color ?? editorTheme['root']?.color ?? Colors.yellow)
            .withValues(alpha: opacity);

    final paint = Paint()
      ..color = highlightColor
      ..style = PaintingStyle.fill;

    final width = size.width - _gutterWidth - (innerPadding?.horizontal ?? 0);
    canvas.drawRect(Rect.fromLTWH(screenX, screenY, width, lineHeight), paint);
  }

  void _drawGutterDecorations(
    Canvas canvas,
    Offset offset,
    int lineIndex,
    double contentTop,
    double lineHeight,
  ) {
    final decorations = controller.gutterDecorations;
    if (decorations.isEmpty) return;

    for (final decoration in decorations) {
      if (lineIndex < decoration.startLine || lineIndex > decoration.endLine) {
        continue;
      }

      final screenY =
          offset.dy +
          (innerPadding?.top ?? 0) +
          contentTop -
          vscrollController.offset;

      switch (decoration.type) {
        case GutterDecorationType.colorBar:
          final paint = Paint()
            ..color = decoration.color
            ..style = PaintingStyle.fill;
          canvas.drawRect(
            Rect.fromLTWH(offset.dx, screenY, decoration.width, lineHeight),
            paint,
          );
          break;

        case GutterDecorationType.icon:
          if (decoration.icon != null) {
            final iconPainter = TextPainter(
              text: TextSpan(
                text: String.fromCharCode(decoration.icon!.codePoint),
                style: TextStyle(
                  fontSize: textStyle?.fontSize ?? 14,
                  color: decoration.color,
                  fontFamily: decoration.icon!.fontFamily,
                  package: decoration.icon!.fontPackage,
                ),
              ),
              textDirection: TextDirection.ltr,
            );
            iconPainter.layout();
            iconPainter.paint(
              canvas,
              Offset(
                offset.dx + 2,
                screenY + (lineHeight - iconPainter.height) / 2,
              ),
            );
          }
          break;

        case GutterDecorationType.dot:
          final paint = Paint()
            ..color = decoration.color
            ..style = PaintingStyle.fill;
          final radius = (textStyle?.fontSize ?? 14) / 4;
          canvas.drawCircle(
            Offset(
              offset.dx + decoration.width / 2 + 2,
              screenY + lineHeight / 2,
            ),
            radius,
            paint,
          );
          break;
      }
    }
  }

  void _drawGhostText(
    Canvas canvas,
    Offset offset,
    int firstVisibleLine,
    int lastVisibleLine,
    double firstVisibleLineY,
    bool hasActiveFolds,
  ) {
    final ghost = controller.ghostText;
    if (ghost == null || ghost.text.isEmpty) return;

    final cursorLine = ghost.line;
    final cursorCol = ghost.column;

    if (hasActiveFolds && _isLineFolded(cursorLine)) return;

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

    final defaultGhostColor =
        (textStyle?.color ?? editorTheme['root']?.color ?? Colors.white)
            .withAlpha(100);
    final customStyle = ghost.style;
    final ghostStyle = ui.TextStyle(
      color: customStyle?.color ?? defaultGhostColor,
      fontSize: customStyle?.fontSize ?? textStyle?.fontSize ?? 14.0,
      fontFamily: customStyle?.fontFamily ?? textStyle?.fontFamily,
      fontStyle: customStyle?.fontStyle ?? FontStyle.italic,
      fontWeight: customStyle?.fontWeight,
      letterSpacing: customStyle?.letterSpacing,
      wordSpacing: customStyle?.wordSpacing,
      decoration: customStyle?.decoration,
      decorationColor: customStyle?.decorationColor,
    );

    final ghostLines = ghost.text.split('\n');
    final isSingleLineGhost = ghostLines.length == 1;

    double firstLineGhostWidth = 0;
    if (isSingleLineGhost && ghostLines[0].isNotEmpty) {
      final ghostBuilder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: textStyle?.fontFamily,
                fontSize: textStyle?.fontSize ?? 14.0,
                height: textStyle?.height ?? 1.2,
              ),
            )
            ..pushStyle(ghostStyle)
            ..addText(ghostLines[0]);
      final ghostPara = ghostBuilder.build();
      ghostPara.layout(const ui.ParagraphConstraints(width: double.infinity));
      firstLineGhostWidth = ghostPara.longestLine;

      final screenY =
          offset.dy +
          (innerPadding?.top ?? 0) +
          cursorY -
          vscrollController.offset;

      final screenX =
          offset.dx +
          _gutterWidth +
          (innerPadding?.left ?? 0) +
          cursorX -
          (lineWrap ? 0 : _effectiveHScroll);

      final clampedCol = cursorCol.clamp(0, lineText.length);
      final bgColor = editorTheme['root']?.backgroundColor ?? Colors.black;
      final originalPara = _paragraphCache[cursorLine];
      if (originalPara != null && clampedCol < lineText.length) {
        final remainingWidth = originalPara.longestLine - cursorX;
        if (remainingWidth > 0) {
          canvas.drawRect(
            Rect.fromLTWH(screenX, screenY, remainingWidth + 2, _lineHeight),
            Paint()..color = bgColor,
          );
        }
      }

      canvas.drawParagraph(ghostPara, Offset(screenX, screenY));

      if (clampedCol < lineText.length) {
        final remainingText = lineText.substring(clampedCol);

        final normalStyle = ui.TextStyle(
          color: textStyle?.color ?? editorTheme['root']?.color ?? Colors.white,
          fontSize: textStyle?.fontSize ?? 14.0,
          fontFamily: textStyle?.fontFamily,
          fontWeight: textStyle?.fontWeight,
        );

        final remainingBuilder =
            ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  fontFamily: textStyle?.fontFamily,
                  fontSize: textStyle?.fontSize ?? 14.0,
                  height: textStyle?.height ?? 1.2,
                ),
              )
              ..pushStyle(normalStyle)
              ..addText(remainingText);

        final remainingPara = remainingBuilder.build();
        remainingPara.layout(
          const ui.ParagraphConstraints(width: double.infinity),
        );

        canvas.drawParagraph(
          remainingPara,
          Offset(screenX + firstLineGhostWidth, screenY),
        );
      }
      return;
    }

    final multiClampedCol = cursorCol.clamp(0, lineText.length);

    if (ghostLines.isNotEmpty && ghostLines[0].isNotEmpty) {
      final ghostBuilder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: textStyle?.fontFamily,
                fontSize: textStyle?.fontSize ?? 14.0,
                height: textStyle?.height ?? 1.2,
              ),
            )
            ..pushStyle(ghostStyle)
            ..addText(ghostLines[0]);
      final ghostPara = ghostBuilder.build();
      ghostPara.layout(const ui.ParagraphConstraints(width: double.infinity));

      final screenY =
          offset.dy +
          (innerPadding?.top ?? 0) +
          cursorY -
          vscrollController.offset;

      final screenX =
          offset.dx +
          _gutterWidth +
          (innerPadding?.left ?? 0) +
          cursorX -
          (lineWrap ? 0 : _effectiveHScroll);

      final bgColor = editorTheme['root']?.backgroundColor ?? Colors.black;
      final originalPara = _paragraphCache[cursorLine];
      if (originalPara != null && multiClampedCol < lineText.length) {
        final remainingWidth = originalPara.longestLine - cursorX;
        if (remainingWidth > 0) {
          canvas.drawRect(
            Rect.fromLTWH(screenX, screenY, remainingWidth + 2, _lineHeight),
            Paint()..color = bgColor,
          );
        }
      }

      canvas.drawParagraph(ghostPara, Offset(screenX, screenY));
    }

    double lastGhostLineWidth = 0;
    double lastGhostLineScreenY = 0;
    double lastGhostLineScreenX = 0;

    for (int i = 1; i < ghostLines.length; i++) {
      final ghostLineText = ghostLines[i];
      final isLastLine = i == ghostLines.length - 1;

      final lineY = cursorY + (i * _lineHeight);

      final screenY =
          offset.dy +
          (innerPadding?.top ?? 0) +
          lineY -
          vscrollController.offset;

      final screenX =
          offset.dx +
          _gutterWidth +
          (innerPadding?.left ?? 0) -
          (lineWrap ? 0 : _effectiveHScroll);

      if (screenY + _lineHeight < offset.dy ||
          screenY > offset.dy + vscrollController.position.viewportDimension) {
        if (isLastLine) {
          lastGhostLineScreenY = screenY;
          lastGhostLineScreenX = screenX;
        }
        continue;
      }

      if (ghostLineText.isNotEmpty || isLastLine) {
        final builder =
            ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  fontFamily: textStyle?.fontFamily,
                  fontSize: textStyle?.fontSize ?? 14.0,
                  height: textStyle?.height ?? 1.2,
                ),
              )
              ..pushStyle(ghostStyle)
              ..addText(ghostLineText);

        final para = builder.build();
        para.layout(const ui.ParagraphConstraints(width: double.infinity));

        canvas.drawParagraph(para, Offset(screenX, screenY));

        if (isLastLine) {
          lastGhostLineWidth = para.longestLine;
          lastGhostLineScreenY = screenY;
          lastGhostLineScreenX = screenX;
        }
      }
    }

    if (multiClampedCol < lineText.length && ghostLines.length > 1) {
      final remainingText = lineText.substring(multiClampedCol);

      final normalStyle = ui.TextStyle(
        color: textStyle?.color ?? editorTheme['root']?.color ?? Colors.white,
        fontSize: textStyle?.fontSize ?? 14.0,
        fontFamily: textStyle?.fontFamily,
        fontWeight: textStyle?.fontWeight,
      );

      final remainingBuilder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: textStyle?.fontFamily,
                fontSize: textStyle?.fontSize ?? 14.0,
                height: textStyle?.height ?? 1.2,
              ),
            )
            ..pushStyle(normalStyle)
            ..addText(remainingText);

      final remainingPara = remainingBuilder.build();
      remainingPara.layout(
        const ui.ParagraphConstraints(width: double.infinity),
      );

      canvas.drawParagraph(
        remainingPara,
        Offset(lastGhostLineScreenX + lastGhostLineWidth, lastGhostLineScreenY),
      );
    }
  }

  void _drawInlayHints(
    Canvas canvas,
    Offset offset,
    int firstVisibleLine,
    int lastVisibleLine,
    double firstVisibleLineY,
    bool hasActiveFolds,
  ) {
    final hints = controller.inlayHints;
    if (hints.isEmpty) return;

    final fontSize = textStyle?.fontSize ?? 14.0;
    final fontFamily = textStyle?.fontFamily;
    final baseColor =
        textStyle?.color ?? editorTheme['root']?.color ?? Colors.white;
    final bgColor = editorTheme['root']?.backgroundColor ?? Colors.black;

    final typeHintStyle = ui.TextStyle(
      color: baseColor.withAlpha(150),
      fontSize: fontSize * 0.9,
      fontFamily: fontFamily,
      fontStyle: FontStyle.italic,
    );

    final paramHintStyle = ui.TextStyle(
      color: baseColor.withAlpha(180),
      fontSize: fontSize * 0.9,
      fontFamily: fontFamily,
    );

    final hintBgColor = bgColor.withAlpha(200);
    final hintBorderColor = baseColor.withAlpha(50);

    final hintsByLine = <int, List<InlayHint>>{};
    for (final hint in hints) {
      if (hint.line >= firstVisibleLine && hint.line <= lastVisibleLine) {
        if (!hasActiveFolds || !_isLineFolded(hint.line)) {
          hintsByLine.putIfAbsent(hint.line, () => []).add(hint);
        }
      }
    }

    hintsByLine.forEach((line, lineHints) {
      lineHints.sort((a, b) => a.column.compareTo(b.column));
    });

    for (final entry in hintsByLine.entries) {
      final line = entry.key;
      final lineHints = entry.value;
      final lineText = _lineTextCache[line] ?? controller.getLineText(line);
      final lineY = _getLineYOffset(line, hasActiveFolds);
      final para =
          _paragraphCache[line] ??
          _buildHighlightedParagraph(
            line,
            lineText,
            width: lineWrap ? _wrapWidth : null,
          );

      final baseScreenY =
          offset.dy +
          (innerPadding?.top ?? 0) +
          lineY -
          vscrollController.offset;

      final baseScreenX =
          offset.dx +
          _gutterWidth +
          (innerPadding?.left ?? 0) -
          (lineWrap ? 0 : _effectiveHScroll);

      final firstHint = lineHints.first;
      double firstHintX = 0;
      if (firstHint.column > 0 && lineText.isNotEmpty) {
        final boxes = para.getBoxesForRange(
          0,
          firstHint.column.clamp(0, lineText.length),
        );
        if (boxes.isNotEmpty) {
          firstHintX = boxes.last.right;
        }
      }

      double totalHintWidth = 0;
      for (final hint in lineHints) {
        final hintText = hint.paddingLeft ? ' ${hint.text}' : hint.text;
        final displayText = hint.paddingRight ? '$hintText ' : hintText;
        final builder =
            ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize * 0.9,
                  height: textStyle?.height ?? 1.2,
                ),
              )
              ..pushStyle(
                hint.kind == InlayHintKind.type
                    ? typeHintStyle
                    : paramHintStyle,
              )
              ..addText(displayText);
        final tempPara = builder.build();
        tempPara.layout(const ui.ParagraphConstraints(width: double.infinity));
        totalHintWidth += tempPara.longestLine + 4;
      }

      final remainingWidth = para.longestLine - firstHintX + totalHintWidth;
      canvas.drawRect(
        Rect.fromLTWH(
          baseScreenX + firstHintX,
          baseScreenY,
          remainingWidth + 20,
          _lineHeight,
        ),
        Paint()..color = bgColor,
      );

      double currentX = firstHintX;
      int lastColumn = firstHint.column;

      for (int i = 0; i < lineHints.length; i++) {
        final hint = lineHints[i];
        final column = hint.column;

        if (i > 0 && column > lastColumn && lastColumn < lineText.length) {
          final endCol = column.clamp(lastColumn, lineText.length);
          final segmentStartX =
              para.getBoxesForRange(0, lastColumn).lastOrNull?.right ?? 0;
          final segmentEndX =
              para.getBoxesForRange(0, endCol).lastOrNull?.right ??
              segmentStartX;
          final segmentWidth = segmentEndX - segmentStartX;

          canvas.save();
          canvas.clipRect(
            Rect.fromLTWH(
              baseScreenX + currentX,
              baseScreenY,
              segmentWidth,
              _lineHeight,
            ),
          );

          canvas.drawParagraph(
            para,
            Offset(baseScreenX + currentX - segmentStartX, baseScreenY),
          );
          canvas.restore();

          currentX += segmentWidth;
        }

        final style = hint.kind == InlayHintKind.type
            ? typeHintStyle
            : paramHintStyle;
        final hintText = hint.paddingLeft ? ' ${hint.text}' : hint.text;
        final displayText = hint.paddingRight ? '$hintText ' : hintText;

        final builder =
            ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize * 0.9,
                  height: textStyle?.height ?? 1.2,
                ),
              )
              ..pushStyle(style)
              ..addText(displayText);

        final hintPara = builder.build();
        hintPara.layout(const ui.ParagraphConstraints(width: double.infinity));
        final hintWidth = hintPara.longestLine;
        final hintHeight = hintPara.height;
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            baseScreenX + currentX - 2,
            baseScreenY + 1,
            hintWidth + 4,
            hintHeight - 2,
          ),
          const Radius.circular(3),
        );

        canvas.drawRRect(bgRect, Paint()..color = hintBgColor);
        canvas.drawRRect(
          bgRect,
          Paint()
            ..color = hintBorderColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5,
        );

        canvas.drawParagraph(
          hintPara,
          Offset(baseScreenX + currentX, baseScreenY),
        );
        currentX += hintWidth + 4;
        lastColumn = column;
      }

      if (lastColumn < lineText.length) {
        final remainingStartX =
            para.getBoxesForRange(0, lastColumn).lastOrNull?.right ?? 0;
        final remainingWidth = para.longestLine - remainingStartX;

        canvas.save();
        canvas.clipRect(
          Rect.fromLTWH(
            baseScreenX + currentX,
            baseScreenY,
            remainingWidth + 10,
            _lineHeight,
          ),
        );

        canvas.drawParagraph(
          para,
          Offset(baseScreenX + currentX - remainingStartX, baseScreenY),
        );
        canvas.restore();
      }
    }
  }

  void _drawDocumentColors(
    Canvas canvas,
    Offset offset,
    int firstVisibleLine,
    int lastVisibleLine,
    double firstVisibleLineY,
    bool hasActiveFolds,
  ) {
    final colors = controller.documentColors;
    if (colors.isEmpty) return;

    final fontSize = textStyle?.fontSize ?? 14.0;
    final colorBoxSize = fontSize * 0.85;
    final colorBoxSpacing = 4.0;
    final totalColorWidth = colorBoxSize + colorBoxSpacing;
    final bgColor = editorTheme['root']?.backgroundColor ?? Colors.black;
    final colorsByLine = <int, List<DocumentColor>>{};

    for (final docColor in colors) {
      if (docColor.line >= firstVisibleLine &&
          docColor.line <= lastVisibleLine) {
        if (!hasActiveFolds || !_isLineFolded(docColor.line)) {
          colorsByLine.putIfAbsent(docColor.line, () => []).add(docColor);
        }
      }
    }

    colorsByLine.forEach((line, lineColors) {
      lineColors.sort((a, b) => a.startColumn.compareTo(b.startColumn));
    });

    for (final entry in colorsByLine.entries) {
      final line = entry.key;
      final lineColors = entry.value;
      final lineText = _lineTextCache[line] ?? controller.getLineText(line);
      final lineY = _getLineYOffset(line, hasActiveFolds);
      final para =
          _paragraphCache[line] ??
          _buildHighlightedParagraph(
            line,
            lineText,
            width: lineWrap ? _wrapWidth : null,
          );

      final baseScreenY =
          offset.dy +
          (innerPadding?.top ?? 0) +
          lineY -
          vscrollController.offset;

      final baseScreenX =
          offset.dx +
          _gutterWidth +
          (innerPadding?.left ?? 0) -
          (lineWrap ? 0 : _effectiveHScroll);

      final firstColor = lineColors.first;
      double firstColorX = 0;
      if (firstColor.startColumn > 0 && lineText.isNotEmpty) {
        final boxes = para.getBoxesForRange(
          0,
          firstColor.startColumn.clamp(0, lineText.length),
        );
        if (boxes.isNotEmpty) {
          firstColorX = boxes.last.right;
        }
      }

      final totalColorBoxWidth = lineColors.length * totalColorWidth;
      final remainingWidth =
          para.longestLine - firstColorX + totalColorBoxWidth;

      canvas.drawRect(
        Rect.fromLTWH(
          baseScreenX + firstColorX,
          baseScreenY,
          remainingWidth + 20,
          _lineHeight,
        ),
        Paint()..color = bgColor,
      );

      double currentX = firstColorX;
      int lastColumn = firstColor.startColumn;

      for (int i = 0; i < lineColors.length; i++) {
        final docColor = lineColors[i];
        final startColumn = docColor.startColumn;

        if (i > 0 && startColumn > lastColumn && lastColumn < lineText.length) {
          final endCol = startColumn.clamp(lastColumn, lineText.length);
          final segmentStartX =
              para.getBoxesForRange(0, lastColumn).lastOrNull?.right ?? 0;
          final segmentEndX =
              para.getBoxesForRange(0, endCol).lastOrNull?.right ??
              segmentStartX;
          final segmentWidth = segmentEndX - segmentStartX;

          canvas.save();
          canvas.clipRect(
            Rect.fromLTWH(
              baseScreenX + currentX,
              baseScreenY,
              segmentWidth,
              _lineHeight,
            ),
          );

          canvas.drawParagraph(
            para,
            Offset(baseScreenX + currentX - segmentStartX, baseScreenY),
          );
          canvas.restore();

          currentX += segmentWidth;
        }

        final colorBoxY = baseScreenY + (_lineHeight - colorBoxSize) / 2;
        final colorRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            baseScreenX + currentX,
            colorBoxY,
            colorBoxSize,
            colorBoxSize,
          ),
          const Radius.circular(2),
        );

        if ((docColor.color.a * 255).round() < 255) {
          canvas.save();
          canvas.clipRRect(colorRect);
          final checkerSize = colorBoxSize / 4;
          final checkerPaint = Paint()..color = Colors.grey.shade300;
          for (int row = 0; row < 4; row++) {
            for (int col = 0; col < 4; col++) {
              if ((row + col) % 2 == 0) {
                canvas.drawRect(
                  Rect.fromLTWH(
                    baseScreenX + currentX + col * checkerSize,
                    colorBoxY + row * checkerSize,
                    checkerSize,
                    checkerSize,
                  ),
                  checkerPaint,
                );
              }
            }
          }
          canvas.restore();
        }

        canvas.drawRRect(colorRect, Paint()..color = docColor.color);

        final borderColor = editorTheme['root']?.color ?? Colors.white;
        canvas.drawRRect(
          colorRect,
          Paint()
            ..color = borderColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );

        _colorBoxHitAreas[colorRect.outerRect] = docColor;

        currentX += totalColorWidth;
        lastColumn = startColumn;
      }

      if (lastColumn < lineText.length) {
        final remainingStartX =
            para.getBoxesForRange(0, lastColumn).lastOrNull?.right ?? 0;
        final remainingWidth = para.longestLine - remainingStartX;

        canvas.save();
        canvas.clipRect(
          Rect.fromLTWH(
            baseScreenX + currentX,
            baseScreenY,
            remainingWidth + 10,
            _lineHeight,
          ),
        );

        canvas.drawParagraph(
          para,
          Offset(baseScreenX + currentX - remainingStartX, baseScreenY),
        );
        canvas.restore();
      }
    }
  }

  void _showColorPicker(DocumentColor docColor) {
    final lsp = lspConfig;
    final file = filePath;
    if (lsp == null || file == null) return;

    Color pickerColor = docColor.color;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Pick a color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (color) {
                pickerColor = color;
              },
              enableAlpha: true,
              displayThumbColor: true,
              pickerAreaHeightPercent: 0.8,
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Apply'),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _applyColorChange(docColor, pickerColor);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _applyColorChange(DocumentColor docColor, Color newColor) async {
    final lsp = lspConfig;
    final file = filePath;
    if (lsp == null || file == null) return;

    try {
      final range = {
        'start': {'line': docColor.line, 'character': docColor.startColumn},
        'end': {'line': docColor.line, 'character': docColor.endColumn},
      };

      final response = await lsp.getColorPresentation(
        file,
        red: newColor.r,
        green: newColor.g,
        blue: newColor.b,
        alpha: newColor.a,
        range: range,
      );

      final result = response['result'];
      if (result is List && result.isNotEmpty) {
        final presentation = result[0];
        final textEdit = presentation['textEdit'];

        if (textEdit != null) {
          final newText = textEdit['newText'] as String?;
          final editRange = textEdit['range'];

          if (newText != null && editRange != null) {
            final startLine = editRange['start']['line'] as int;
            final startChar = editRange['start']['character'] as int;
            final endLine = editRange['end']['line'] as int;
            final endChar = editRange['end']['character'] as int;

            final startOffset =
                controller.getLineStartOffset(startLine) + startChar;
            final endOffset = controller.getLineStartOffset(endLine) + endChar;

            controller.replaceRange(startOffset, endOffset, newText);
          }
        } else {
          final label = presentation['label'] as String?;
          if (label != null) {
            final startOffset =
                controller.getLineStartOffset(docColor.line) +
                docColor.startColumn;
            final endOffset =
                controller.getLineStartOffset(docColor.line) +
                docColor.endColumn;

            controller.replaceRange(startOffset, endOffset, label);
          }
        }
      }
    } catch (e) {
      debugPrint('Error applying color change: $e');
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChange);
    controller.setScrollCallback(null);
    _syntaxHighlighter.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    final localPosition = event.localPosition;
    final clickY =
        localPosition.dy + vscrollController.offset - (innerPadding?.top ?? 0);
    _currentPosition = localPosition;

    final contentX = isRTL
        ? localPosition.dx -
              (innerPadding?.left ?? 0) -
              (lineWrap ? 0 : _effectiveHScroll)
        : localPosition.dx -
              _gutterWidth -
              (innerPadding?.left ?? 0) +
              (lineWrap ? 0 : _effectiveHScroll);
    final contentPosition = Offset(
      contentX,
      localPosition.dy - (innerPadding?.top ?? 0) + vscrollController.offset,
    );
    final textOffset = _getTextOffsetFromPosition(contentPosition);

    if (event is PointerHoverEvent) {
      if (hoverNotifier.value == null) {
        _hoverTimer?.cancel();
      }
      if (!(hoverNotifier.value != null && isHoveringPopup.value)) {
        hoverNotifier.value = null;
      }

      if ((hoverNotifier.value == null || !isHoveringPopup.value) &&
          _isOffsetOverWord(textOffset)) {
        _hoverTimer?.cancel();
        _hoverTimer = Timer(Duration(milliseconds: 1500), () {
          final lineChar = _offsetToLineChar(textOffset);
          hoverNotifier.value = (event.localPosition, lineChar);
        });
      } else {
        _hoverTimer?.cancel();
        hoverNotifier.value = null;
      }
    }

    if ((event is PointerDownEvent && event.buttons == kSecondaryButton) ||
        (event is PointerUpEvent &&
            isMobile &&
            _selectionActive &&
            controller.selection.start != controller.selection.end)) {
      _draggingStartHandle = false;
      _draggingEndHandle = false;
      _draggingCHandle = false;
      _isDragging = false;
      _cachedSelectionMagnifierParagraphs = null;
      _cachedSelectionMagnifierStartLine = null;
      _cachedSelectionMagnifierEndLine = null;
      _cachedMagnifiedParagraph = null;
      _cachedMagnifiedLine = null;
      _cachedMagnifiedOffset = null;

      contextMenuOffsetNotifier.value = localPosition;
      markNeedsPaint();
      return;
    }

    if (event is PointerDownEvent && event.buttons == kPrimaryButton) {
      try {
        focusNode.requestFocus();
        suggestionNotifier.value = null;
        signatureNotifier.value = null;
      } catch (e) {
        debugPrint(e.toString());
      }
      if (contextMenuOffsetNotifier.value.dx >= 0) {
        contextMenuOffsetNotifier.value = const Offset(-1, -1);
      }

      if (lspActionNotifier.value != null && _actionBulbRects.isNotEmpty) {
        for (final entry in _actionBulbRects.entries) {
          if (entry.value.contains(localPosition)) {
            suggestionNotifier.value = null;
            lspActionOffsetNotifier.value = event.localPosition;
            return;
          }
        }
      }

      if (_colorBoxHitAreas.isNotEmpty) {
        for (final entry in _colorBoxHitAreas.entries) {
          if (entry.key.contains(localPosition)) {
            _showColorPicker(entry.value);
            return;
          }
        }
      }

      final gutterClickArea = isRTL
          ? localPosition.dx > size.width - _gutterWidth
          : localPosition.dx < _gutterWidth;

      if (enableFolding && enableGutter && gutterClickArea) {
        if (clickY < 0) return;
        final clickedLine = _findVisibleLineByYPosition(clickY);

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

        _dtap.onDoubleTap = () {
          _selectWordAtOffset(textOffset);
          contextMenuOffsetNotifier.value = localPosition;
        };

        _onetap.onTap = () {
          if (hoverNotifier.value != null && !isHoveringPopup.value) {
            hoverNotifier.value = null;
            hoverContentNotifier.value = null;
          } else if (_isOffsetOverWord(textOffset)) {
            final lineChar = _offsetToLineChar(textOffset);
            hoverNotifier.value = (localPosition, lineChar);
            onHoverSetByTap?.call();
          }

          if (lspActionNotifier.value != null ||
              lspActionOffsetNotifier.value != null) {
            lspActionNotifier.value = null;
            lspActionOffsetNotifier.value = null;
          }
        };

        if (controller.selection.start != controller.selection.end) {
          if (_startHandleRect?.contains(localPosition) ?? false) {
            _draggingStartHandle = true;
            _selectionActive = selectionActiveNotifier.value = true;
            _pointerDownPosition = localPosition;
            _dragStartOffset = controller.selection.start;
            markNeedsPaint();
            return;
          }
          if (_endHandleRect?.contains(localPosition) ?? false) {
            _draggingEndHandle = true;
            _selectionActive = selectionActiveNotifier.value = true;
            _pointerDownPosition = localPosition;
            _dragStartOffset = controller.selection.end;
            markNeedsPaint();
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
        _dtap.addPointer(event);
        _dtap.onDoubleTap = () {
          _selectWordAtOffset(textOffset);
        };

        _dragStartOffset = textOffset;
        _onetap.onTap = () {
          if (suggestionNotifier.value != null) {
            suggestionNotifier.value = null;
          }
          if (signatureNotifier.value != null) {
            signatureNotifier.value = null;
          }
          if (lspActionNotifier.value != null) {
            lspActionNotifier.value = null;
            lspActionOffsetNotifier.value = null;
          }
        };
        controller.selection = TextSelection.collapsed(offset: textOffset);
      }
    }

    if (event is PointerMoveEvent && _dragStartOffset != null) {
      if (isMobile) {
        if (_draggingCHandle) {
          final handleRadius = (_lineHeight / 2).clamp(6.0, 12.0);
          final handleOffset = _lineHeight + handleRadius;
          final adjustedContentPosition = Offset(
            contentPosition.dx,
            contentPosition.dy - handleOffset,
          );
          final adjustedTextOffset = _getTextOffsetFromPosition(
            adjustedContentPosition,
          );
          controller.selection = TextSelection.collapsed(
            offset: adjustedTextOffset,
          );
          _showBubble = true;
          markNeedsLayout();
          markNeedsPaint();
          return;
        }

        if (_draggingStartHandle || _draggingEndHandle) {
          final handleRadius = (_lineHeight / 2).clamp(6.0, 12.0);
          final handleOffset = _lineHeight + handleRadius;
          final adjustedContentPosition = Offset(
            contentPosition.dx,
            contentPosition.dy - handleOffset,
          );
          final adjustedTextOffset = _getTextOffsetFromPosition(
            adjustedContentPosition,
          );
          final base = controller.selection.start;
          final extent = controller.selection.end;

          if (_draggingStartHandle) {
            controller.selection = TextSelection(
              baseOffset: adjustedTextOffset,
              extentOffset: extent,
            );
            if (adjustedTextOffset > extent) {
              _draggingStartHandle = false;
              _draggingEndHandle = true;
            }
          } else {
            controller.selection = TextSelection(
              baseOffset: base,
              extentOffset: adjustedTextOffset,
            );
            if (adjustedTextOffset < base) {
              _draggingEndHandle = false;
              _draggingStartHandle = true;
            }
          }
          markNeedsLayout();
          markNeedsPaint();
          return;
        }

        if ((localPosition - (_pointerDownPosition ?? localPosition)).distance >
            10) {
          _isDragging = true;
          suggestionNotifier.value = null;

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
          markNeedsPaint();
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
        controller.connection?.show();
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
      _cachedSelectionMagnifierParagraphs = null;
      _cachedSelectionMagnifierStartLine = null;
      _cachedSelectionMagnifierEndLine = null;

      final wasDragging = _isDragging;
      _isDragging = false;
      _selectionActive = selectionActiveNotifier.value = false;

      markNeedsPaint();

      if (readOnly) return;
      if (!wasDragging) {
        controller.notifyListeners();
      }

      if (isMobile && controller.selection.isCollapsed) {
        _showBubble = true;
      }
    }
  }

  void _selectWordAtOffset(int offset) {
    if (isMobile) {
      _selectionActive = selectionActiveNotifier.value = true;
    }

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
    return char.trim().isEmpty || !RegExp(_wordCharPattern).hasMatch(char);
  }

  bool _isOffsetOverWord(int offset) {
    final text = controller.text;
    if (offset < 0 || offset >= text.length) return false;
    return RegExp(_wordCharPattern).hasMatch(text[offset]);
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
    final isInGutter = isRTL
        ? _currentPosition.dx > size.width - _gutterWidth
        : _currentPosition.dx >= 0 && _currentPosition.dx < _gutterWidth;

    if (isInGutter) {
      if (_foldRanges.isEmpty && !enableFolding) {
        return MouseCursor.defer;
      }

      final clickY =
          _currentPosition.dy +
          vscrollController.offset -
          (innerPadding?.top ?? 0);
      final hasActiveFolds = _foldRanges.values.any(
        (f) => f != null && f.isFolded,
      );

      int hoveredLine;
      if (!hasActiveFolds && !lineWrap) {
        hoveredLine = (clickY / _lineHeight).floor().clamp(
          0,
          controller.lineCount - 1,
        );
      } else {
        hoveredLine = _findVisibleLineByYPosition(clickY);
      }

      final foldRange = _getFoldRangeAtLine(hoveredLine);
      if (foldRange != null) {
        return SystemMouseCursors.click;
      }

      if (_actionBulbRects.isNotEmpty) {
        for (final rect in _actionBulbRects.values) {
          if (rect.contains(_currentPosition)) {
            return SystemMouseCursors.click;
          }
        }
      }

      return MouseCursor.defer;
    }

    if (_colorBoxHitAreas.isNotEmpty) {
      for (final rect in _colorBoxHitAreas.keys) {
        if (rect.contains(_currentPosition)) {
          return SystemMouseCursors.click;
        }
      }
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

/// Represents a foldable code region in the editor.
///
/// A fold range defines a region of code that can be collapsed (folded) to hide
/// its contents. This is typically used for code blocks like functions, classes,
/// or control structures.
///
/// Fold ranges are automatically detected based on code structure (braces,
/// indentation) when folding is enabled in the editor.
///
/// Example:
/// ```dart
/// // A fold range from line 5 to line 10
/// final foldRange = FoldRange(5, 10);
/// foldRange.isFolded = true; // Collapse the region
/// ```
class FoldRange {
  /// The starting line index (zero-based) of the fold range.
  ///
  /// This is the line where the fold indicator appears in the gutter.
  final int startIndex;

  /// The ending line index (zero-based) of the fold range.
  ///
  /// When folded, all lines from `startIndex + 1` to `endIndex` are hidden.
  final int endIndex;

  /// Whether this fold range is currently collapsed.
  ///
  /// When true, the contents of this range are hidden in the editor.
  bool isFolded = false;

  /// Child fold ranges that were originally folded when this range was unfolded.
  ///
  /// Used to restore the fold state of nested ranges when toggling folds.
  List<FoldRange> originallyFoldedChildren = [];

  /// Creates a [FoldRange] with the specified start and end line indices.
  FoldRange(this.startIndex, this.endIndex);

  /// Adds a child fold range that was originally folded.
  ///
  /// Used internally to track nested fold states.
  void addOriginallyFoldedChild(FoldRange child) {
    if (!originallyFoldedChildren.contains(child)) {
      originallyFoldedChildren.add(child);
    }
  }

  /// Clears the list of originally folded children.
  void clearOriginallyFoldedChildren() {
    originallyFoldedChildren.clear();
  }

  /// Checks if a line is contained within this fold range.
  ///
  /// Returns true if [line] is strictly greater than [startIndex] and
  /// less than or equal to [endIndex].
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

/// Custom scroll physics that reverses horizontal drag direction for RTL mode on mobile.
class RTLAwareScrollPhysics extends ClampingScrollPhysics {
  final bool isRTL;
  final bool isMobile;

  const RTLAwareScrollPhysics({
    super.parent,
    required this.isRTL,
    required this.isMobile,
  });

  @override
  RTLAwareScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return RTLAwareScrollPhysics(
      parent: buildParent(ancestor),
      isRTL: isRTL,
      isMobile: isMobile,
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (isRTL && isMobile && position.axis == Axis.horizontal) {
      return super.applyPhysicsToUserOffset(position, -offset);
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (isRTL && isMobile && position.axis == Axis.horizontal) {
      return super.createBallisticSimulation(position, -velocity);
    }
    return super.createBallisticSimulation(position, velocity);
  }
}
