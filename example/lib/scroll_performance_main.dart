import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/github-dark.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const ScrollPerformanceApp());
}

class ScrollPerformanceApp extends StatelessWidget {
  const ScrollPerformanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const ScrollPerformancePage(),
    );
  }
}

class ScrollPerformancePage extends StatefulWidget {
  const ScrollPerformancePage({super.key});

  @override
  State<ScrollPerformancePage> createState() => _ScrollPerformancePageState();
}

class _ScrollPerformancePageState extends State<ScrollPerformancePage> {
  final _editor = CodeForgeController();
  var _lineWrap = false;
  var _languageName = 'JSON';

  Mode get _language => _languageName == 'Dart' ? langDart : langJson;

  @override
  void initState() {
    super.initState();
    _replaceText(_buildJsonSample(6000));
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  String _buildJsonSample(int lineCount) {
    return List<String>.generate(
      lineCount,
      (index) =>
          '{"line": $index, "name": "scroll-performance", '
          '"message": "Paste your long JSON, XML, SQL, or source content here", '
          '"payload": "abcdefghijklmnopqrstuvwxyz0123456789"}',
    ).join('\n');
  }

  void _replaceText(String text) {
    _editor.text = text;
    if (mounted) setState(() {});
  }

  Future<void> _pasteFromClipboard() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text;
    if (text != null && text.isNotEmpty) _replaceText(text);
  }

  Future<void> _openPasteDialog() async {
    final input = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste long content'),
        content: SizedBox(
          width: 720,
          height: 420,
          child: TextField(
            controller: input,
            autofocus: true,
            expands: true,
            minLines: null,
            maxLines: null,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Paste content here',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Load'),
          ),
        ],
      ),
    );
    input.dispose();
    if (text != null && text.isNotEmpty) _replaceText(text);
  }

  @override
  Widget build(BuildContext context) {
    final stats = '${_editor.lineCount} lines · ${_editor.length} chars';
    return Scaffold(
      appBar: AppBar(
        title: const Text('CodeForge scroll performance'),
        actions: [
          Center(child: Text(stats)),
          const SizedBox(width: 16),
          DropdownButton<String>(
            value: _languageName,
            items: const [
              DropdownMenuItem(value: 'JSON', child: Text('JSON')),
              DropdownMenuItem(value: 'Dart', child: Text('Dart')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _languageName = value);
            },
          ),
          const SizedBox(width: 12),
          const Text('Wrap'),
          Switch(
            value: _lineWrap,
            onChanged: (value) => setState(() => _lineWrap = value),
          ),
          TextButton(
            onPressed: () => _replaceText(_buildJsonSample(6000)),
            child: const Text('Generate 6k'),
          ),
          TextButton(
            onPressed: () => _replaceText(_buildJsonSample(12000)),
            child: const Text('Generate 12k'),
          ),
          TextButton(
            onPressed: _pasteFromClipboard,
            child: const Text('Clipboard'),
          ),
          TextButton(onPressed: _openPasteDialog, child: const Text('Paste')),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: CodeForge(
          controller: _editor,
          language: _language,
          lineWrap: _lineWrap,
          editorTheme: githubDarkTheme,
          textStyle: const TextStyle(
            fontFamily: 'Consolas',
            fontSize: 13,
            height: 1.2,
          ),
          // Keep the benchmark focused on text layout and syntax highlighting.
          enableFolding: false,
          enableGuideLines: false,
          enableLocalSuggestions: false,
          enableKeyboardSuggestions: false,
        ),
      ),
    );
  }
}
