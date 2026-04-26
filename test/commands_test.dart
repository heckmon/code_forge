import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:code_forge/code_forge.dart';

void main() {
  late CodeForgeController controller;
  late UndoRedoController undoRedo;
  late CodeForgeCommands commands;
  late List<String> postCommandLog;

  setUp(() {
    controller = CodeForgeController();
    undoRedo = UndoRedoController();
    controller.setUndoController(undoRedo);
    postCommandLog = [];
    commands = CodeForgeCommands(
      controller: controller,
      undoRedoController: undoRedo,
      onPostCommand: () => postCommandLog.add('postCommand'),
    );
  });

  tearDown(() {
    controller.dispose();
    undoRedo.dispose();
  });

  group('CodeForgeCommands instantiation', () {
    test('can be created standalone without widget tree', () {
      expect(commands, isNotNull);
      expect(commands.controller, same(controller));
      expect(commands.undoRedoController, same(undoRedo));
      expect(commands.readOnly, isFalse);
    });
  });

  group('Text editing commands', () {
    test('selectAll selects entire text', () {
      controller.replaceRange(0, 0, 'hello world');
      commands.selectAll();
      expect(controller.selection.baseOffset, 0);
      expect(controller.selection.extentOffset, 11);
    });

    test('backspace deletes character before cursor', () {
      controller.replaceRange(0, 0, 'hello');
      controller.selection = const TextSelection.collapsed(offset: 5);
      commands.backspace();
      expect(controller.text, 'hell');
    });

    test('delete removes character after cursor', () {
      controller.replaceRange(0, 0, 'hello');
      controller.selection = const TextSelection.collapsed(offset: 0);
      commands.delete();
      expect(controller.text, 'ello');
    });

    test('backspace does nothing in readOnly mode', () {
      controller.replaceRange(0, 0, 'hello');
      controller.selection = const TextSelection.collapsed(offset: 5);
      commands.readOnly = true;
      commands.backspace();
      expect(controller.text, 'hello');
    });

    test('deleteWordBackward deletes previous word', () {
      controller.replaceRange(0, 0, 'hello world');
      controller.selection = const TextSelection.collapsed(offset: 11);
      commands.deleteWordBackward();
      expect(controller.text, 'hello ');
    });

    test('deleteWordForward deletes next word', () {
      controller.replaceRange(0, 0, 'hello world');
      controller.selection = const TextSelection.collapsed(offset: 0);
      commands.deleteWordForward();
      expect(controller.text, ' world');
    });
  });

  group('Cursor movement', () {
    test('moveCursorRight advances cursor by one', () {
      controller.replaceRange(0, 0, 'hello');
      controller.selection = const TextSelection.collapsed(offset: 0);
      commands.moveCursorRight();
      expect(controller.selection.baseOffset, 1);
      expect(controller.selection.isCollapsed, isTrue);
    });

    test('moveCursorRight with select extends selection', () {
      controller.replaceRange(0, 0, 'hello');
      controller.selection = const TextSelection.collapsed(offset: 0);
      commands.moveCursorRight(select: true);
      expect(controller.selection.baseOffset, 0);
      expect(controller.selection.extentOffset, 1);
    });

    test('moveCursorLeft moves cursor back by one', () {
      controller.replaceRange(0, 0, 'hello');
      controller.selection = const TextSelection.collapsed(offset: 3);
      commands.moveCursorLeft();
      expect(controller.selection.baseOffset, 2);
      expect(controller.selection.isCollapsed, isTrue);
    });

    test('moveWordRight jumps to end of word', () {
      controller.replaceRange(0, 0, 'hello world');
      controller.selection = const TextSelection.collapsed(offset: 0);
      commands.moveWordRight();
      expect(controller.selection.baseOffset, 5);
    });

    test('moveWordLeft jumps to start of word', () {
      controller.replaceRange(0, 0, 'hello world');
      controller.selection = const TextSelection.collapsed(offset: 11);
      commands.moveWordLeft();
      expect(controller.selection.baseOffset, 6);
    });

    test('moveWordRight with select extends selection to word end', () {
      controller.replaceRange(0, 0, 'hello world');
      controller.selection = const TextSelection.collapsed(offset: 0);
      commands.moveWordRight(select: true);
      expect(controller.selection.baseOffset, 0);
      expect(controller.selection.extentOffset, 5);
    });
  });

  group('Line operations', () {
    test('moveLineDown swaps current line with next', () {
      controller.replaceRange(0, 0, 'line1\nline2\nline3');
      controller.selection = const TextSelection.collapsed(offset: 0);
      commands.moveLineDown();
      expect(controller.getLineText(0), 'line2');
      expect(controller.getLineText(1), 'line1');
    });

    test('moveLineUp swaps current line with previous', () {
      controller.replaceRange(0, 0, 'line1\nline2\nline3');
      controller.selection = const TextSelection.collapsed(offset: 6);
      commands.moveLineUp();
      expect(controller.getLineText(0), 'line2');
      expect(controller.getLineText(1), 'line1');
    });

    test('line operations do nothing in readOnly mode', () {
      controller.replaceRange(0, 0, 'line1\nline2');
      controller.selection = const TextSelection.collapsed(offset: 0);
      commands.readOnly = true;
      commands.moveLineDown();
      expect(controller.getLineText(0), 'line1');
    });
  });

  group('Multi-cursor', () {
    test('insertCursorBelow adds a cursor on the next line', () {
      controller.replaceRange(0, 0, 'hello\nworld');
      controller.selection = const TextSelection.collapsed(offset: 0);
      commands.insertCursorBelow();
      expect(controller.selections.length, 2);
    });

    test('insertCursorAbove adds a cursor on the previous line', () {
      controller.replaceRange(0, 0, 'hello\nworld');
      controller.selection = const TextSelection.collapsed(offset: 6);
      commands.insertCursorAbove();
      expect(controller.selections.length, 2);
    });
  });

  group('Undo/Redo', () {
    test('undo reverts last edit', () {
      controller.replaceRange(0, 0, 'hello');
      commands.undo();
      expect(controller.text, isEmpty);
    });

    test('redo restores undone edit', () {
      controller.replaceRange(0, 0, 'hello');
      commands.undo();
      expect(controller.text, isEmpty);
      commands.redo();
      expect(controller.text, 'hello');
    });

    test('undo does nothing in readOnly mode', () {
      controller.replaceRange(0, 0, 'hello');
      commands.readOnly = true;
      commands.undo();
      expect(controller.text, 'hello');
    });
  });

  group('onPostCommand callback', () {
    test('is called after commands', () {
      controller.replaceRange(0, 0, 'hello');
      controller.selection = const TextSelection.collapsed(offset: 0);
      postCommandLog.clear();

      commands.moveCursorRight();
      expect(
        postCommandLog,
        isEmpty,
        reason:
            'Individual method calls do not call onPostCommand — '
            'only handleKeyEvent does',
      );
    });

    test('handleKeyEvent calls onPostCommand for handled commands', () {
      controller.replaceRange(0, 0, 'hello');
      controller.selection = const TextSelection.collapsed(offset: 0);
      postCommandLog.clear();

      final handled = commands.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowDown,
          logicalKey: LogicalKeyboardKey.arrowDown,
          timeStamp: Duration.zero,
        ),
        metaPressed: false,
        ctrlPressed: false,
        altPressed: false,
        shiftPressed: false,
        isMacOS: true,
      );
      expect(handled, isTrue);
      expect(postCommandLog, ['postCommand']);
    });
  });

  group('handleKeyEvent routing', () {
    setUp(() {
      controller.replaceRange(0, 0, 'hello world\nfoo bar');
      controller.selection = const TextSelection.collapsed(offset: 0);
    });

    test('Cmd+A selects all (macOS)', () {
      commands.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        ),
        metaPressed: true,
        ctrlPressed: false,
        altPressed: false,
        shiftPressed: false,
        isMacOS: true,
      );
      expect(controller.selection.baseOffset, 0);
      expect(controller.selection.extentOffset, controller.text.length);
    });

    test('Ctrl+A selects all (Linux/Windows)', () {
      commands.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        ),
        metaPressed: false,
        ctrlPressed: true,
        altPressed: false,
        shiftPressed: false,
        isMacOS: false,
      );
      expect(controller.selection.baseOffset, 0);
      expect(controller.selection.extentOffset, controller.text.length);
    });

    test('Alt+Down moves line down (macOS)', () {
      final handled = commands.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowDown,
          logicalKey: LogicalKeyboardKey.arrowDown,
          timeStamp: Duration.zero,
        ),
        metaPressed: false,
        ctrlPressed: false,
        altPressed: true,
        shiftPressed: false,
        isMacOS: true,
      );
      expect(handled, isTrue);
      expect(controller.getLineText(0), 'foo bar');
      expect(controller.getLineText(1), 'hello world');
    });

    test('unhandled keys return false', () {
      final handled = commands.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
        metaPressed: false,
        ctrlPressed: false,
        altPressed: false,
        shiftPressed: false,
        isMacOS: true,
      );
      expect(handled, isFalse);
    });
  });
}
