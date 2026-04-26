import 'package:flutter/services.dart';

import 'controller.dart';
import 'undo_redo.dart';

/// Unicode-aware word character class used for word-boundary navigation.
const String wordCharPattern = r'[\w\u0600-\u06FF\u08A0-\u08FF\u0590-\u05FF]';

/// Pure editing commands that can be tested without a widget tree.
///
/// This class encapsulates the mapping from keyboard shortcuts to controller
/// operations. It is instantiated by `_CodeForgeState` and also by test code.
class CodeForgeCommands {
  CodeForgeCommands({
    required this.controller,
    required this.undoRedoController,
    this.readOnly = false,
    this.textDirection = TextDirection.ltr,
    this.onPostCommand,
  });

  final CodeForgeController controller;
  final UndoRedoController undoRedoController;

  /// Whether the editor is in read-only mode. Updated by the owning widget.
  bool readOnly;

  /// Text direction — affects which physical arrow maps to which logical
  /// direction.
  TextDirection textDirection;

  /// Called after each command executes. In the widget this calls
  /// `_commonKeyFunctions()` to clear ghost text, reset cursor blink, etc.
  /// In tests this can be null or a no-op.
  final void Function()? onPostCommand;

  // ---------------------------------------------------------------------------
  // Text editing
  // ---------------------------------------------------------------------------

  void copy() {
    controller.copy();
  }

  void cut() {
    if (readOnly) return;
    controller.cut();
  }

  void paste() {
    if (readOnly) return;
    controller.paste();
  }

  void selectAll() {
    controller.selectAll();
  }

  void backspace() {
    if (readOnly) return;
    controller.backspace();
  }

  void delete() {
    if (readOnly) return;
    controller.delete();
  }

  void indent() {
    if (readOnly) return;
    controller.indent();
  }

  void unindent() {
    if (readOnly) return;
    controller.unindent();
  }

  void undo() {
    if (readOnly) return;
    if (undoRedoController.canUndo) {
      undoRedoController.undo();
    }
  }

  void redo() {
    if (readOnly) return;
    if (undoRedoController.canRedo) {
      undoRedoController.redo();
    }
  }

  void deleteWordBackward() {
    if (readOnly) return;
    final selection = controller.selection;
    final text = controller.text;

    if (!selection.isCollapsed) {
      controller.replaceRange(selection.start, selection.end, '');
      return;
    }

    int caret = selection.extentOffset;
    if (caret <= 0) return;

    final prevChar = text[caret - 1];
    if (prevChar == '\n') {
      controller.replaceRange(caret - 1, caret, '');
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

    controller.replaceRange(deleteFrom, caret, '');
  }

  void deleteWordForward() {
    if (readOnly) return;
    final selection = controller.selection;
    final text = controller.text;

    if (!selection.isCollapsed) {
      controller.replaceRange(selection.start, selection.end, '');
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

    controller.replaceRange(caret, deleteTo, '');
  }

  // ---------------------------------------------------------------------------
  // Cursor movement
  // ---------------------------------------------------------------------------

  void moveCursorUp({bool select = false}) {
    controller.pressUpArrowKey(isShiftPressed: select);
  }

  void moveCursorDown({bool select = false}) {
    controller.pressDownArrowKey(isShiftPressed: select);
  }

  /// Move cursor left one character (respects [textDirection]).
  void moveCursorLeft({bool select = false}) {
    if (textDirection == TextDirection.rtl) {
      _moveSelectionRight(select);
    } else {
      controller.pressLetfArrowKey(isShiftPressed: select);
    }
  }

  /// Move cursor right one character (respects [textDirection]).
  void moveCursorRight({bool select = false}) {
    if (textDirection == TextDirection.rtl) {
      controller.pressLetfArrowKey(isShiftPressed: select);
    } else {
      _moveSelectionRight(select);
    }
  }

  void _moveSelectionRight(bool withShift) {
    final sel = controller.selection;
    final textLength = controller.length;

    int newOffset;
    if (!withShift && sel.start != sel.end) {
      newOffset = sel.end;
    } else if (sel.extentOffset < textLength) {
      newOffset = sel.extentOffset + 1;
    } else {
      newOffset = textLength;
    }

    if (withShift) {
      controller.setSelectionSilently(
        TextSelection(baseOffset: sel.baseOffset, extentOffset: newOffset),
      );
    } else {
      controller.setSelectionSilently(
        TextSelection.collapsed(offset: newOffset),
      );
    }
  }

  void moveHome({bool select = false}) {
    controller.pressHomeKey(isShiftPressed: select);
  }

  void moveEnd({bool select = false}) {
    controller.pressEndKey(isShiftPressed: select);
  }

  void moveDocumentHome({bool select = false}) {
    controller.pressDocumentHomeKey(isShiftPressed: select);
  }

  void moveDocumentEnd({bool select = false}) {
    controller.pressDocumentEnd(isShiftPressed: select);
  }

  void moveWordLeft({bool select = false}) {
    final selection = controller.selection;
    final text = controller.text;
    int caret = selection.extentOffset;

    if (caret <= 0) return;

    final prevNewline = text.lastIndexOf('\n', caret - 1);
    final lineStart = prevNewline == -1 ? 0 : prevNewline + 1;
    if (caret == lineStart && lineStart > 0) {
      final newOffset = lineStart - 1;
      controller.setSelectionSilently(
        select
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
      '$wordCharPattern+|[^$wordCharPattern\\s]+',
    ).allMatches(lineText).toList();

    int newOffset = lineStart;
    for (final match in wordMatches) {
      newOffset = lineStart + match.start;
      if (match.end >= lineText.length) break;
    }

    controller.setSelectionSilently(
      select
          ? TextSelection(
              baseOffset: selection.baseOffset,
              extentOffset: newOffset,
            )
          : TextSelection.collapsed(offset: newOffset),
    );
  }

  void moveWordRight({bool select = false}) {
    final selection = controller.selection;
    final text = controller.text;
    int caret = selection.extentOffset;

    if (caret >= text.length) return;

    if (caret < text.length && text[caret] == '\n') {
      final newOffset = caret + 1;
      controller.setSelectionSilently(
        select
            ? TextSelection(
                baseOffset: selection.baseOffset,
                extentOffset: newOffset,
              )
            : TextSelection.collapsed(offset: newOffset),
      );
      return;
    }

    final regex = RegExp('$wordCharPattern+|[^$wordCharPattern\\s]+|\\s+');
    final matches = regex.allMatches(text, caret);

    int newOffset = caret;
    for (final match in matches) {
      if (match.start > caret) {
        newOffset = match.start;
        break;
      }
    }
    if (newOffset == caret) newOffset = text.length;

    controller.setSelectionSilently(
      select
          ? TextSelection(
              baseOffset: selection.baseOffset,
              extentOffset: newOffset,
            )
          : TextSelection.collapsed(offset: newOffset),
    );
  }

  // ---------------------------------------------------------------------------
  // Multi-cursor
  // ---------------------------------------------------------------------------

  void insertCursorAbove() {
    controller.insertCursorAbove();
  }

  void insertCursorBelow() {
    controller.insertCursorBelow();
  }

  void addSelectionToNextFindMatch() {
    if (readOnly) return;
    controller.addSelectionToNextFindMatch();
  }

  void selectAllOccurrences() {
    controller.selectAllOccurrencesOfSelectionOrWord();
  }

  void cursorUndo() {
    controller.cursorUndo();
  }

  // ---------------------------------------------------------------------------
  // Line manipulation
  // ---------------------------------------------------------------------------

  void moveLineUp() {
    if (readOnly) return;
    final selection = controller.selection;
    final text = controller.text;
    final selStart = selection.start;
    final selEnd = selection.end;
    final lineStart = selStart > 0
        ? text.lastIndexOf('\n', selStart - 1) + 1
        : 0;
    int effectiveEnd = selEnd;
    if (!selection.isCollapsed &&
        effectiveEnd > selStart &&
        effectiveEnd > 0 &&
        text[effectiveEnd - 1] == '\n') {
      effectiveEnd -= 1;
    }
    int lineEnd = text.indexOf('\n', effectiveEnd);
    if (lineEnd == -1) lineEnd = text.length;
    if (lineStart == 0) return;

    final prevLineEnd = lineStart - 1;
    final prevLineStart = text.lastIndexOf('\n', prevLineEnd - 1) + 1;
    final prevLine = text.substring(prevLineStart, prevLineEnd);
    final currentLines = text.substring(lineStart, lineEnd);

    controller.replaceRange(prevLineStart, lineEnd, '$currentLines\n$prevLine');

    final prevLineLen = prevLineEnd - prevLineStart;
    final offsetDelta = prevLineLen + 1;
    final newSelection = TextSelection(
      baseOffset: selection.baseOffset - offsetDelta,
      extentOffset: selection.extentOffset - offsetDelta,
    );
    controller.setSelectionSilently(newSelection);
  }

  void moveLineDown() {
    if (readOnly) return;
    final selection = controller.selection;
    final text = controller.text;
    final selStart = selection.start;
    final selEnd = selection.end;
    final lineStart = selStart > 0
        ? text.lastIndexOf('\n', selStart - 1) + 1
        : 0;
    int effectiveEnd = selEnd;
    if (!selection.isCollapsed &&
        effectiveEnd > selStart &&
        effectiveEnd > 0 &&
        text[effectiveEnd - 1] == '\n') {
      effectiveEnd -= 1;
    }
    int lineEnd = text.indexOf('\n', effectiveEnd);
    if (lineEnd == -1) lineEnd = text.length;
    final nextLineStart = lineEnd + 1;
    if (nextLineStart >= text.length) return;
    int nextLineEnd = text.indexOf('\n', nextLineStart);
    if (nextLineEnd == -1) nextLineEnd = text.length;

    final currentLines = text.substring(lineStart, lineEnd);
    final nextLine = text.substring(nextLineStart, nextLineEnd);

    controller.replaceRange(lineStart, nextLineEnd, '$nextLine\n$currentLines');

    final offsetDelta = nextLine.length + 1;
    final newSelection = TextSelection(
      baseOffset: selection.baseOffset + offsetDelta,
      extentOffset: selection.extentOffset + offsetDelta,
    );
    controller.setSelectionSilently(newSelection);
  }

  void copyLineUp() {
    if (readOnly) return;
    final text = controller.text;
    final selection = controller.selection;
    final selStart = selection.start;
    final selEnd = selection.end;

    final lineStart = selStart > 0
        ? text.lastIndexOf('\n', selStart - 1) + 1
        : 0;

    int effectiveEnd = selEnd;
    if (!selection.isCollapsed &&
        effectiveEnd > selStart &&
        effectiveEnd > 0 &&
        text[effectiveEnd - 1] == '\n') {
      effectiveEnd -= 1;
    }

    int lineEnd = text.indexOf('\n', effectiveEnd);
    if (lineEnd == -1) lineEnd = text.length;

    final blockText = text.substring(lineStart, lineEnd);
    controller.replaceRange(lineStart, lineStart, '$blockText\n');

    // Keep the selection on the duplicated block (above).
    controller.setSelectionSilently(
      TextSelection(
        baseOffset: selection.baseOffset,
        extentOffset: selection.extentOffset,
      ),
    );
  }

  void copyLineDown() {
    if (readOnly) return;
    final text = controller.text;
    final selection = controller.selection;
    final selStart = selection.start;
    final selEnd = selection.end;

    final lineStart = selStart > 0
        ? text.lastIndexOf('\n', selStart - 1) + 1
        : 0;

    int effectiveEnd = selEnd;
    if (!selection.isCollapsed &&
        effectiveEnd > selStart &&
        effectiveEnd > 0 &&
        text[effectiveEnd - 1] == '\n') {
      effectiveEnd -= 1;
    }

    int lineEnd = text.indexOf('\n', effectiveEnd);
    if (lineEnd == -1) lineEnd = text.length;

    final blockText = text.substring(lineStart, lineEnd);
    controller.replaceRange(lineEnd, lineEnd, '\n$blockText');

    final offsetDelta = blockText.length + 1;
    controller.setSelectionSilently(
      TextSelection(
        baseOffset: selection.baseOffset + offsetDelta,
        extentOffset: selection.extentOffset + offsetDelta,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LSP
  // ---------------------------------------------------------------------------

  void callSignatureHelp() {
    controller.callSignatureHelp();
  }

  // ---------------------------------------------------------------------------
  // Composite key handler
  // ---------------------------------------------------------------------------

  /// Attempts to handle a key event as a pure editing command.
  ///
  /// Returns `true` if the event was handled (caller should return
  /// [KeyEventResult.handled]). Returns `false` if the event was not
  /// recognised as a command — the caller should continue its own handling.
  ///
  /// This does NOT handle UI-overlay keys (suggestions popup, find/replace,
  /// escape, ghost text acceptance, inlay hints toggle). Those remain in
  /// `_CodeForgeState`.
  bool handleKeyEvent(
    KeyEvent event, {
    required bool metaPressed,
    required bool ctrlPressed,
    required bool altPressed,
    required bool shiftPressed,
    required bool isMacOS,
  }) {
    final isPrimaryModifier = isMacOS ? metaPressed : ctrlPressed;
    final isWordModifier = isMacOS ? altPressed : ctrlPressed;

    // Cmd/Ctrl+Shift+Space → signature help
    if (isPrimaryModifier &&
        shiftPressed &&
        event.logicalKey == LogicalKeyboardKey.space) {
      callSignatureHelp();
      onPostCommand?.call();
      return true;
    }

    // Cmd/Ctrl+Alt → insert cursor above/below
    if (isPrimaryModifier && altPressed) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowUp:
          insertCursorAbove();
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.arrowDown:
          insertCursorBelow();
          onPostCommand?.call();
          return true;
        default:
          break;
      }
    }

    // Cmd/Ctrl+Shift+L → select all occurrences
    if (isPrimaryModifier &&
        shiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyL) {
      selectAllOccurrences();
      onPostCommand?.call();
      return true;
    }

    // Word modifier + Shift → word selection
    if (isWordModifier && shiftPressed) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowLeft:
          moveWordLeft(select: true);
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.arrowRight:
          moveWordRight(select: true);
          onPostCommand?.call();
          return true;
        default:
          break;
      }
    }

    // Primary modifier (Cmd on Mac, Ctrl on others)
    if (isPrimaryModifier) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyC:
          copy();
          return true;
        case LogicalKeyboardKey.keyX:
          cut();
          return true;
        case LogicalKeyboardKey.keyV:
          paste();
          return true;
        case LogicalKeyboardKey.keyA:
          selectAll();
          return true;
        case LogicalKeyboardKey.keyD:
          addSelectionToNextFindMatch();
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.keyU:
          cursorUndo();
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.keyZ:
          if (shiftPressed) {
            redo();
          } else {
            undo();
          }
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.keyY:
          redo();
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.backspace:
          if (!isMacOS) {
            deleteWordBackward();
            onPostCommand?.call();
            return true;
          }
          return false;
        case LogicalKeyboardKey.delete:
          if (!isMacOS) {
            deleteWordForward();
            onPostCommand?.call();
            return true;
          }
          return false;
        case LogicalKeyboardKey.arrowLeft:
          if (isMacOS) {
            moveHome(select: shiftPressed);
          } else {
            moveWordLeft();
          }
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.arrowRight:
          if (isMacOS) {
            moveEnd(select: shiftPressed);
          } else {
            moveWordRight();
          }
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.arrowUp:
          if (isMacOS) {
            moveDocumentHome(select: shiftPressed);
            onPostCommand?.call();
            return true;
          }
          return false;
        case LogicalKeyboardKey.arrowDown:
          if (isMacOS) {
            moveDocumentEnd(select: shiftPressed);
            onPostCommand?.call();
            return true;
          }
          return false;
        default:
          break;
      }
    }

    // Shift only (no primary/word modifier)
    if (shiftPressed && !isPrimaryModifier && !isWordModifier) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.tab:
          unindent();
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.arrowUp:
          moveCursorUp(select: true);
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.arrowDown:
          moveCursorDown(select: true);
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.home:
          moveHome(select: true);
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.end:
          moveEnd(select: true);
          onPostCommand?.call();
          return true;
        default:
          // Shift+ArrowLeft, Shift+ArrowRight are handled below as they need
          // the UI-coupled _handleArrowLeft/_handleArrowRight wrappers that
          // dismiss suggestions and handle ghost text. Return false so the
          // caller handles them.
          break;
      }
    }

    // Alt only (no primary modifier) — line move/copy + word movement on Mac
    if (altPressed && !isPrimaryModifier) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowUp:
          if (shiftPressed) {
            copyLineUp();
          } else {
            moveLineUp();
          }
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.arrowDown:
          if (shiftPressed) {
            copyLineDown();
          } else {
            moveLineDown();
          }
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.arrowLeft:
          moveWordLeft(select: shiftPressed);
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.arrowRight:
          moveWordRight(select: shiftPressed);
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.backspace:
          deleteWordBackward();
          onPostCommand?.call();
          return true;
        case LogicalKeyboardKey.delete:
          deleteWordForward();
          onPostCommand?.call();
          return true;
        default:
          break;
      }
    }

    // No modifier — base keys
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        moveCursorDown(select: shiftPressed);
        onPostCommand?.call();
        return true;
      case LogicalKeyboardKey.arrowUp:
        moveCursorUp(select: shiftPressed);
        onPostCommand?.call();
        return true;
      case LogicalKeyboardKey.home:
        moveHome(select: shiftPressed);
        onPostCommand?.call();
        return true;
      case LogicalKeyboardKey.end:
        moveEnd(select: shiftPressed);
        onPostCommand?.call();
        return true;
      default:
        break;
    }

    return false;
  }
}
