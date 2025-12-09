import 'package:code_forge/AI_completion/ai.dart';
import 'package:code_forge/LSP/lsp.dart';
import 'package:code_forge/code_forge.dart';
import 'package:example/big_code.dart';
import 'package:example/little_code.dart';
import 'package:example/small_code.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/python.dart';

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

/*   Future<LspConfig> getLsp() async{
    final data = await LspStdioConfig.start(
      executable: "/home/athul/flutter/flutter/bin//dart",
      args: ["language-server", "--protocol=lsp"],
      filePath: "/home/athul/Projects/code_forge/lib/code_forge/code_area.dart",
      workspacePath: "/home/athul/Projects/code_forge/lib/",
      languageId: "dart"
    );
    return data;
  } */

   Future<LspConfig> getLsp() async{
    final data = await LspStdioConfig.start(
      executable: "/home/athul/.nvm/versions/node/v20.19.2/bin/basedpyright-langserver",
      args: ["--stdio"],
      filePath: "/home/athul/Projects/EhEh/sample.py",
      workspacePath: "/home/athul/Projects/EhEh",
      languageId: "python"
    );
    return data;
  }

  /* Future<LspConfig> getLsp() async{
    final data = await LspStdioConfig.start(
      executable: "/home/athul/flutter/flutter/bin//dart",
      args: ["language-server", "--protocol=lsp"],
      filePath: "/home/athul/Projects/EhEh/server/lib/server.dart",
      workspacePath: "/home/athul/Projects/EhEh/server",
      languageId: "dart"
    );
    return data;
  } */

  @override
  void initState(){
    // _controller.text = small_code;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SafeArea(
        child: FutureBuilder<LspConfig>(
          future: getLsp(),
          builder: (context, snapshot) {
            if(snapshot.connectionState == ConnectionState.waiting){
              return CircularProgressIndicator();
            }
            return CodeForge(
              // language: langDart,
              language: langPython,
              filePath: "/home/athul/Projects/EhEh/sample.py",
              controller: _controller,
              textStyle: GoogleFonts.jetBrainsMono(),
              /* aiCompletion: AiCompletion(
                model: Gemini(
                  apiKey: "AIzaSyB-1JwovLrD9CJoZtEj5ZS43YJ7z7fAl9Q"
                )
              ), */
              /* lspConfig: LspSocketConfig(
                filePath: "/home/athul/Projects/EhEh/sample.py",
                languageId: "python",
                serverUrl: "ws://0.0.0.0:3031",
                workspacePath: "/home/athul/Projects/EhEh",
              ), */
              lspConfig: snapshot.data,
              // filePath: "/home/athul/Projects/code_forge/lib/code_forge/code_area.dart",
              // filePath: "/home/athul/Projects/EhEh/numpy_source.py",
              // filePath: "/home/athul/Projects/EhEh/server/lib/server.dart",
              gutterStyle: GutterStyle(
                // backgroundColor: Color(0xFF252526),
                lineNumberStyle: TextStyle(
                  fontSize: 13,
                ),
                foldedIconColor: Color(0xFFD4D4D4),
                unfoldedIconColor: Color(0xFF858585),
              ),
              selectionStyle: CodeSelectionStyle(
                cursorColor: const Color(0xFFAEAFAD),
                //TODO
                selectionColor: const Color(0xFF264F78).withOpacity(0.5),
              ),
            );
          }
        )
      ),
    );
  }
}
