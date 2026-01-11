import 'package:flutter/material.dart';

/// This class provides styling options for code selection in the code editor.
class CodeSelectionStyle {
  /// The color of the cursor line, defaults to the highlight theme text color.
  final Color? cursorColor;

  /// The color used to highlight selected text in the code editor.
  final Color selectionColor;

  /// The color of the cursor bubble that appears when selecting text.
  final Color cursorBubbleColor;

  CodeSelectionStyle({
    this.cursorColor,
    this.selectionColor = const Color(0x6E2195F3),
    this.cursorBubbleColor = Colors.blue,
  });
}

/// This class provides styling options for the Gutter.
class GutterStyle {
  /// The style for line numbers in the gutter. Expected to be a [TextStyle].
  final TextStyle? lineNumberStyle;

  /// The background color of the gutter bar.
  final Color? backgroundColor;

  /// The color for the folded line folding indicator icon in the gutter. Defaults to [Colors.grey].
  final Color? foldedIconColor;

  /// The color for the unfolded line folding indicator icon in the gutter. Defaults to [Colors.grey].
  final Color? unfoldedIconColor;

  /// The width of the gutter. Dynamic by default, which means it can adapt best width based on line number. So recommended to leave it null.
  final double? gutterWidth;

  /// The size of the folding icon in the gutter. Defaults to (widget?.textStyle?.fontSize ?? 14) * 1.2.
  ///
  /// /// Recommended to leave it null, because the default value is dynamic based on editor fontSize.
  final double? foldingIconSize;

  /// The icon used for the folded line folding indicator in the gutter.
  ///
  /// Defaults to [Icons.chevron_right_outlined] for folded lines.
  final IconData unfoldedIcon;

  /// The icon used for the unfolded line folding indicator in the gutter.
  ///
  /// Defaults to [Icons.keyboard_arrow_down_outlined] for unfolded lines.
  final IconData foldedIcon;

  /// The color used to highlight the current line number in the gutter.
  /// If null, the line number will use the default text color.
  final Color? activeLineNumberColor;

  /// The color used for non-active line numbers in the gutter.
  /// If null, defaults to a dimmed version of the text color.
  final Color? inactiveLineNumberColor;

  /// The color used to highlight line numbers with errors (severity 1).
  /// Defaults to red.
  final Color errorLineNumberColor;

  /// The color used to highlight line numbers with warnings (severity 2).
  /// Defaults to yellow/orange.
  final Color warningLineNumberColor;

  /// The background color used to highlight folded line start.
  /// If null, a low opacity version of the selection color is used.
  final Color? foldedLineHighlightColor;

  GutterStyle({
    this.lineNumberStyle,
    this.backgroundColor,
    this.gutterWidth,
    this.foldedIcon = Icons.chevron_right_outlined,
    this.unfoldedIcon = Icons.keyboard_arrow_down_outlined,
    this.foldingIconSize,
    this.foldedIconColor,
    this.unfoldedIconColor,
    this.activeLineNumberColor,
    this.inactiveLineNumberColor,
    this.errorLineNumberColor = const Color(0xFFE53935),
    this.warningLineNumberColor = const Color(0xFFFFA726),
    this.foldedLineHighlightColor,
  });
}

/// Base class for overlay styling options used in various popup elements.
///
/// This sealed class provides common styling options for overlays such as
/// suggestion popups and hover details. Extend this class to create specific
/// overlay styles.
sealed class OverlayStyle {
  /// The elevation of the overlay, which determines the shadow depth.
  /// Defaults to 6.
  final double elevation;

  /// The background color of the overlay.
  final Color backgroundColor;

  /// The color used when the overlay is focused.
  final Color focusColor;

  /// The color used when the overlay is hovered.
  final Color hoverColor;

  /// The color used for the splash effect when the overlay is tapped.
  final Color splashColor;

  /// The shape of the overlay, which defines its border and corner radius.
  /// This can be a [ShapeBorder] such as [RoundedRectangleBorder], [CircleBorder], etc.
  final ShapeBorder shape;

  /// The text style used for the text in the overlay.
  /// This is typically a [TextStyle] that defines the font size, weight, color, etc.
  final TextStyle textStyle;
  OverlayStyle({
    this.elevation = 6,
    required this.shape,
    required this.backgroundColor,
    required this.focusColor,
    required this.hoverColor,
    required this.splashColor,
    required this.textStyle,
  });
}

/// Styling options for the code completion suggestion popup.
///
/// This class extends [OverlayStyle] to provide specific styling for the
/// autocomplete suggestion list that appears while typing in the editor.
///
/// Example:
/// ```dart
/// SuggestionStyle(
///   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
///   backgroundColor: Colors.grey[900]!,
///   focusColor: Colors.blue.withOpacity(0.3),
///   hoverColor: Colors.blue.withOpacity(0.1),
///   splashColor: Colors.blue.withOpacity(0.2),
///   textStyle: TextStyle(color: Colors.white),
/// )
/// ```
class SuggestionStyle extends OverlayStyle {
  /// Creates a [SuggestionStyle] with the specified options.
  SuggestionStyle({
    super.elevation,
    required super.shape,
    required super.backgroundColor,
    required super.focusColor,
    required super.hoverColor,
    required super.splashColor,
    required super.textStyle,
  });
}

/// Styling options for the hover details popup.
///
/// This class extends [OverlayStyle] to provide specific styling for the
/// popup that shows documentation or type information when hovering over
/// code elements (requires LSP integration).
///
/// Example:
/// ```dart
/// HoverDetailsStyle(
///   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
///   backgroundColor: Colors.grey[850]!,
///   focusColor: Colors.blue.withOpacity(0.3),
///   hoverColor: Colors.blue.withOpacity(0.1),
///   splashColor: Colors.blue.withOpacity(0.2),
///   textStyle: TextStyle(color: Colors.white),
/// )
/// ```
class HoverDetailsStyle extends OverlayStyle {
  /// Creates a [HoverDetailsStyle] with the specified options.
  HoverDetailsStyle({
    super.elevation,
    required super.shape,
    required super.backgroundColor,
    required super.focusColor,
    required super.hoverColor,
    required super.splashColor,
    required super.textStyle,
  });
}

/// Represents a highlighted search result in the editor
class SearchHighlight {
  /// The start offset of the highlighted text
  final int start;

  /// The end offset of the highlighted text
  final int end;

  /// Whether this highlight represents the currently selected match
  final bool isCurrentMatch;

  const SearchHighlight({
    required this.start,
    required this.end,
    this.isCurrentMatch = false,
  });
}

/// Styles used to highlight occurrences found by the controller.findWord() API.
///
/// Provides separate TextStyle values for the currently selected match and for
/// all other matches, so the active match can be visually emphasized while
/// keeping other matches visible.
///
/// Fields:
/// - currentMatchStyle: TextStyle applied to the currently selected/active
///   match. Use this to draw attention to the match the user is navigating to.
/// - otherMatchStyle: TextStyle applied to all non-active matches. Typically
///   a subtler style than the currentMatchStyle (for example a translucent
///   background color).
///
/// Usage example:
/// ```dart
/// matchHighlightStyle: const MatchHighlightStyle(
///   currentMatchStyle: TextStyle(
///     backgroundColor: Color(0xFFFFA726),
///   ),
///   otherMatchStyle: TextStyle(
///     backgroundColor: Color(0x55FFFF00),
///   ),
/// ),
/// ```
///
/// Notes:
/// - Prefer using const constructors and const TextStyle values where possible
///   to improve performance.
/// - The exact visual result depends on how the editor widget composes the
///   TextStyle with surrounding styles; typically only the differing properties
///   (for example backgroundColor) will have a visible effect.
class MatchHighlightStyle {
  /// Style for the currently selected match.
  final TextStyle currentMatchStyle;

  /// Style for all other matches.
  final TextStyle otherMatchStyle;

  const MatchHighlightStyle({
    required this.currentMatchStyle,
    required this.otherMatchStyle,
  });
}

/// Defines decoration types for line decorations in the editor.
///
/// Used to specify how a line range should be visually decorated,
/// such as for git diff highlighting, bookmarks, or custom markers.
enum LineDecorationType {
  /// Full line background highlight
  background,

  /// Left border/bar indicator (like git diff added/removed)
  leftBorder,

  /// Underline decoration
  underline,

  /// Wavy underline (like error indicators)
  wavyUnderline,
}

/// Represents a decoration applied to a range of lines in the editor.
///
/// Line decorations can be used to highlight code changes (git diff),
/// mark breakpoints, show coverage information, or any custom highlighting.
///
/// Example - Git diff added lines:
/// ```dart
/// controller.addLineDecoration(LineDecoration(
///   startLine: 10,
///   endLine: 15,
///   type: LineDecorationType.background,
///   color: Colors.green.withOpacity(0.2),
/// ));
/// ```
///
/// Example - Git diff left border:
/// ```dart
/// controller.addLineDecoration(LineDecoration(
///   startLine: 10,
///   endLine: 15,
///   type: LineDecorationType.leftBorder,
///   color: Colors.green,
///   thickness: 3,
/// ));
/// ```
class LineDecoration {
  /// Unique identifier for this decoration
  final String id;

  /// The start line (0-based) of the decoration range
  final int startLine;

  /// The end line (0-based, inclusive) of the decoration range
  final int endLine;

  /// The type of decoration to apply
  final LineDecorationType type;

  /// The color of the decoration
  final Color color;

  /// Thickness for border/underline decorations (default: 3.0)
  final double thickness;

  /// Optional priority for overlapping decorations (higher = on top)
  final int priority;

  /// Creates a line decoration.
  ///
  /// [id] - Unique identifier for managing the decoration
  /// [startLine] - First line to decorate (0-based)
  /// [endLine] - Last line to decorate (0-based, inclusive)
  /// [type] - The decoration style to apply
  /// [color] - Color of the decoration
  /// [thickness] - Width for border/underline decorations
  /// [priority] - Z-order for overlapping decorations
  const LineDecoration({
    required this.id,
    required this.startLine,
    required this.endLine,
    required this.type,
    required this.color,
    this.thickness = 3.0,
    this.priority = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineDecoration &&
          id == other.id &&
          startLine == other.startLine &&
          endLine == other.endLine;

  @override
  int get hashCode => Object.hash(id, startLine, endLine);
}

/// Defines decoration types for gutter decorations.
enum GutterDecorationType {
  /// Colored bar/stripe in the gutter
  colorBar,

  /// Custom icon in the gutter
  icon,

  /// Dot/circle indicator
  dot,
}

/// Represents a decoration in the gutter area (line numbers column).
///
/// Gutter decorations are useful for showing git diff status,
/// breakpoints, bookmarks, or other line-level indicators.
///
/// Example - Git diff added indicator:
/// ```dart
/// controller.addGutterDecoration(GutterDecoration(
///   startLine: 10,
///   endLine: 15,
///   type: GutterDecorationType.colorBar,
///   color: Colors.green,
/// ));
/// ```
///
/// Example - Breakpoint icon:
/// ```dart
/// controller.addGutterDecoration(GutterDecoration(
///   startLine: 25,
///   endLine: 25,
///   type: GutterDecorationType.icon,
///   color: Colors.red,
///   icon: Icons.circle,
/// ));
/// ```
class GutterDecoration {
  /// Unique identifier for this decoration
  final String id;

  /// The start line (0-based) of the decoration range
  final int startLine;

  /// The end line (0-based, inclusive) of the decoration range
  final int endLine;

  /// The type of gutter decoration
  final GutterDecorationType type;

  /// The color of the decoration
  final Color color;

  /// Icon to display (only used when type is [GutterDecorationType.icon])
  final IconData? icon;

  /// Width of the color bar (default: 3.0)
  final double width;

  /// Optional tooltip text shown on hover
  final String? tooltip;

  /// Optional priority for overlapping decorations (higher = on top)
  final int priority;

  /// Creates a gutter decoration.
  const GutterDecoration({
    required this.id,
    required this.startLine,
    required this.endLine,
    required this.type,
    required this.color,
    this.icon,
    this.width = 3.0,
    this.tooltip,
    this.priority = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GutterDecoration &&
          id == other.id &&
          startLine == other.startLine &&
          endLine == other.endLine;

  @override
  int get hashCode => Object.hash(id, startLine, endLine);
}

/// Represents ghost text (inline suggestion) displayed in the editor.
///
/// Ghost text appears as semi-transparent text at the cursor position,
/// typically used for AI code completion suggestions.
///
/// When [shouldPersist] is false (default), the ghost text will be:
/// - Cleared when the cursor moves or text changes don't match
/// - Accepted (inserted) when Tab or Right Arrow is pressed
///
/// When [shouldPersist] is true, the ghost text will only be cleared
/// by explicitly calling [CodeForgeController.clearGhostText].
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
class GhostText {
  /// The line where the ghost text starts (0-based)
  final int line;

  /// The column where the ghost text starts (0-based)
  final int column;

  /// The ghost text content (can be multi-line with \n)
  final String text;

  /// Text style for the ghost text
  final TextStyle? style;

  /// Whether the ghost text should persist until explicitly cleared.
  ///
  /// When false (default), the ghost text will be cleared on cursor
  /// movement or mismatched typing, and accepted on Tab/Right Arrow.
  /// When true, the ghost text can only be cleared by calling
  /// [CodeForgeController.clearGhostText].
  final bool shouldPersist;

  /// Creates a ghost text decoration.
  ///
  /// [line] - The line number where text appears (0-based)
  /// [column] - The column position where text starts (0-based)
  /// [text] - The suggestion text to display
  /// [style] - Optional custom style (defaults to semi-transparent italic)
  /// [shouldPersist] - If true, only cleared by clearGhostText(); if false,
  ///   cleared on cursor movement and accepted on Tab/Right Arrow
  const GhostText({
    required this.line,
    required this.column,
    required this.text,
    this.style,
    this.shouldPersist = false,
  });
}
