import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:web_socket_channel/web_socket_channel.dart';

part 'lsp_socket.dart';
part 'lsp_stdio.dart';

sealed class LspConfig {
  /// The file path of the document to be processed by the LSP.
  final String filePath;

  /// The language ID of the language.
  ///
  /// languageId depends on the server you are using.
  /// For example, for rust-analyzer give "rust", for pyright-langserver, it is 'python' and so on.
  final String languageId;

  /// The workspace path of the document to be processed by the LSP.
  ///
  /// The workspacePath is the root directory of the project or workspace.
  /// If you are using a single file, you can set it to the parent directory of the file.
  final String workspacePath;

  /// Whether to disable warnings from the LSP server.
  final bool disableWarning;

  /// Whether to disable errors from the LSP server.
  final bool disableError;

  final StreamController<Map<String, dynamic>> _responseController =
      StreamController.broadcast();
  int _nextId = 1;
  final _openDocuments = <String, int>{};

  /// The semantic token types legend from the server.
  /// This is populated during initialization and used to decode token type indices.
  List<String>? _serverTokenTypes;

  /// The semantic token modifiers legend from the server.
  List<String>? _serverTokenModifiers;

  /// Stream of responses from the LSP server.
  /// Use this to listen for notifications like diagnostics.
  Stream<Map<String, dynamic>> get responses => _responseController.stream;

  /// The server's semantic token types legend.
  /// Returns null if not yet initialized.
  List<String>? get serverTokenTypes => _serverTokenTypes;

  /// The server's semantic token modifiers legend.
  /// Returns null if not yet initialized.
  List<String>? get serverTokenModifiers => _serverTokenModifiers;

  LspConfig({
    required this.filePath,
    required this.workspacePath,
    required this.languageId,
    this.disableWarning = false,
    this.disableError = false,
  });

  void dispose();

  Future<Map<String, dynamic>> _sendRequest({
    required String method,
    required Map<String, dynamic> params,
  });

  Future<void> _sendNotification({
    required String method,
    required Map<String, dynamic> params,
  });

  /// This method is used to initialize the LSP server.
  ///
  /// This method is used internally by the [CodeCrafter] widget and calling it directly is not recommended.
  /// It may crash the LSP server if called multiple times.
  Future<void> initialize() async {
    final workspaceUri = Uri.directory(workspacePath).toString();
    final response = await _sendRequest(
      method: 'initialize',
      params: {
        'processId': pid,
        'rootUri': workspaceUri,
        'workspaceFolders': [
          {'uri': workspaceUri, 'name': 'workspace'},
        ],
        'capabilities': {
          'textDocument': {
            'completion': {
              'completionItem': {'snippetSupport': false},
            },
            'synchronization': {'didSave': true},
            'hover': {
              'contentFormat': ['markdown'],
            },
            'semanticTokens': {
              'dynamicRegistration': false,
              'tokenTypes': sematicMap['tokenTypes'],
              'tokenModifiers': sematicMap['tokenModifiers'],
              'formats': ['relative'],
              'requests': {
                'full': {'delta': false},
                'range': true,
              },
              'multilineTokenSupport': true,
              'overlappingTokenSupport': false,
              'augmentsSyntaxTokens': true,
            },
          },
        },
      },
    );

    if (response['error'] != null) {
      throw Exception('Initialization failed: ${response['error']}');
    }

    final capabilities = response['result']?['capabilities'];
    final semanticTokensProvider = capabilities?['semanticTokensProvider'];
    if (semanticTokensProvider != null) {
      final legend = semanticTokensProvider['legend'];
      if (legend != null) {
        _serverTokenTypes = List<String>.from(legend['tokenTypes'] ?? []);
        _serverTokenModifiers = List<String>.from(
          legend['tokenModifiers'] ?? [],
        );
      }
    }

    await _sendNotification(method: 'initialized', params: {});
  }

  Map<String, dynamic> _commonParams(int line, int character) {
    return {
      'textDocument': {'uri': Uri.file(filePath).toString()},
      'position': {'line': line, 'character': character},
    };
  }

  /// Opens the document in the LSP server.
  ///
  /// This method is used internally by the [CodeCrafter] widget and calling it directly is not recommended.
  ///
  /// If [initialContent] is provided, it will be used as the document content.
  /// Otherwise, the content will be read from [filePath].
  Future<void> openDocument({String? initialContent}) async {
    final version = (_openDocuments[filePath] ?? 0) + 1;
    _openDocuments[filePath] = version;
    final String text = initialContent ?? await File(filePath).readAsString();
    await _sendNotification(
      method: 'textDocument/didOpen',
      params: {
        'textDocument': {
          'uri': Uri.file(filePath).toString(),
          'languageId': languageId,
          'version': version,
          'text': text,
        },
      },
    );
    await Future.delayed(Duration(milliseconds: 300));
  }

  /// Updates the document content in the LSP server.
  ///
  /// Sends a 'didChange' notification to the LSP server with the new [content].
  /// If the document is not open, this method does nothing.
  Future<void> updateDocument(String content) async {
    if (!_openDocuments.containsKey(filePath)) {
      return; // Apply language-specific overrides
    }

    final version = _openDocuments[filePath]! + 1;
    _openDocuments[filePath] = version;

    await _sendNotification(
      method: 'textDocument/didChange',
      params: {
        'textDocument': {
          'uri': Uri.file(filePath).toString(),
          'version': version,
        },
        'contentChanges': [
          {'text': content},
        ],
      },
    );
  }

  /// Saves the document in the LSP server.
  ///
  /// Sends a 'didSave' notification to the LSP server with the current [content].
  Future<void> saveDocument(String content) async {
    await _sendNotification(
      method: 'textDocument/didSave',
      params: {
        'textDocument': {'uri': Uri.file(filePath).toString()},
        'text': content,
      },
    );
  }

  /// Updates the document in the LSP server if there is any change.
  /// ///
  /// This method is used internally by the [CodeCrafter] widget and calling it directly is not recommended.
  Future<void> closeDocument() async {
    if (!_openDocuments.containsKey(filePath)) return;

    await _sendNotification(
      method: 'textDocument/didClose',
      params: {
        'textDocument': {'uri': Uri.file(filePath).toString()},
      },
    );
    _openDocuments.remove(filePath);
  }

  /// Shuts down the LSP server gracefully.
  ///
  /// Sends a 'shutdown' request to the LSP server. This should be called before exiting the server.
  Future<void> shutdown() async {
    await _sendRequest(method: 'shutdown', params: {});
  }

  /// Exits the LSP server process.
  ///
  /// Sends an 'exit' notification to the LSP server. This should be called after shutdown.
  Future<void> exitServer() async {
    await _sendNotification(method: 'exit', params: {});
  }

  /// This method is used to get completions at a specific position in the document.
  ///
  /// This method is used internally by the [CodeCrafter], calling this with appropriate parameters will returns a [List] of [LspCompletion].
  Future<List<LspCompletion>> getCompletions(int line, int character) async {
    List<LspCompletion> completion = [];
    final response = await _sendRequest(
      method: 'textDocument/completion',
      params: _commonParams(line, character),
    );
    try {
      final result = response['result'];
      if (result == null) return completion;

      final items = result['items'];
      if (items == null || items is! List) return completion;

      for (var item in items) {
        final importUris = item['data']?['importUris'];
        final List<String>? importUriList = importUris != null
            ? (importUris as List).map((e) => e.toString()).toList()
            : null;

        completion.add(
          LspCompletion(
            label: item['label'],
            itemType: CompletionItemType.values.firstWhere(
              (type) => type.value == item['kind'],
              orElse: () => CompletionItemType.text,
            ),
            importUri: importUriList,
            reference: item["data"]?["ref"],
          ),
        );
      }
    } on Exception catch (e) {
      debugPrint("An Error Occured: $e");
    }
    return completion;
  }

  /// This method is used to get details at a specific position in the document.
  ///
  /// This method is used internally by the [CodeCrafter], calling this with appropriate parameters will returns a [String].
  /// If the LSP server does not support hover or the location provided is invalid, it will return an empty string.
  Future<String> getHover(int line, int character) async {
    final response = await _sendRequest(
      method: 'textDocument/hover',
      params: _commonParams(line, character),
    );
    final contents = response['result']?['contents'];
    if (contents == null || contents.isEmpty) return '';
    if (contents is String) return contents;
    if (contents is Map && contents.containsKey('value')) {
      return contents['value'] ?? '';
    }
    if (contents is List && contents.isNotEmpty) {
      return contents
          .map((item) {
            if (item is String) return item;
            if (item is Map && item.containsKey('value')) return item['value'];
            return '';
          })
          .join('\n');
    }
    return '';
  }

  /// Gets the definition location for a symbol at the specified position.
  ///
  /// Returns a map with location information, or an empty map if not found.
  Future<Map<String, dynamic>> getDefinition(int line, int character) async {
    final response = await _sendRequest(
      method: 'textDocument/definition',
      params: _commonParams(line, character),
    );
    if (response['result'] == null) return {};
    return response['result']?[0] ?? '';
  }

  /// Gets all references to a symbol at the specified position.
  ///
  /// Returns a list of reference locations, or an empty list if none found.
  Future<List<dynamic>> getReferences(int line, int character) async {
    final params = _commonParams(line, character);
    params['context'] = {'includeDeclaration': true};
    final response = await _sendRequest(
      method: 'textDocument/references',
      params: params,
    );
    if (response['result'] == null || response['result'].isEmpty) return [];
    return response['result'];
  }

  /// Gets all semantic tokens for the document.
  ///
  /// Returns a list of [LspSemanticToken] objects representing syntax tokens for highlighting.
  Future<List<LspSemanticToken>> getSemanticTokensFull() async {
    final response = await _sendRequest(
      method: 'textDocument/semanticTokens/full',
      params: {
        'textDocument': {'uri': Uri.file(filePath).toString()},
      },
    );

    final tokens = response['result']?['data'];
    if (tokens is! List) return [];
    return _decodeSemanticTokens(tokens);
  }

  List<LspSemanticToken> _decodeSemanticTokens(List<dynamic> data) {
    final result = <LspSemanticToken>[];
    int line = 0, start = 0;

    for (int i = 0; i < data.length; i += 5) {
      final deltaLine = data[i];
      final deltaStart = data[i + 1];
      final length = data[i + 2];
      final tokenType = data[i + 3];
      final tokenModifiers = data[i + 4];

      line += deltaLine as int;
      start = deltaLine == 0 ? start + deltaStart : deltaStart;

      String? tokenTypeName;
      if (_serverTokenTypes != null && tokenType < _serverTokenTypes!.length) {
        tokenTypeName = _serverTokenTypes![tokenType];
      }

      result.add(
        LspSemanticToken(
          line: line,
          start: start,
          length: length,
          typeIndex: tokenType,
          modifierBitmask: tokenModifiers,
          tokenTypeName: tokenTypeName,
        ),
      );
    }

    return result;
  }
}

enum CompletionItemType {
  text(1),
  method(2),
  function(3),
  constructor(4),
  field(5),
  variable(6),
  class_(7),
  interface(8),
  module(9),
  property(10),
  unit(11),
  value_(12),
  enum_(13),
  keyword(14),
  snippet(15),
  color(16),
  file(17),
  reference(18),
  folder(19),
  enumMember(20),
  constant(21),
  struct(22),
  event(23),
  operator(24),
  typeParameter(25);

  final int value;
  const CompletionItemType(this.value);
}

Map<CompletionItemType, Icon> completionItemIcons = {
  CompletionItemType.text: Icon(Icons.text_snippet_rounded, color: Colors.grey),
  CompletionItemType.method: Icon(
    CustomIcons.method,
    color: const Color(0xff9e74c0),
  ),
  CompletionItemType.function: Icon(
    CustomIcons.method,
    color: const Color(0xff9e74c0),
  ),
  CompletionItemType.constructor: Icon(
    CustomIcons.method,
    color: const Color(0xff9e74c0),
  ),
  CompletionItemType.field: Icon(
    CustomIcons.field,
    color: const Color(0xff75beff),
  ),
  CompletionItemType.variable: Icon(
    CustomIcons.variable,
    color: const Color(0xff75beff),
  ),
  CompletionItemType.class_: Icon(
    CustomIcons.class_,
    color: const Color(0xffee9d28),
  ),
  CompletionItemType.interface: Icon(CustomIcons.interface, color: Colors.grey),
  CompletionItemType.module: Icon(Icons.folder_special, color: Colors.grey),
  CompletionItemType.property: Icon(Icons.build, color: Colors.grey),
  CompletionItemType.unit: Icon(Icons.view_module, color: Colors.grey),
  CompletionItemType.value_: Icon(Icons.numbers, color: Colors.grey),
  CompletionItemType.enum_: Icon(
    CustomIcons.enum_,
    color: const Color(0xffee9d28),
  ),
  CompletionItemType.keyword: Icon(CustomIcons.keyword, color: Colors.grey),
  CompletionItemType.snippet: Icon(CustomIcons.snippet, color: Colors.grey),
  CompletionItemType.color: Icon(Icons.color_lens, color: Colors.grey),
  CompletionItemType.file: Icon(Icons.insert_drive_file, color: Colors.grey),
  CompletionItemType.reference: Icon(CustomIcons.reference, color: Colors.grey),
  CompletionItemType.folder: Icon(Icons.folder, color: Colors.grey),
  CompletionItemType.enumMember: Icon(
    CustomIcons.enum_,
    color: const Color(0xff75beff),
  ),
  CompletionItemType.constant: Icon(
    CustomIcons.constant,
    color: const Color(0xff75beff),
  ),
  CompletionItemType.struct: Icon(
    CustomIcons.struct,
    color: const Color(0xff75beff),
  ),
  CompletionItemType.event: Icon(
    CustomIcons.event,
    color: const Color(0xffee9d28),
  ),
  CompletionItemType.operator: Icon(CustomIcons.operator, color: Colors.grey),
  CompletionItemType.typeParameter: Icon(
    CustomIcons.parameter,
    color: const Color(0xffee9d28),
  ),
};

class CustomIcons {
  static const IconData method = IconData(0xe900, fontFamily: 'Method');
  static const IconData variable = IconData(0xe900, fontFamily: 'Variable');
  static const IconData class_ = IconData(0xe900, fontFamily: 'Class');
  static const IconData enum_ = IconData(0x900, fontFamily: 'Enum');
  static const IconData keyword = IconData(0x900, fontFamily: 'KeyWord');
  static const IconData reference = IconData(0x900, fontFamily: 'Reference');
  static const IconData constant = IconData(0x900, fontFamily: 'Constant');
  static const IconData struct = IconData(0x900, fontFamily: 'Struct');
  static const IconData event = IconData(0x900, fontFamily: 'Event');
  static const IconData operator = IconData(0x900, fontFamily: 'Operator');
  static const IconData parameter = IconData(0x900, fontFamily: 'Parameter');
  static const IconData snippet = IconData(0x900, fontFamily: 'Snippet');
  static const IconData interface = IconData(0x900, fontFamily: 'Interface');
  static const IconData field = IconData(0x900, fontFamily: 'Field');

  /// Loads all custom icon fonts for the code_forge package.
  /// Call [CustomIcons.loadAllCustomFonts] before using any custom icons.
  static Future<void> loadAllCustomFonts() async {
    final fonts = <String, String>{
      'Method': 'assets/icons/method.ttf',
      'Variable': 'assets/icons/variable.ttf',
      'Class': 'assets/icons/class.ttf',
      'Enum': 'assets/icons/enum.ttf',
      'KeyWord': 'assets/icons/keyword.ttf',
      'Reference': 'assets/icons/reference.ttf',
      'Constant': 'assets/icons/constant.ttf',
      'Struct': 'assets/icons/struct.ttf',
      'Event': 'assets/icons/event.ttf',
      'Operator': 'assets/icons/operator.ttf',
      'Parameter': 'assets/icons/parameter.ttf',
      'Snippet': 'assets/icons/snippet.ttf',
      'Interface': 'assets/icons/interface.ttf',
      'Field': 'assets/icons/field.ttf',
    };
    for (final entry in fonts.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(rootBundle.load('packages/code_forge/${entry.value}'));
      await loader.load();
    }
  }
}

/// Represents a completion item in the LSP (Language Server Protocol).
/// This class is used internally by the [CodeCrafter] widget to display completion suggestions.
class LspCompletion {
  /// The label of the completion item, which is displayed in the completion suggestions.
  final String label;

  /// The type of the completion item, which determines the icon and color used to represent it.
  /// The icon is determined by the [completionItemIcons] map.
  final CompletionItemType itemType;

  /// The icon associated with the completion item, determined by its type.
  final Icon icon;

  /// [reference] specifies the symbol or entity within the codebase that this item refers to.
  final String? reference;

  /// [importUri] provides the URI needed to import the file where the referenced item is defined.
  final List<String>? importUri;

  LspCompletion({
    required this.label,
    required this.itemType,
    this.reference,
    this.importUri,
  }) : icon = Icon(
         completionItemIcons[itemType]!.icon,
         color: completionItemIcons[itemType]!.color,
         size: 18,
       );

  Map<String, dynamic> toJson() => {
    "label": label,
    "itemType": itemType,
    "reference": reference,
    "importUri": importUri,
  };

  @override
  String toString() => toJson().toString();
}

/// Represents an error in the LSP (Language Server Protocol).
/// This class is used internally by the [CodeCrafter] widget to display errors in the editor.
class LspErrors {
  /// The severity of the error, which can be one of the following:
  /// - 1: Error
  /// - 2: Warning
  /// - 3: Information
  /// - 4: Hint
  final int severity;

  /// The range of the error in the document, represented as a map with keys 'start' and 'end'.
  /// The 'start' and 'end' keys are maps with 'line' and 'character' keys.
  final Map<String, dynamic> range;

  /// The message describing the error.
  String message;

  LspErrors({
    required this.severity,
    required this.range,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'severity': severity,
    'range': range,
    'message': message,
  };

  @override
  String toString() => toJson().toString();
}

class LspSemanticToken {
  final int line;
  final int start;
  final int length;
  final int typeIndex;
  final int modifierBitmask;

  /// The actual token type name from the server's legend (e.g., 'namespace', 'function', etc.)
  /// This is populated from the server's semanticTokensProvider.legend.tokenTypes list.
  final String? tokenTypeName;

  LspSemanticToken({
    required this.line,
    required this.start,
    required this.length,
    required this.typeIndex,
    required this.modifierBitmask,
    this.tokenTypeName,
  });

  int get end => start + length;

  Map<String, dynamic> toJson() => {
    'line': line,
    'start': start,
    'length': length,
    'typeIndex': typeIndex,
    'tokenTypeName': tokenTypeName,
    'modifierBitmask': modifierBitmask,
  };

  @override
  String toString() => toJson().toString();
}

const sematicMap = {
  'requests': {'full': true, 'range': true},
  'tokenTypes': [
    'namespace',
    'type',
    'class',
    'enum',
    'interface',
    'struct',
    'typeParameter',
    'parameter',
    'variable',
    'property',
    'enumMember',
    'event',
    'function',
    'method',
    'macro',
    'keyword',
    'modifier',
    'comment',
    'string',
    'number',
    'regexp',
    'operator',
    'decorator',
  ],
  'tokenModifiers': [
    'declaration',
    'definition',
    'readonly',
    'static',
    'deprecated',
    'abstract',
    'async',
    'modification',
    'documentation',
    'defaultLibrary',
  ],
};

const Map<String, List<String>> semanticToHljs = {
  'class': ['built_in', 'type'],
  'type': ['built_in', 'type'],
  'namespace': ['built_in', 'type'],
  'interface': ['built_in', 'type'],
  'struct': ['attr', 'attribute'],
  'enum': ['built_in', 'type'],
  'function': ['section', 'function', 'bullet', 'selector-tag', 'selector-id'],
  'method': ['section', 'function', 'bullet', 'selector-tag', 'selector-id'],
  'decorator': ['meta', 'meta-keyword'],
  'variable': ['attr', 'attribute'],
  'parameter': ['attr', 'attribute'],
  'property': ['attr', 'attribute'],
  'typeParameter': ['attr', 'attribute'],
  'enumMember': ['attr', 'attribute'],
  'operator': ['keyword'],
  'keyword': ['keyword'],
  'modifier': ['keyword'],
  'string': ['string'],
  'comment': ['comment'],
  'number': ['number'],
  'regexp': ['regexp'],
  'macro': ['meta', 'meta-keyword'],
  'event': ['attr', 'attribute'],
};

/// Pyright-specific overrides for semantic token mappings.
/// Pyright uses some token types differently than the LSP standard.
///```dart
///const Map<String, List<String>> pyrightSemanticOverrides = {
///  // Pyright uses 'enumMember' for function/method names
///  'method': ['attr', 'attribute'],
///};
///```

/// Get the semantic token mapping for a specific language server.
/// Returns the standard mapping with any server-specific overrides applied.
Map<String, List<String>> getSemanticMapping(String languageId) {
  final baseMap = Map<String, List<String>>.from(semanticToHljs);

  // Apply language-specific overrides
  switch (languageId) {
    // case 'rust':
    //   baseMap.addAll(rustAnalyzerOverrides);
    //   break;
    // case 'typescript':
    // case 'javascript':
    //   // typescript-language-server follows standard mappings
    //   break;
  }

  return baseMap;
}
