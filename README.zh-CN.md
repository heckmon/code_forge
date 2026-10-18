<p align="left">
  <strong>语言:</strong>
  <a href="./README.md">English</a> |
  <a href="./README.zh-CN.md">简体中文</a> |
  <a href="./README.es.md">Español</a>
</p>

<h1 align="center">CodeForge</h1>

<p align="center">
  <strong>功能强大、特性丰富的代码编辑器组件.</strong>
</p>

<p align="center">
  <em>在 Flutter 应用中带来接近 VS Code 的编辑体验</em>
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
  <img src="https://raw.githubusercontent.com/heckmon/code_forge/refs/heads/main/gifs/1M.gif" alt="CodeForge Demo" width="800"/><sub><br>在 100 万+ 行代码中依然流畅编辑，测试设备为老旧低端 PC（奔腾双核，无独显）。</sub>
</p>
<p align="center">
  <img src="https://raw.githubusercontent.com/heckmon/code_forge/refs/heads/main/gifs/code_forge_100k.gif" alt="CodeForge Demo" width="800"/><sub><br>基于 LSP 的 10 万+ 行智能懒加载高亮</sub>
</p>

### 功能演示: [CodeForge Features Showcase](https://heckmon.github.io/code_forge_demo/)

## 为什么选择 CodeForge?

**CodeForge** 是面向开发者的新一代代码编辑器组件。无论你在做 IDE、代码片段查看器，还是教学平台，CodeForge 都能提供强大能力。

| 功能 | CodeForge | 其他组件 |
|---------|:---------:|:------:|
| 语法高亮 | 180+ 语言 | ✅ |
| 代码折叠 | 智能检测 | 有限 |
| LSP 集成 | 完整支持 | ❌ |
| AI 补全 | 多模型 | ❌ |
| 语义高亮 | 实时 | ❌ |
| 诊断信息 | 行内错误 | ❌ |
| 撤销/重做 | 智能分组 | 基础 |
| 主题定制 | 全量可定制 | 有限 |

### 差异化优势
- 使用 Rope 数据结构处理大文本，性能更稳定。
- 使用 Flutter 底层 `RenderBox` 和 `ParagraphBuilder` 渲染，而不是 `TextField`。
- 内置 [Language Server Protocol](https://microsoft.github.io/language-server-protocol/) 客户端。
- 支持 AI 代码补全。

---

## 安装

1. 在 `pubspec.yaml` 中添加依赖:

```yaml
dependencies:
  code_forge: ^11.1.0
```

2. 然后执行:

```bash
flutter pub get
```

---

## 快速开始

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
          language: langPython,
          editorTheme: atomOneDarkTheme,
        ),
      ),
    );
  }
}
```

## 控制器示例

```dart
class _EditorState extends State<Editor> {
  final _controller = CodeForgeController();
  final _undoController = UndoRedoController();

  @override
  Widget build(BuildContext context) {
    return CodeForge(
      controller: _controller,
      undoController: _undoController,
    );
  }
}
```

---

## 11.0.0 版本更新

- 移除了 Rust 和 FFI 依赖，改为纯 Dart 实现。
- 现在直接支持 Web，不再需要
  [code_forge_web](https://pub.dev/packages/code_forge_web)。
- 显著提升性能并缩短构建时间。

## 安装

在 `pubspec.yaml` 中添加依赖，然后运行 `flutter pub get`：

```yaml
dependencies:
  code_forge: ^11.3.0
```

## 快速开始

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
          language: langPython,
          editorTheme: atomOneDarkTheme,
        ),
      ),
    );
  }
}
```

## Web 构建

浏览器无法访问本地文件系统路径。Web 构建中不能使用 `filePath`，请使用
`fileUrl` 加载远程文件内容：

```dart
CodeForge(
  fileUrl: 'https://example.com/files/main.dart',
  controller: controller,
)
```

若要在 Web 中启用 LSP，请使用 `LspSocketConfig`，并将 LSP 服务器通过
WebSocket 暴露出来。同时提供 `fileUri`（或在 LSP 配置中设置 URI）作为
虚拟文档标识：

```dart
final controller = CodeForgeController(
  lspConfig: LspSocketConfig(
    workspacePath: 'file:///workspace',
    languageId: 'dart',
    serverUrl: 'ws://localhost:9000',
  ),
);

CodeForge(
  controller: controller,
  fileUrl: 'https://raw.githubusercontent.com/heckmon/code_forge/main/lib/code_forge/controller.dart',
  fileUri: 'file:///workspace/controller.dart',
)
```

浏览器不能通过 stdio 启动 LSP 进程，可以使用
[`lsp-ws-proxy`](https://github.com/qualified/lsp-ws-proxy)：

```bash
./lsp-ws-proxy --listen 0.0.0.0:9000 -- dart language-server --protocol=lsp
```

为了获得更好的性能，建议使用 `flutter build web --wasm` 构建。

## LSP 集成

CodeForge 内置 LSP 客户端，支持智能补全、悬停文档、诊断信息、语义高亮、
代码动作、签名帮助、内联提示、跳转到定义和符号重命名。桌面应用可以
使用 `LspStdioConfig.start`，也可以使用 `LspSocketConfig` 连接 WebSocket。

```dart
final lspConfig = LspSocketConfig(
  workspacePath: '/path/to/project',
  languageId: 'python',
  serverUrl: 'ws://localhost:5656',
);

final controller = CodeForgeController(lspConfig: lspConfig);

CodeForge(
  controller: controller,
  filePath: '/path/to/project/main.py',
)
```

原生平台使用 `filePath` 标识真实文件；Web 平台使用 `fileUrl` 下载内容，
并使用 `fileUri` 标识 LSP 服务器中的虚拟文档。

## 自定义

可以通过主题、`GutterStyle`、`CodeSelectionStyle`、`SuggestionStyle`、
`HoverDetailsStyle` 和 `MatchHighlightStyle` 定制编辑器。还可以提供
`finderBuilder`、代码片段、右键菜单项以及自定义滚动控制器。

### LSP 补全建议构建器

`lspSuggestionBuilder` 可以替换每一条 LSP 补全建议的内容，并允许使用
自定义图标：

```dart
CodeForge(
  lspSuggestionBuilder: (context, suggestion, isSelected) {
    return Row(
      children: [
        Icon(Icons.code, color: isSelected ? Colors.white : Colors.amber),
        const SizedBox(width: 8),
        Expanded(child: Text(suggestion.label)),
      ],
    );
  },
)
```

`suggestion.itemType` 表示 LSP 类型（例如 `method`、`class_`、`variable`、
`keyword`），`suggestion.completionItem` 保存服务器返回的原始数据。如果
builder 为 `null`，则继续使用默认建议行和 `pubspec.yaml` 中声明的 TTF
图标。编辑器仍然负责自定义内容外围的选中、悬停和点击行为。

## API 参考

`CodeForge` 的重要属性包括：`controller`、`editorTheme`、`language`、
`textStyle`、`innerPadding`、`selectionStyle`、`gutterStyle`、
`suggestionStyle`、`lspSuggestionBuilder`、`hoverDetailsStyle`、
`matchHighlightStyle`、`filePath`、`fileUri`、`fileUrl`、`initialText`、
`readOnly`、`lineWrap`、`autoFocus`、`enableFolding`、`enableGuideLines`、
`enableGutter`、`enableSuggestions`、`enableKeyboardSuggestions`、
`customCodeSnippets`、`customContextMenuItems`、`finderBuilder` 和
`deleteFoldRangeOnDeletingFirstLine`。

`CodeForgeController` 支持文本和选区编辑、撤销/重做、搜索、滚动、代码折叠、
多光标、ghost text 以及 LSP 操作。所有方法和类型请查看
[完整 API 文档](https://pub.dev/documentation/code_forge/latest/)。

## 键盘快捷键

CodeForge 内置编辑、导航、缩进、选择、LSP 补全和签名帮助快捷键，可以通过
`CodeForgeKeyboardShortcuts` 自定义。

## 搜索、许可证和示例

编辑器支持搜索与替换、匹配高亮、代码折叠、诊断信息和 RTL 语言。更多完整
示例请查看[英文 README](./README.md)和
[功能演示](https://heckmon.github.io/code_forge_demo/)。CodeForge 使用 MIT
许可证发布。
