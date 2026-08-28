import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/xml.dart';
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
    _languageName = 'go';
    _replaceText(_buildGoSample());
  }

  void _onEditorChanged() {
    if (mounted) setState(() {});
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
    if (mounted) setState(() {});
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
            onPressed: _pasteFromClipboard,
            child: const Text('Clipboard'),
          ),
          TextButton(onPressed: _openPasteDialog, child: const Text('Paste')),
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
            // const VerticalDivider(width: 1),
            // Expanded( // test re_highlight
            //   child: DecoratedBox(
            //     decoration: BoxDecoration(
            //       color: githubDarkTheme['root']?.backgroundColor,
            //     ),
            //     child: ListView.builder(
            //       controller: _referenceVScroll,
            //       padding: const EdgeInsets.all(8),
            //       itemCount: _editor.lineCount,
            //       itemBuilder: (context, index) => SelectableText.rich(
            //         _buildReferenceLine(_editor.getLineText(index)),
            //         style: const TextStyle(
            //           fontFamily: 'Consolas',
            //           fontSize: 13,
            //           height: 1.2,
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
