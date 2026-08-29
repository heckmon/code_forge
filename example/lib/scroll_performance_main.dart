import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_highlight/languages/all.dart';
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
  final _editorTick = ValueNotifier<int>(0);
  final _codeVScroll = ScrollController();
  final _referenceVScroll = ScrollController();
  bool _syncingReferenceScroll = false;
  var _lineWrap = false;
  var _languageName = 'json';

  Mode? resolveLanguageMode(String key) {
    final mode = builtinAllLanguages[key];
    return mode is Mode ? mode : null;
  }

  @override
  void initState() {
    super.initState();
    _editor.addListener(_onEditorChanged);
    _codeVScroll.addListener(_syncReferenceScroll);
    _languageName = 'json';
    _replaceText(_buildProvidedJson());
  }

  void _onEditorChanged() {
    _editorTick.value++;
  }

  void _syncReferenceScroll() {
    if (_syncingReferenceScroll || !_referenceVScroll.hasClients) return;
    _syncingReferenceScroll = true;
    final target = _codeVScroll.offset.clamp(
      _referenceVScroll.position.minScrollExtent,
      _referenceVScroll.position.maxScrollExtent,
    );
    _referenceVScroll.jumpTo(target);
    _syncingReferenceScroll = false;
  }

  @override
  void dispose() {
    _editor.removeListener(_onEditorChanged);
    _editorTick.dispose();
    _editor.dispose();
    _codeVScroll
      ..removeListener(_syncReferenceScroll)
      ..dispose();
    _referenceVScroll.dispose();
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

  String _buildProvidedJson() => '''
{
  "number": 123,
  "array": [
    1,
    2,
    3,
    8143661439548533000,
    "8143661439548533232"
  ],
  "safe integer": 9007199254740991,
  "unsafe integer": 9007199254111741000,
  "text line": "You can delete this sample JSON from the options page",
  "text block": "Line 1\\nLine 2\\n  Line 2.1\\n  Line 2.2\\nLine 3",
  "number string": "8143661439548533232",
  "boolean": true,
  "color": "gold",
  "null": null,
  "object": {
    "complex": [
      40.66,
      -73.23,
      -73.9899789999999
    ],
    "type": "Point"
  }
}
''';

  String _buildGoSample() =>
      '''// Addr2line is a minimal simulation of the GNU addr2line tool.
package main

import (
\t"bufio"
\t"flag"
\t"fmt"
\t"log"
\t"os"
\t"strconv"
\t"strings"
)

func printUsage(w *os.File) {
\tfmt.Fprintf(w, "usage: addr2line binary\\n")
\tfmt.Fprintf(w, "reads addresses from standard input\\n")
}

func main() {
\tlog.SetFlags(0)
\tflag.Parse()
\tstdin := bufio.NewScanner(os.Stdin)
\tfor stdin.Scan() {
\t\tp := strings.TrimPrefix(stdin.Text(), "0x")
\t\tpc, _ := strconv.ParseUint(p, 16, 64)
\t\tfmt.Println(pc)
\t}
}''';

  String _buildJavaSample() => '''public class HelloWorld {
    public static void main(String[] args) {
        System.out.println("Hello, World!");
    }
}''';

  void _replaceText(String text) {
    _editor.text = text;
  }

  TextSpan _buildReferenceLine(String text) {
    final language = resolveLanguageMode(_languageName);
    if (language == null) return TextSpan(text: text);
    final highlighter = Highlight()..registerLanguage('reference', language);
    try {
      final result = highlighter.highlight(code: text, language: 'reference');
      final renderer = TextSpanRenderer(null, githubDarkTheme);
      result.render(renderer);
      return renderer.span ?? TextSpan(text: text);
    } catch (_) {
      return TextSpan(text: text);
    }
  }

  TextSpan? _buildCodeForgeLine(String text) {
    final language = resolveLanguageMode(_languageName);
    if (language == null) return TextSpan(text: text);
    final highlighter = SyntaxHighlighter(
      language: language,
      editorTheme: githubDarkTheme,
      languageId: _languageName,
    );
    return highlighter.getLineSpan(0, text);
  }

  void _dumpSpanTree(String label, TextSpan? span) {
    void walk(TextSpan node, String indent) {
      final text = node.text;
      if (text != null && text.isNotEmpty) {
        debugPrint(
          '$indent${text.replaceAll("\n", r"\\n")} '
              'color=${node.style?.color} '
              'weight=${node.style?.fontWeight} '
              'style=${node.style?.fontStyle}',
        );
      }
      final children = node.children;
      if (children == null) return;
      for (final child in children) {
        if (child is TextSpan) {
          walk(child, '$indent  ');
        }
      }
    }

    debugPrint('--- $label ---');
    if (span == null) {
      debugPrint('<null>');
      return;
    }
    walk(span, '');
  }

  void _dumpRenderComparison() {
    final language = resolveLanguageMode(_languageName);
    if (language == null) {
      debugPrint('language=null');
      return;
    }

    final line = _editor.text
        .split('\n')
        .firstWhere((l) => l.contains('false'), orElse: () => _editor.text);

    debugPrint('theme.literal=${githubDarkTheme['literal']?.color}');
    debugPrint('theme.keyword=${githubDarkTheme['keyword']?.color}');
    debugPrint('line=$line');

    _dumpSpanTree('reference', _buildReferenceLine(line));
    _dumpSpanTree('codeforge', _buildCodeForgeLine(line));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('CodeForge scroll performance'),
        actions: [
          Center(
            child: ValueListenableBuilder<int>(
              valueListenable: _editorTick,
              builder: (context, _, __) {
                final stats =
                    '${_editor.lineCount} lines · ${_editor.length} chars';
                return Text(stats);
              },
            ),
          ),
          const SizedBox(width: 16),
          DropdownButton<String>(
            value: _languageName,
            items: const [
              DropdownMenuItem(value: 'json', child: Text('json')),
              DropdownMenuItem(value: 'xml', child: Text('xml')),
              DropdownMenuItem(value: 'go', child: Text('go')),
              DropdownMenuItem(value: 'java', child: Text('java')),
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
            onPressed: () {
              _languageName = 'go';
              _replaceText(_buildGoSample());
            },
            child: const Text('Go sample'),
          ),
          TextButton(
            onPressed: () {
              _languageName = 'java';
              _replaceText(_buildJavaSample());
            },
            child: const Text('Java sample'),
          ),
          TextButton(
            onPressed: () {
              _languageName = 'json';
              _replaceText(_buildProvidedJson());
            },
            child: const Text('JSON sample'),
          ),
          TextButton(
            onPressed: _pasteFromClipboard,
            child: const Text('Clipboard'),
          ),
          TextButton(onPressed: _openPasteDialog, child: const Text('Paste')),
          TextButton(
            onPressed: _dumpRenderComparison,
            child: const Text('Dump'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: CodeForge(
                controller: _editor,
                verticalScrollController: _codeVScroll,
                language: resolveLanguageMode(_languageName),
                lineWrap: _lineWrap,
                editorTheme: githubDarkTheme,
                textStyle: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 13,
                  height: 1.2,
                ),
                enableFolding: false,
                enableGuideLines: false,
                enableLocalSuggestions: false,
                enableKeyboardSuggestions: false,
              ),
            ),
            const VerticalDivider(width: 1),
            // Expanded(
            //   child: ValueListenableBuilder<int>(
            //     valueListenable: _editorTick,
            //     builder: (context, _, __) => DecoratedBox(
            //       decoration: BoxDecoration(
            //         color: githubDarkTheme['root']?.backgroundColor,
            //       ),
            //       child: ListView.builder(
            //         controller: _referenceVScroll,
            //         padding: const EdgeInsets.all(8),
            //         itemCount: _editor.lineCount,
            //         itemBuilder: (context, index) => SelectableText.rich(
            //           _buildReferenceLine(_editor.getLineText(index)),
            //           style: const TextStyle(
            //             fontFamily: 'Consolas',
            //             fontSize: 13,
            //             height: 1.2,
            //           ),
            //         ),
            //       ),
            //     ),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}
