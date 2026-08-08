<p align="left">
  <strong>Idioma:</strong>
  <a href="./README.md">English</a> |
  <a href="./README.zh-CN.md">简体中文</a> |
  <a href="./README.es.md">Español</a>
</p>

<h1 align="center">CodeForge</h1>

<p align="center">
  <strong>Un widget de editor de codigo potente y completo, con backend en Rust</strong>
</p>

<p align="center">
  <em>Lleva una experiencia de edicion tipo VS Code a tus apps Flutter</em>
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
  <img src="https://raw.githubusercontent.com/heckmon/code_forge/refs/heads/main/gifs/1M.gif" alt="CodeForge Demo" width="800"/><sub><br>Edicion fluida en archivos de mas de 1M lineas, probado en un PC antiguo de bajos recursos.</sub>
</p>
<p align="center">
  <img src="https://raw.githubusercontent.com/heckmon/code_forge/refs/heads/main/gifs/code_forge_100k.gif" alt="CodeForge Demo" width="800"/><sub><br>Resaltado inteligente y diferido con LSP en archivos de 100k+ lineas</sub>
</p>

### Demo de funciones: [CodeForge Features Showcase](https://heckmon.github.io/code_forge_demo/)

> [!NOTE]
>
> code_forge **no** es compatible con Flutter web porque depende de `dart:io` para funciones principales. Para web, usa [code_forge_web](https://pub.dev/packages/code_forge_web).


## Por que CodeForge?

**CodeForge** es un widget de editor de codigo de nueva generacion para desarrolladores exigentes. Ya sea que construyas un IDE, un visor de snippets o una plataforma educativa, CodeForge ofrece herramientas avanzadas.

| Funcion | CodeForge | Otros |
|---------|:---------:|:------:|
| Resaltado de sintaxis | 180+ lenguajes | ✅ |
| Plegado de codigo | Deteccion inteligente | Limitado |
| Integracion LSP | Soporte completo | ❌ |
| Autocompletado con IA | Multi-modelo | ❌ |
| Tokens semanticos | En tiempo real | ❌ |
| Diagnosticos | Errores inline | ❌ |
| Deshacer/Rehacer | Agrupacion inteligente | Basico |
| Temas | Totalmente personalizable | Limitado |

### Que hace diferente a CodeForge
- Usa estructura de datos rope para manejar texto grande con mejor rendimiento.
- Renderiza con `RenderBox` y `ParagraphBuilder` en lugar de `TextField`.
- Incluye cliente integrado de [Language Server Protocol](https://microsoft.github.io/language-server-protocol/).
- Soporta autocompletado de codigo con IA.

---

## Instalacion

1. Instala [rustup](https://rustup.rs/) y asegurate de que este en `PATH`.

2. Agrega CodeForge a `pubspec.yaml`:

```yaml
dependencies:
  code_forge: ^10.10.3
```

3. Agrega la inicializacion en `main()`:

```dart
void main() async {
  await RustLib.init();
  runApp(const MyApp());
}
```

4. Luego ejecuta:

```bash
flutter pub get
```

---

## Inicio rapido

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

## Ejemplo con controlador

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

Para detalles avanzados (configuracion LSP, acciones de codigo, renombrado, selector de color y mas), consulta la documentacion en ingles: [README.md](./README.md)
