<p align="left">
  <strong>Idioma:</strong>
  <a href="./README.md">English</a> |
  <a href="./README.zh-CN.md">简体中文</a> |
  <a href="./README.es.md">Español</a>
</p>

<h1 align="center">CodeForge</h1>

<p align="center">
  <strong>Un widget de editor de codigo potente y completo.</strong>
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

1. Agrega CodeForge a `pubspec.yaml`:

```yaml
dependencies:
  code_forge: ^11.1.0
```

2. Luego ejecuta:

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

## Novedades de la version 11.0.0

- Se elimino Rust y sus dependencias FFI; ahora el editor usa implementaciones
  Dart puras.
- Se agrego soporte web directo, sin necesidad del paquete
  [code_forge_web](https://pub.dev/packages/code_forge_web).
- Se mejoro el rendimiento y se redujo el tiempo de compilacion.

## Instalacion

Agrega CodeForge a `pubspec.yaml` y ejecuta `flutter pub get`:

```yaml
dependencies:
  code_forge: ^11.1.0
```

## Uso rapido

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

## Compilaciones web

En el navegador no existe acceso a rutas del sistema de archivos. Usa
`fileUrl` para cargar el contenido remoto; `filePath` no esta disponible en
compilaciones web:

```dart
CodeForge(
  fileUrl: 'https://example.com/files/main.dart',
  controller: controller,
)
```

Para habilitar LSP en web, usa `LspSocketConfig` y un servidor LSP expuesto
mediante WebSocket. Proporciona un URI virtual con `fileUri` (o configura el
URI en el servidor) para que el servidor pueda identificar el documento:

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

Un proceso LSP no puede iniciarse con stdio desde el navegador. Puedes usar
[`lsp-ws-proxy`](https://github.com/qualified/lsp-ws-proxy):

```bash
./lsp-ws-proxy --listen 0.0.0.0:9000 -- dart language-server --protocol=lsp
```

Para obtener un mejor rendimiento, compila con `flutter build web --wasm`.

## Integracion LSP

CodeForge incluye un cliente LSP con autocompletado, documentacion al pasar el
raton, diagnosticos, resaltado semantico, acciones de codigo, ayuda de firma,
pistas en linea, ir a definicion y renombrado. Admite `LspSocketConfig` para
WebSocket y `LspStdioConfig.start` para aplicaciones de escritorio.

```dart
final lspConfig = LspSocketConfig(
  workspacePath: '/ruta/al/proyecto',
  languageId: 'python',
  serverUrl: 'ws://localhost:5656',
);

final controller = CodeForgeController(lspConfig: lspConfig);

CodeForge(
  controller: controller,
  filePath: '/ruta/al/proyecto/main.py',
)
```

En aplicaciones nativas, `filePath` identifica el archivo real. En web,
combina `fileUrl` para descargar el contenido con `fileUri` para el documento
virtual del servidor.

## Personalizacion

Todos los elementos principales se pueden personalizar mediante temas,
`GutterStyle`, `CodeSelectionStyle`, `SuggestionStyle`,
`HoverDetailsStyle` y `MatchHighlightStyle`. Tambien puedes proporcionar un
`finderBuilder`, snippets, elementos de menu contextual y controladores de
desplazamiento.

### Constructor de sugerencias LSP

`lspSuggestionBuilder` permite reemplazar el contenido de cada fila de
autocompletado LSP y elegir tus propios iconos:

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

`suggestion.itemType` indica el tipo LSP (`method`, `class_`, `variable`,
`keyword`, etc.) y `suggestion.completionItem` contiene los datos originales
del servidor. Si el builder es `null`, se mantiene la fila predeterminada y
los iconos TTF declarados en `pubspec.yaml`. El editor conserva la seleccion,
el hover y el comportamiento de toque alrededor del contenido personalizado.

## Referencia de API

Propiedades importantes de `CodeForge`: `controller`, `editorTheme`,
`language`, `textStyle`, `innerPadding`, `selectionStyle`, `gutterStyle`,
`suggestionStyle`, `lspSuggestionBuilder`, `hoverDetailsStyle`,
`matchHighlightStyle`, `filePath`, `fileUri`, `fileUrl`, `initialText`,
`readOnly`, `lineWrap`, `autoFocus`, `enableFolding`, `enableGuideLines`,
`enableGutter`, `enableSuggestions`, `enableKeyboardSuggestions`,
`customCodeSnippets`, `customContextMenuItems`, `finderBuilder` y
`deleteFoldRangeOnDeletingFirstLine`.

El `CodeForgeController` permite editar texto y selecciones, deshacer y
rehacer, buscar, desplazarse, plegar codigo, gestionar varios cursores,
usar ghost text y ejecutar las funciones LSP. Consulta la
[documentacion completa de la API](https://pub.dev/documentation/code_forge/latest/)
para ver todos los metodos y tipos.

## Atajos de teclado

CodeForge incluye atajos para editar, navegar, cambiar la sangria, seleccionar
texto, mostrar sugerencias LSP y solicitar ayuda de firma. Se pueden
personalizar mediante `CodeForgeKeyboardShortcuts`.

## Busqueda, licencia y ejemplos

El editor incluye busqueda y reemplazo, resaltado de coincidencias, plegado,
diagnosticos y soporte RTL. Consulta el [README en ingles](./README.md) y la
[demostracion de funciones](https://heckmon.github.io/code_forge_demo/) para
ver ejemplos completos. CodeForge se distribuye bajo la licencia MIT.
