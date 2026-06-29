<p align="left">
  <strong>语言:</strong>
  <a href="./README.md">English</a> |
  <a href="./README.zh-CN.md">简体中文</a> |
  <a href="./README.es.md">Español</a>
</p>

<h1 align="center">CodeForge</h1>

<p align="center">
  <strong>功能强大、特性丰富的代码编辑器组件，后端基于 Rust</strong>
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

> [!NOTE]
>
> code_forge **不支持** Flutter Web，因为核心功能依赖 `dart:io`。如需 Web 支持，请使用 [code_forge_web](https://pub.dev/packages/code_forge_web)。

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

1. 安装 [rustup](https://rustup.rs/) 并确保已加入 `PATH`。

2. 在 `pubspec.yaml` 中添加依赖:

```yaml
dependencies:
  code_forge: ^10.7.0
```

3. 在 `main()` 中添加初始化:

```dart
void main() async {
  await RustLib.init();
  runApp(const MyApp());
}
```

4. 然后执行:

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

更多高级能力（LSP 配置、代码动作、重命名、颜色选择器等）请参考英文文档: [README.md](./README.md)
