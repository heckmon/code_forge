import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:example/finder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/styles/github-dark.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final undoController = UndoRedoController();
  late final Future<LspConfig?> _lspFuture = getLsp();
  late final Future<String> _exampleTextFuture = _loadExampleText();
  String? lspError;
  CodeForgeController? codeController;

  Future<String> _loadExampleText() async {
    try {
      return await rootBundle.loadString('assets/example_code.dart');
    } catch (_) {
      return '// Failed to load assets/example_code.dart';
    }
  }

  Future<LspConfig?> getLsp() async {
    try {
      final absWorkspacePath = p.join(Directory.current.path, "lib");
      final data = await LspStdioConfig.start(
        executable: "/home/athul/flutter/flutter/bin//dart",
        args: ["language-server", "--protocol=lsp"],
        workspacePath: absWorkspacePath,
        languageId: "dart",
      );
      return data;
    } catch (e) {
      // Keep the editor usable even when local LSP startup fails.
      lspError = e.toString();
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            codeController?.setGitDiffDecorations(
              addedRanges: [(1, 5), (10, 25)],
              removedRanges: [
                (
                  afterLine: 29,
                  content:
                      'final x = 10;\nfinal y = 20;\nprint("removed line");',
                ),
              ],
            );
            codeController?.scrollToLine(30);
          },
        ),
        body: SafeArea(
          child: FutureBuilder<List<Object?>>(
            future: Future.wait<Object?>([_lspFuture, _exampleTextFuture]),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final lspConfig = snapshot.data?[0] as LspConfig?;
              final exampleText =
                  (snapshot.data?[1] as String?) ??
                  '// Failed to load assets/example_code.dart';

              if (codeController == null ||
                  codeController!.lspConfig != lspConfig) {
                codeController = lspConfig == null
                    ? CodeForgeController()
                    : CodeForgeController(lspConfig: lspConfig);
              }

              return Column(
                children: [
                  if (lspConfig == null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      color: const Color(0xFFFFF3CD),
                      child: Text(
                        'LSP is disabled: ${lspError ?? "startup failed"}',
                        style: const TextStyle(
                          color: Color(0xFF664D03),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Expanded(
                    child: CodeForge(
                      undoController: undoController,
                      language: langDart,
                      editorTheme: githubDarkTheme,
                      controller: codeController,
                      textStyle: GoogleFonts.jetBrainsMono(
                        textStyle: const TextStyle(fontFamily: 'monospace'),
                      ),
                      initialText: exampleText,
                      tabSize: 4,
                      matchHighlightStyle: const MatchHighlightStyle(
                        currentMatchStyle: TextStyle(
                          backgroundColor: Color(0xFFFFA726),
                        ),
                        otherMatchStyle: TextStyle(
                          backgroundColor: Color(0x55FFFF00),
                        ),
                      ),
                      finderBuilder: (c, controller) =>
                          FindPanelView(controller: controller),
                      customCodeSnippets: [
                        CustomCodeSnippet(
                          label: 'if',
                          value: 'if (condition) {\n  \n}',
                          cursorLocations: {4},
                        ),
                        CustomCodeSnippet(
                          label: 'if-else',
                          value: 'if (condition) {\n  \n} else {\n  \n}',
                          cursorLocations: {18, 31},
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
