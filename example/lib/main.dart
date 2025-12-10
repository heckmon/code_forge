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
  final _controller = CodeForgeController();
  final undoController = UndoRedoController();
  final absFilePath = p.join(Directory.current.path, "lib/example_code.dart");

  Future<LspConfig> getLsp() async {
    final absWorkspacePath = p.join(Directory.current.path, "lib");
    final data = await LspStdioConfig.start(
      executable: "dart",
      args: ["language-server", "--protocol=lsp"],
      filePath: absFilePath,
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
                return CircularProgressIndicator();
              }
              return CodeForge(
                undoController: undoController,
                language: langDart,
                controller: _controller,
                textStyle: GoogleFonts.jetBrainsMono(),
                /* aiCompletion: AiCompletion(
                  model: Gemini(apiKey: "YOUR API KEY"),
                ), */
                lspConfig: snapshot.data,
                filePath: absFilePath,
              );
            },
          ),
        ),
      ),
    );
  }
}
