import 'dart:io';
import 'package:example/finder.dart';
import 'package:path/path.dart' as p;
import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/styles/atom-one-dark-reasonable.dart';

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
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            codeController?.setGitDiffDecorations(
              addedRanges: [(1, 5), (10, 25)],
              removedRanges: [(30, 37)],
            );
          },
        ),
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

              final lspConfig = snapshot.data!;
              if (codeController == null ||
                  codeController!.lspConfig != lspConfig) {
                codeController = CodeForgeController(lspConfig: lspConfig);
              }

              return CodeForge(
                undoController: undoController,
                language: langDart,
                editorTheme: atomOneDarkReasonableTheme,
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
                finderBuilder: (c, controller) =>
                    FindPanelView(controller: controller),
              );
            },
          ),
        ),
      ),
    );
  }
}
