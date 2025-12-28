import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:re_highlight/languages/dart.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final undoController = UndoRedoController();
  final absFilePath = p.join(Directory.current.path, "lib/example_code.dart");
  CodeForgeController? codeController;
  FindController? findController;
  final replaceController = TextEditingController();

  Future<LspConfig> getLsp() async {
    final absWorkspacePath = p.join(Directory.current.path, "lib");
    final data = await LspStdioConfig.start(
      executable: "dart",
      args: ["language-server", "--protocol=lsp"],
      workspacePath: absWorkspacePath,
      languageId: "dart",
    );
    return data;
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: FutureBuilder<LspConfig>(
            future: getLsp(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData) {
                return const Center(child: Text("Failed to load LSP"));
              }

              // Initialize controllers if not already (or if config changed, though unlikely here)
              // Ideally we'd do this cleaner, but for a quick verified test inside FutureBuilder:
              final lspConfig = snapshot.data!;
              if (codeController == null ||
                  codeController!.lspConfig != lspConfig) {
                codeController = CodeForgeController(lspConfig: lspConfig);
                findController = FindController(codeController!);
              }

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    color: Colors.grey[200],
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.search),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  hintText: 'Find...',
                                  border: InputBorder.none,
                                ),
                                onChanged: (val) => findController?.find(val),
                              ),
                            ),
                            // Verification Toggles
                            ListenableBuilder(
                              listenable: findController!,
                              builder: (context, _) {
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    findController?.currentMatchIndex == -1
                                        ? Text(
                                            "No Results",
                                            style: TextStyle(color: Colors.red),
                                          )
                                        : Text(
                                            "${findController!.currentMatchIndex + 1}/${findController!.matchCount}",
                                          ),
                                    IconButton(
                                      icon: const Icon(Icons.abc),
                                      color: findController!.caseSensitive
                                          ? Colors.blue
                                          : Colors.grey,
                                      onPressed: () =>
                                          findController!.caseSensitive =
                                              !findController!.caseSensitive,
                                      tooltip: 'Match Case',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.text_fields),
                                      color: findController!.matchWholeWord
                                          ? Colors.blue
                                          : Colors.grey,
                                      onPressed: () =>
                                          findController!.matchWholeWord =
                                              !findController!.matchWholeWord,
                                      tooltip: 'Match Whole Word',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.code),
                                      color: findController!.isRegex
                                          ? Colors.blue
                                          : Colors.grey,
                                      onPressed: () => findController!.isRegex =
                                          !findController!.isRegex,
                                      tooltip: 'Regex',
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_up),
                              onPressed: () => findController?.previous(),
                              tooltip: 'Previous',
                            ),
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down),
                              onPressed: () => findController?.next(),
                              tooltip: 'Next',
                            ),
                          ],
                        ),
                        const Divider(),
                        Row(
                          children: [
                            const Icon(Icons.edit_note),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: replaceController,
                                decoration: const InputDecoration(
                                  hintText: 'Replace...',
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                findController?.replace(replaceController.text);
                              },
                              child: const Text('Replace'),
                            ),
                            TextButton(
                              onPressed: () {
                                findController?.replaceAll(
                                  replaceController.text,
                                );
                              },
                              child: const Text('All'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: CodeForge(
                      undoController: undoController,
                      language: langDart,
                      controller: codeController,
                      textStyle: GoogleFonts.jetBrainsMono(),
                      filePath: absFilePath,
                      matchHighlightStyle: const MatchHighlightStyle(
                        currentMatchStyle: TextStyle(
                          backgroundColor: Color(0xFFFFA726),
                        ),
                        otherMatchStyle: TextStyle(
                          backgroundColor: Color(0x55FFFF00),
                        ),
                      ),
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
