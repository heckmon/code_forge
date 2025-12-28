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
