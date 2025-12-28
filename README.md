<h1 align="center">⚒️ CodeForge</h1>

<p align="center">
  <strong>A powerful, feature-rich code editor created using Flutter</strong>
</p>

<p align="center">
  <em>Bring VS Code-level editing experience to your Flutter apps</em>
</p>


<p align="center">
  A complete and better alternative for <a href=https://pub.dev/packages/re_editor>re_editor</a>, <a href=https://pub.dev/packages/flutter_code_crafter>flutter_code_crafter</a>, <a href=https://pub.dev/packages/flutter_code_editor>flutter_code_editor</a>, <a href =https://pub.dev/packages/code_text_field>code_text_field</a>, etc
</p>

<p align="center">
  <a href="https://pub.dev/packages/code_forge">
    <img src="https://img.shields.io/pub/v/code_forge.svg?style=for-the-badge&logo=dart&logoColor=white&labelColor=0175C2&color=02569B" alt="Pub Version"/>
  </a>
  <a href="https://github.com/heckmon/code_forge/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge&labelColor=333333&color=4CAF50" alt="License"/>
  </a>
  <a href="https://github.com/heckmon/code_forge/stargazers">
    <img src="https://img.shields.io/github/stars/heckmon/code_forge.svg?style=for-the-badge&logo=github&labelColor=333333&color=FFD700" alt="GitHub Stars"/>
  </a>
  <a href="https://flutter.dev">
    <img src="https://img.shields.io/badge/Platform-Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Platform"/>
  </a>
</p>


---

<p align="center">
  <img src="https://raw.githubusercontent.com/heckmon/code_forge/refs/heads/main/gifs/code_forge_100k.gif" alt="CodeForge Demo" width="800"/><sub><br>large code support (tested with 100k+ lines) and LSP based intelligent lazy highlighting</sub>
</p>

> [!NOTE]
>
> CodeForge does **not** support Flutter web, as it relies on `dart:io` for core functionality. Web support may be considered in the future if dependencies allow.

## ✨ Why CodeForge?

**CodeForge** is a next-generation code editor widget designed for developers who demand more. Whether you're building an IDE, a code snippet viewer, or an educational coding platform, CodeForge delivers:

| Feature | CodeForge | Others |
|---------|:---------:|:------:|
| 🎨 Syntax Highlighting | ✅ 180+ languages<br>[Availabe languages](https://github.com/reqable/re-highlight/tree/main/lib/languages) | ✅ |
| 📁 Code Folding | ✅ Smart detection | ⚠️ Limited |
| 🔌 LSP Integration | ✅ Full support | ❌ |
| 🤖 AI Completion | ✅ Multi-model | ❌ |
| ⚡ Semantic Tokens | ✅ Real-time | ❌ |
| 🎯 Diagnostics | ✅ Inline errors | ❌ |
| ↩️ Undo/Redo | ✅ Smart grouping | ⚠️ Basic |
| 🎨 Full Theming | ✅ Everything<br>[Available themes](https://github.com/reqable/re-highlight/tree/main/lib/styles) | ⚠️ Limited |

### What makes CodeForge different from other editors:
- Uses the rope data structure instead of regular char array to to handle large text.
- Uses flutter's low level `RenderBox` and `ParagrahBuilder` to render text insted of `TextField` for efficiency.
- Built in [Language Server Protocol](https://microsoft.github.io/language-server-protocol/) client
- AI Code completion.

---

## 🎬 Features

<div style="display:flex; flex-wrap:wrap; gap:20px;">
  <div style="flex: 0 1 50%; min-width:300px;">
    <h3>🤖 AI Code Completion</h3>
    <p>Intelligent code suggestions powered by AI models like Gemini. Auto, manual, or mixed completion modes with smart debouncing.</p>
    <div style="text-align:center;">
      <img src="https://raw.githubusercontent.com/heckmon/code_forge/refs/heads/main/gifs/cf_ai.gif" alt="AI Completion" style="width:100%;height:auto;" />
    </div>
  </div>

  <div style="flex: 0 1 50%; min-width:300px;">
    <h3>🔌 LSP Integration</h3>
    <p>Full Language Server Protocol support with real-time diagnostics, hover documentation, Code Actions and semantic highlighting.</p>
    <div style="text-align:center;">
      <img src="https://raw.githubusercontent.com/heckmon/code_forge/refs/heads/dev/gifs/cf_lsp_new.gif" alt="LSP Integration" style="width:100%;height:auto;" />
    </div>
  </div>

  <div style="flex: 0 1 50%; min-width:300px;">
    <h3>📁 Smart Code Folding</h3>
    <p>Collapse and expand code blocks with visual indicators. Navigate large files with ease.</p>
    <div style="text-align:center;">
      <img src="https://raw.githubusercontent.com/heckmon/code_forge/refs/heads/main/gifs/cf_fold.gif" alt="Code Folding" style="width:100%;height:auto;" />
    </div>
  </div>

  <div style="flex: 0 1 50%; min-width:300px;">
    <h3>🎨 Syntax Highlighting</h3>
    <p>Beautiful syntax highlighting for 180+ languages with customizable themes and semantic token support.</p>
    <div style="text-align:center;">
      <img src="https://raw.githubusercontent.com/heckmon/code_forge/refs/heads/main/gifs/cf_themes.gif" alt="Syntax Highlighting" style="width:100%;height:auto;" />
    </div>
  </div>
</div>

### 🌟 More Features

<details>
<summary><strong>📋 Complete Feature List</strong></summary>

#### Editor Core
- ⚡ **Rope Data Structure** — Optimized for large files
- 🎨 **180+ Languages** — Via `re_highlight` package
- 📁 **Code Folding** — Smart block detection
- 📏 **Indentation Guides** — Visual code structure
- 🔢 **Line Numbers** — With active line highlighting
- ↩️ **Smart Undo/Redo** — Timestamp-based grouping
- 🔍 **Search Highlighting** — Find and highlight matches
- ✂️ **Line Operations** — Move, duplicate, delete lines

#### LSP Features
- 💡 **Intelligent Completions** — Context-aware suggestions
- 📖 **Hover Documentation** — Rich markdown tooltips
- 🚨 **Real-time Diagnostics** — Errors and warnings
- 🎨 **Semantic Highlighting** — Token-based coloring
- 📡 **Multiple Protocols** — Stdio and WebSocket support

#### AI Features
- 🤖 **Multi-Model Support** — Gemini and extensible
- ⚙️ **Completion Modes** — Auto, manual, or mixed
- 💾 **Response Caching** — Improved performance
- 🧹 **Smart Parsing** — Clean code extraction

#### Customization
- 🎨 **Full Theming** — Every element customizable
- 📐 **Gutter Styling** — Colors, icons, sizes
- ✨ **Selection Styling** — Cursor, selection, bubbles
- 💬 **Popup Styling** — Suggestions, hover details

</details>

---

## 📦 Installation

Add CodeForge to your `pubspec.yaml`:

```yaml
dependencies:
  code_forge: ^3.0.0
```

Then run:

```bash
flutter pub get
```

---

## 🚀 Quick Start

### Basic Usage

Import a theme and a language from the [re_highlight](https://pub.dev/packages/re_highlight) package and you are good to go. (Defaults to `langDart` and `vs2015Theme`):

```dart
import 'package:flutter/material.dart';
import 'package:code_forge/code_forge.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CodeForge(
          language: langPython, // Defaults to langDart
          editorTheme: atomOneDarkTheme, // Defaults to vs2015Theme
        ),
      ),
    );
  }
}
```

### With Controller

For more control over the editor:

```dart
class _EditorState extends State<Editor> {
  final _controller = CodeForgeController();
  final _undoController = UndoRedoController();

  @override
  Widget build(BuildContext context) {
    return CodeForge(
      controller: _controller, // Optional controller for more features.
      undoController: _undoController, // Optional undo controller to control the undo-redo operations.
    );
  }
}
```

---

<details>

<summary><h2>🔌 LSP Integration</h2></summary>

Connect to any Language Server Protocol compatible server for intelligent code assistance.

CodeForge provides a built-in LSP client that allows you to connect to any LSP server for intelligent highlighting, completions, hover details, diagnostics, and more.

## Types
#### There are two ways to configure LSP client with the `CodeForge`:
1. Using WebSocket (easy and recommended)
2. Using stdio

<details>
<summary><h3>1. Using WebSocket</h3></summary>

The class `LspSocketConfig` is used to connect to an LSP server using WebSocket. It takes the following parameters:
- `serverUrl`: The WebSocket URL of the LSP server.
- `filePath`: A filePath is required by the LSP server to provide completions and diagnostics.
- `workspacePath`: The workspace path is the current directory or the parent directory which holds the `filePath` file.
- `languageId`: This is a server specific parameter. eg: `'python'` is the language ID used in basedpyright/pyright language server.

You can easily start any language server using websocket using the  [lsp-ws-proxy](https://github.com/qualified/lsp-ws-proxy) package. For example, to start the basedpyright language server, you can use the following command:<br>
(On Android, you can use [Termux](https://github.com/termux/termux-app))

```bash
cd /Downloads/lsp-ws-proxy_linux # Navigate to the directory where lsp-ws-proxy is located

./lsp-ws-proxy --listen 5656 -- basedpyright-langserver --stdio # Start the pyright language server on port 5656
```

#### Example:
create a `LspSocketConfig` object and pass it to the `CodeForgeController` widget.

```dart
final lspConfig = LspSocketConfig(
    workspacePath: "/home/athul/Projects/lsp",
    languageId: "python",
    serverUrl: "ws://localhost:5656"
),
```
Then pass the `lspConfig` instance to the `CodeForgeController` widget:

```dart
final _controller = CodeForgeController(
  lspConfig: lspConfig // Pass the LspConfig here.
)

CodeForge(
    controller: _controller, // Pass the controller here.
    theme: anOldHopeTheme,
    filePath: "/home/athul/Projects/lsp/example.py"
),
```
</details>

<details>
<summary><h3>2. Using Stdio</h3></summary>

This method is easy to start—no terminal setup or extra packages are needed—but it does require a bit more setup in your code. The `LspStdioConfig.start()` method connects to an LSP server using stdio and is asynchronous, so you'll typically use a `FutureBuilder` to handle initialization. It accepts the following parameters:
- `executable`: Location of the LSP server executable file.
- `args`: Arguments to pass to the LSP server executable.
- `filePath`: A filePath is required by the LSP server to provide completions and diagnostics.
- `workspacePath`: The workspace path is the current directory or parent directory which holds the `filePath` file.
- `languageId`: This is a server specific parameter. eg: `'python'` is the language ID used in pyright language server.

To get the `executable` path, you can use the `which` command in the terminal. For example, to get the path of the `basedpyright-langserver`, you can use the following command:

```bash
which basedpyright-langserver
```

#### Example:
Create an async method to initialize the LSP configuration.
```dart
Future<LspConfig?> _initLsp() async {
    try {
      final config = await LspStdioConfig.start(
        executable: '/home/athul/.nvm/versions/node/v20.19.2/bin/basedpyright-langserver',
        args: ['--stdio'],
        workspacePath: '/home/athul/Projects/lsp',
        languageId: 'python',
      );
      
      return config;
    } catch (e) {
      debugPrint('LSP Initialization failed: $e');
      return null;
    }
  }
  ```
  Then use a `FutureBuilder` to initialize the LSP configuration and pass it to the `CodeForgeController` widget:
```dart
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: FutureBuilder(
            future: _initLsp(), // Call the async method to get the LSP config.
            builder: (context, snapshot) {
              if(snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }
              return CodeForge(
                editorTheme: anOldHopeTheme,
                controller: CodeForgeController(
                  lspConfig: snapshot.data // Pass the config here.
                ),
                filePath: '/home/athul/Projects/lsp/example.py',
                textStyle: TextStyle(fontSize: 15, fontFamily: 'monospace'),
              );
            }
          ),
        ) 
      ),
    );
  }
```
</details>

<hr style="height: 1px; border: none; border-top: 1px">

### Dart LSP Example Using Stdio

```dart
Future<LspConfig> setupDartLsp() async {
  return await LspStdioConfig.start(
    executable: 'dart',
    args: ['language-server', '--protocol=lsp'],
    workspacePath: '/path/to/your/project',
    languageId: 'dart',
  );
}

// In your widget
@override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: FutureBuilder<LspConfig>(
            future: setupDartLsp(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return CircularProgressIndicator();
              }
              return CodeForge(
                language: langDart,
                textStyle: GoogleFonts.jetBrainsMono(),
                controller: CodeForgeController(
                  lspConfig: snapshot.data
                ),
                filePath: '/path/to/your/file.dart', // Mandatory field
              )
            },
          ),
        ),
      ),
    );
  }
```
</details>

---
<details>
<summary><h2>🤖 AI Completion</h2></summary>

Supercharge your editor with AI-powered code completion.

### `AiCompletion` class
#### required parameters:
- `model`: An instance of the `Models` class, which can be one of the [built-in AI models](#built-in-ai-models) or a [custom model](#custom-ai-model).
#### optional parameters:
- `enableCompletion`: A boolean value to enable or disable AI code completion. Defaults to `true`.
- `completionType`: The type of AI code completion. Defaults to `CompletionType.auto`.
- `debounceTime`: The debounce time in milliseconds for AI code completion. Defaults to `1000`.

create an instance of the `AiCompletion` class with any of the [built-in AI models](#built-in-ai-models) or [custom model](#custom-ai-model) and pass it to the `CodeForge` widget.
Example of using Gemini AI completion:

```dart
import 'package:flutter/material.dart';
import 'package:code_crafter/code_crafter.dart';

final aiCompletion = AiCompletion(
    model: Gemini(
        apiKey: "Your API Key",
    )
)
```

Then pass the `aiCompletion` instance to the `CodeForge` widget:

```dart
CodeForge(
    controller: controller,
    theme: anOldHopeTheme,
    aiCompletion: aiCompletion, // Pass the AI completion instance here
),
```

## Styling AI Completion Text
pass the `aiCompletionTextStyle` parameter to the `CodeForge` widget to style the AI completion text. This is a `TextStyle` object that will be applied to the AI completion text. Recommended to leave it null as default style, which is similar to VSCode completion style.

```dart
CodeForge(
    controller: controller,
    theme: anOldHopeTheme,
    aiCompletion: aiCompletion,
    aiCompletionTextStyle: TextStyle(
        color: Colors.grey, // Change the color of the AI completion text
        fontStyle: FontStyle.italic, // Make the AI completion text italic
    ),
),
```

## Completion on Callback
If you want to trigger AI code completion manually, you can use the `getManualAiCompletion()` callback in the `CodeForgeController`. This callback will be called when the AI code completion is triggered.<br>
In this example, a `FloatingActionButton` is used to trigger the AI code completion manually:

```dart
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        floatingActionButton: FloatingActionButton(onPressed: ()=> controller.getManualAiSuggestion()),
        body: SafeArea(
          child: CodeForge(
            editorTheme: anOldHopeTheme,
            controller: controller,
            textStyle: GoogleFonts.notoSansMono(
              fontSize: 15,
            ),
            aiCompletion: AiCompletion(
              completionType: CompletionType.manual,
              model: Gemini(
                apiKey: apiKey,
              )
            ),
          ),
        )
      ),
    );
  }
```

## Built-in AI Models

### 1. `Gemini()`
#### required parameter:
- `apiKey`: Your Gemini API key.
#### optional parameters:
- `model` : The model to use for completion. Defaults to `gemini-2.0-flash`.
- `temperature` : The temperature to use for completion. Defaults to `null`.
- `maxOutPutTokens` : The maximum number of tokens to generate. Defaults to `null`.
- `TopP` : The top P value to use for completion. Defaults to `null`.
- `TopK` : The top K value to use for completion. Defaults to `null`.
- `stopSequences` : The stop sequences to use for completion. Defaults to `null`.

### 2. `OpenAI()`
#### required parameters:
- `apiKey` : Your OpenAI API key.
- `model` : The model to use for completion.

### 3. `Claude()`
#### required parameters:
- `apiKey` : Your Claude API key.
- `model` : The model to use for completion.

### 4. `Grok()`
#### required parameters:
- `apiKey` : Your OpenAI API key.
- `model` : The model to use for completion.

### 5. `DeepSeek()`
#### required parameters:
- `apiKey` : Your OpenAI API key.
- `model` : The model to use for completion.

### 6. `Gorq()`
#### required parameters:
- `apiKey` : Your OpenAI API key.
- `model` : The model to use for completion.

### 7. `TogetherAi()`
#### required parameters:
- `apiKey` : Your OpenAI API key.
- `model` : The model to use for completion.

### 8. `Sonar()`
#### required parameters:
- `apiKey` : Your OpenAI API key.
- `model` : The model to use for completion.

### 9. `OpenRouter()`
#### required parameters:
- `apiKey` : Your OpenAI API key.
- `model` : The model to use for completion.

### 10. `FireWorks()`
#### required parameters:
- `apiKey` : Your OpenAI API key.
- `model` : The model to use for completion.

## Custom AI Model

If want to use a custom AI model that running on your own server or a third party service not listed above, you can create an instance of the `CustomModel` class and pass it to the `AiCompletion` class. 

#### required parameters
- `url` : The URL of the AI model endpoint.
- `customHeaders` : The custom headers to use for the request.
`String` content.
- `requestBuilder` : The request builds the request and return the response. This is a function that takes two `String` parameters code and instruction as input and returns a `Map<String, dynamic>`.
- `customParser` : A function that parse the json response and returns `String` content.

#### Example of using a custom AI model using TogetherAI:

```dart
late final Models model;

  @override
  void initState() {
    model = CustomModel(
      url: "https://api.together.xyz/v1/chat/completions",
      customHeaders: {
        "Authorization": "Bearer ${your_api_key}",
        "Content-Type": "application/json"
      },
      requestBuilder: (code, instruction){
        return {
          "model": "deepseek-ai/DeepSeek-V3",
          "messages": [
            {
              "role": "system",
              "content": instruction
            },
            {
              "role": "user",
              "content": code
            }
          ]
        };
      },
      customParser: (response) => response['choices'][0]['message']['content']
    );
    controller = CodeCrafterController();
    controller.language = python;
    super.initState();
  }
```
Then pass the `model` instance to the `AiCompletion` class:

```dart
 @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CodeForge(
          editorTheme: anOldHopeTheme,
          controller: controller,
          aiCompletion: AiCompletion(
            model: model // Pass the custom model here
          ),
        )
      ),
    );
  }
```
</details>

---

<details>
<summary><h2>🎨 Customization</h2></summary>

CodeForge offers extensive customization options for every aspect of the editor.

### Theme & Styling

```dart
CodeForge(
  controller: controller,
  language: langDart,
  
  // Editor theme (syntax colors)
  editorTheme: vs2015Theme,
  
  // Text styling
  textStyle: GoogleFonts.jetBrainsMono(fontSize: 14),

  // AI Completion styling
  aiCompletionTextStyle: TextStyle(
    color: Colors.grey, // Change the color of the AI completion text
    fontStyle: FontStyle.italic, // Make the AI completion text italic
  ),
  
  // Selection & cursor
  selectionStyle: CodeSelectionStyle(
    cursorColor: Colors.white,
    selectionColor: Colors.blue.withOpacity(0.3),
    cursorBubbleColor: Colors.blue,
  ),
  
  // Gutter (line numbers & fold icons)
  gutterStyle: GutterStyle(
    lineNumberStyle: TextStyle(color: Colors.grey),
    backgroundColor: Color(0xFF1E1E1E),
    activeLineNumberColor: Colors.white,
    foldedIconColor: Colors.grey,
    unfoldedIconColor: Colors.grey,
    errorLineNumberColor: Colors.red,
    warningLineNumberColor: Colors.orange,
  ),
  
  // Suggestion popup
  suggestionStyle: SuggestionStyle(
    backgroundColor: Color(0xFF252526),
    textStyle: TextStyle(color: Colors.white),
    elevation: 8,
  ),
  
  // Hover documentation
  hoverDetailsStyle: HoverDetailsStyle(
    backgroundColor: Color(0xFF252526),
    textStyle: TextStyle(color: Colors.white),
  ),

  // Highlight matching text using [controller.findWord()] and [controller.findRegex()]
  matchHighlightStyle: const MatchHighlightStyle(
    currentMatchStyle: TextStyle(
      backgroundColor: Color(0xFFFFA726),
    ),
    otherMatchStyle: TextStyle(
      backgroundColor: Color(0x55FFFF00),
    ),
  ),
)
```

### Feature Toggles

```dart
CodeForge(
  // Enable/disable features
  enableFolding: true,        // Code folding
  enableGutter: true,         // Line numbers
  enableGuideLines: true,     // Indentation guides
  enableGutterDivider: false, // Gutter separator line
  enableSuggestions: true,    // Autocomplete
  
  // Behavior
  readOnly: false,            // Read-only mode
  autoFocus: true,            // Auto-focus on mount
  lineWrap: false,            // Line wrapping
)
```
</details>

---

<details>
<summary><h2>📚 API Reference</h2></summary>

### CodeForge Widget

| Property | Type | Description |
|----------|------|-------------|
| `controller` | `CodeForgeController?` | Text and selection controller |
| `undoController` | `UndoRedoController?` | Undo/redo history controller |
| `language` | `Mode?` | Syntax highlighting language |
| `editorTheme` | `Map<String, TextStyle>?` | Syntax color theme |
| `textStyle` | `TextStyle?` | Base text style |
| `lspConfig` | `LspConfig?` | LSP server configuration |
| `aiCompletion` | `AiCompletion?` | AI completion settings |
| `filePath` | `String?` | File path for LSP |
| `initialText` | `String?` | Initial editor content |
| `readOnly` | `bool` | Read-only mode |
| `enableFolding` | `bool` | Enable code folding |
| `enableGutter` | `bool` | Show line numbers |
| `enableGuideLines` | `bool` | Show indentation guides |
| `selectionStyle` | `CodeSelectionStyle?` | Selection styling |
| `gutterStyle` | `GutterStyle?` | Gutter styling |
| `suggestionStyle` | `SuggestionStyle?` | Suggestion popup styling |
| `hoverDetailsStyle` | `HoverDetailsStyle?` | Hover popup styling |
| `matchHighlightStyle` | `MatchHighlightStyle?` | Highlight the matching words <br> in the controller.findWord() API |

### CodeForgeController

```dart
final controller = CodeForgeController();

// Text operations
controller.text = 'Hello, World!';
String content = controller.text;

// Selection
controller.selection = TextSelection(baseOffset: 0, extentOffset: 5);

// Line operations
int lineCount = controller.lineCount;
String line = controller.getLineText(0);
int lineStart = controller.getLineStartOffset(0);

// Folding
controller.foldAll();
controller.unfoldAll();
controller.toggleFold(lineNumber);

// Search
controller.searchHighlights = [
  SearchHighlight(start: 0, end: 5, color: Colors.yellow),
];
```

### GutterStyle

```dart
GutterStyle({
  TextStyle? lineNumberStyle,
  Color? backgroundColor,
  double? gutterWidth,
  IconData foldedIcon,
  IconData unfoldedIcon,
  double? foldingIconSize,
  Color? foldedIconColor,
  Color? unfoldedIconColor,
  Color? activeLineNumberColor,
  Color? inactiveLineNumberColor,
  Color errorLineNumberColor,
  Color warningLineNumberColor,
  Color? foldedLineHighlightColor,
})
```

### CodeSelectionStyle

```dart
CodeSelectionStyle({
  Color? cursorColor,
  Color selectionColor,
  Color cursorBubbleColor,
})
```

### SuggestionStyle
```dart
SuggestionStyle(
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  backgroundColor: Colors.grey[900]!,
  focusColor: Colors.blue.withOpacity(0.3),
  hoverColor: Colors.blue.withOpacity(0.1),
  splashColor: Colors.blue.withOpacity(0.2),
  textStyle: TextStyle(color: Colors.white),
)
```

### HoverDetailsStyle
```dart
HoverDetailsStyle(
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  backgroundColor: Colors.grey[850]!,
  focusColor: Colors.blue.withOpacity(0.3),
  hoverColor: Colors.blue.withOpacity(0.1),
  splashColor: Colors.blue.withOpacity(0.2),
  textStyle: TextStyle(color: Colors.white),
)
```

### MatchHighlightStyle
```dart
matchHighlightStyle: const MatchHighlightStyle(
  currentMatchStyle: TextStyle(
    backgroundColor: Color(0xFFFFA726),
  ),
  otherMatchStyle: TextStyle(
    backgroundColor: Color(0x55FFFF00),
  ),
),
```

</details>

---
<details>
<summary><h2>⌨️ Keyboard Shortcuts</h2></summary>
CodeForge supports a variety of keyboard shortcuts for efficient editing:

### Editing
- **Ctrl+C** — Copy selected text
- **Ctrl+X** — Cut selected text
- **Ctrl+V** — Paste text
- **Ctrl+A** — Select all text
- **Ctrl+D** — Duplicate current line
- **Ctrl+Z** — Undo last action
- **Ctrl+Y** — Redo last action
- **Ctrl+Backspace** — Delete word backward
- **Ctrl+Delete** — Delete word forward

### Navigation
- **Ctrl+Arrow Left** — Move cursor to previous word
- **Ctrl+Arrow Right** — Move cursor to next word
- **Ctrl+Shift+Arrow Left** — Select to previous word
- **Ctrl+Shift+Arrow Right** — Select to next word
- **Ctrl+Shift+Arrow Up** — Move current line up
- **Ctrl+Shift+Arrow Down** — Move current line down

### Indentation
- **Tab** — Indent current line or accept AI completion/suggestion
- **Shift+Tab** — Unindent current line

### Suggestions & AI Completion
- **Ctrl+.** — Show available code actions
- **Arrow Up/Down** — Navigate through suggestions
- **Enter/Tab** — Accept current suggestion
- **Escape** — Close suggestions or hover details

### Selection
- **Shift+Arrow Keys** — Extend selection
- **Shift+Home** — Select to line start
- **Shift+End** — Select to line end

</details>

---

## 🤝 Contributing

Contributions are welcome! Whether it's bug fixes, new features, or documentation improvements.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/code_forge/blob/main/LICENSE) file for details.

---

## 🙏 Acknowledgments

- [re_highlight](https://pub.dev/packages/re_highlight) — Syntax highlighting
- [markdown_widget](https://pub.dev/packages/markdown_widget) — Markdown rendering
- [web_socket_channel](https://pub.dev/packages/web_socket_channel) — WebSocket support

---

<p align="center">
  <strong>Built with ❤️ for the Flutter community</strong>
</p>

<p align="center">
  <a href="https://github.com/heckmon/code_forge">
    <img src="https://img.shields.io/badge/⭐_Star_on_GitHub-333333?style=for-the-badge&logo=github" alt="Star on GitHub"/>
  </a>
</p>
