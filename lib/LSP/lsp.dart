import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:web_socket_channel/web_socket_channel.dart';

part 'lsp_socket.dart';
part 'lsp_stdio.dart';

sealed class LspConfig {
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
  List<String>? _serverTokenTypes;
  List<String>? _serverTokenModifiers;

  bool isIntialized = false;

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
    required this.workspacePath,
    required this.languageId,
    this.disableWarning = false,
    this.disableError = false,
  });

  @override
  bool operator ==(Object other) {
    return (other is LspConfig &&
        languageId == other.languageId &&
        workspacePath == other.workspacePath &&
        disableError == other.disableError &&
        disableWarning == other.disableWarning);
  }

  @override
  int get hashCode =>
      Object.hash(languageId, workspacePath, disableError, disableWarning);

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
  /// This method is used internally by the [CodeForge] widget and calling it directly is not recommended.
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
        'initializationOptions': {
          'highlight': {'enabled': true},
        },
        'capabilities': {
          'workspace': {'applyEdit': true},
          'textDocument': {
            'completion': {
              'completionItem': {
                'resolveSupport': {
                  'properties': [
                    'documentaion',
                    'detail',
                    'additionalTextEdits',
                  ],
                },
                'snippetSupport': false,
              },
            },
            'signatureHelp': {
              'dynamicRegistration': false,
              'signatureInformation': {
                'documentationFormat': ['markdown', 'plaintext'],
                'parameterInformation': {'labelOffsetSupport': true},
                'activeParameterSupport': true,
              },
              'contextSupport': true,
            },
            'synchronization': {'didSave': true, 'change': 1},
            'publishDiagnostics': {'relatedInformation': true},
            'hover': {
              'contentFormat': ['markdown'],
            },
            'semanticTokens': {
              'dynamicRegistration': false,
              'tokenTypes': sematicMap['tokenTypes'],
              'tokenModifiers': sematicMap['tokenModifiers'],
              'formats': ['relative'],
              'requests': {'full': true, 'range': true},
              'multilineTokenSupport': true,
              'overlappingTokenSupport': false,
              'augmentsSyntaxTokens': true,
            },
          },
        },
      },
    );

    if (response['error'] != null) {
      isIntialized = false;
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
    isIntialized = true;
  }

  Map<String, dynamic> _commonParams(String filePath, int line, int character) {
    return {
      'textDocument': {'uri': Uri.file(filePath).toString()},
      'position': {'line': line, 'character': character},
    };
  }

  /// Opens the document in the LSP server.
  ///
  /// This method is used internally by the [CodeForge] widget and calling it directly is not recommended.
  ///
  /// If [initialContent] is provided, it will be used as the document content.
  /// Otherwise, the content will be read from [filePath].
  Future<void> openDocument(String filePath) async {
    final version = (_openDocuments[filePath] ?? 0) + 1;
    _openDocuments[filePath] = version;
    final String text = await File(filePath).readAsString();
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
  Future<void> updateDocument(String filePath, String content) async {
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
  Future<void> saveDocument(String filePath, String content) async {
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
  /// This method is used internally by the [CodeForge] widget and calling it directly is not recommended.
  Future<void> closeDocument(String filePath) async {
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
  /// This method is used internally by the [CodeForge], calling this with appropriate parameters will returns a [List] of [LspCompletion].
  Future<List<LspCompletion>> getCompletions(
    String filePath,
    int line,
    int character,
  ) async {
    List<LspCompletion> completion = [];
    final response = await _sendRequest(
      method: 'textDocument/completion',
      params: _commonParams(filePath, line, character),
    );
    try {
      final result = response['result'];
      if (result == null) return completion;

      final dynamic items;

      if (result is List) {
        items = result;
      } else {
        items = result['items'];
      }

      if (items == null || items is! List) return completion;

      for (Map<String, dynamic> item in items) {
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
            completionItem: item,
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
  /// This method is used internally by the [CodeForge], calling this with appropriate parameters will returns a [String].
  /// If the LSP server does not support hover or the location provided is invalid, it will return an empty string.
  Future<String> getHover(String filePath, int line, int character) async {
    final response = await _sendRequest(
      method: 'textDocument/hover',
      params: _commonParams(filePath, line, character),
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

  /// Resolves and retrieves additional details for the given LSP completion item.
  ///
  /// Sends a `completionItem/resolve` request to the language server (when
  /// supported) and merges any returned fields (for example `documentation`,
  /// `detail`, and `additionalTextEdits`) into the provided completion item.
  ///
  /// The resolved item is returned so callers can use the enriched information
  /// (for example to display rich documentation, apply additional text edits,
  /// or show a more descriptive detail string).
  ///
  /// Returns a Future that completes with the resolved completion item. Throws an
  /// exception if the resolve request fails or the server returns an error.
  Future<Map<String, dynamic>> resolveCompletionItem(
    Map<String, dynamic> item,
  ) async {
    final response = await _sendRequest(
      method: 'completionItem/resolve',
      params: item,
    );
    return response['result'] ?? item;
  }

  /// Requests signature help information for the given position in a document.
  ///
  /// This method sends a 'textDocument/signatureHelp' request to the language server
  /// with the specified file path, line, character position, and trigger context.
  /// It processes the response to extract signature details, including the label,
  /// documentation, parameters, and active indices.
  ///
  /// - [filePath]: The path to the file for which signature help is requested.
  /// - [line]: The zero-based line number in the document.
  /// - [character]: The zero-based character position in the line.
  /// - [triggerKind]: The kind of trigger that initiated the signature help request
  ///   (e.g., invoked, trigger character, or content change).
  /// - [triggerCharacter]: An optional character that triggered the request, if applicable.
  ///
  /// Returns a [Future<LspSignatureHelps>] containing the signature help information,
  /// including the active signature and parameter indices, label, documentation, and parameters.
  /// If no signatures are available, default empty values are used.
  Future<LspSignatureHelps> getSignatureHelp(
    String filePath,
    int line,
    int character,
    int triggerKind, {
    String? triggerCharacter,
    bool isRetrigger = false,
  }) async {
    final commonParams = _commonParams(filePath, line, character);
    commonParams.addAll({
      'context': {
        'triggerKind': triggerKind,
        if (triggerCharacter != null) 'triggerCharacter': triggerCharacter,
        'isRetrigger': isRetrigger,
      },
    });
    final response = await _sendRequest(
      method: 'textDocument/signatureHelp',
      params: commonParams,
    );

    final result = response['result'];

    if (result == null) {
      return LspSignatureHelps(
        activeParameter: -1,
        activeSignature: -1,
        documentation: "",
        label: "",
        parameters: [],
      );
    }

    final signatures = result['signatures'];
    late final String label, doc;
    late final List<Map<String, dynamic>> parameters;
    if (signatures is List) {
      if (signatures.isNotEmpty) {
        label = (signatures[0]['label']) ?? "";
        final rawParameters = signatures[0]['parameters'];
        if (rawParameters is List) {
          parameters = rawParameters.map((param) {
            if (param is Map<String, dynamic>) {
              return param;
            } else if (param is String) {
              return {'label': param};
            } else {
              return {'label': param['label'] ?? param.toString()};
            }
          }).toList();
        } else {
          parameters = [];
        }

        final docField = signatures[0]['documentation'];
        if (docField is String) {
          doc = docField;
        } else if (docField is Map) {
          doc = docField['value'] ?? "";
        } else {
          doc = "";
        }
      } else {
        label = "";
        doc = "";
        parameters = [];
      }
    } else {
      label = "";
      doc = "";
      parameters = [];
    }
    return LspSignatureHelps(
      activeParameter: (result['activeParameter'] ?? -1) as int,
      activeSignature: (result['activeSignature'] ?? -1) as int,
      documentation: doc,
      label: label,
      parameters: parameters,
    );
  }

  /// Gets the definition location for a symbol at the specified position.
  ///
  /// Returns a map with location information, or an empty map if not found.
  Future<Map<String, dynamic>> getDefinition(
    String filePath,
    int line,
    int character,
  ) async {
    final response = await _sendRequest(
      method: 'textDocument/definition',
      params: _commonParams(filePath, line, character),
    );
    if (response['result'] == null) return {};
    return response['result']?[0] ?? '';
  }

  /// Gets the declaration for a symbol at the specified position.
  ///
  /// Returns a map with location information, or an empty map if not found.
  Future<Map<String, dynamic>> getDeclaration(
    String filePath,
    int line,
    int character,
  ) async {
    final response = await _sendRequest(
      method: 'textDocument/declaration',
      params: _commonParams(filePath, line, character),
    );
    if (response['result'] == null) return {};
    return response['result']?[0] ?? '';
  }

  /// Jumps to the location where the data type of a symbol is defined.
  ///
  /// Returns a map with location information, or an empty map if not found.
  Future<Map<String, dynamic>> getTypeDefinition(
    String filePath,
    int line,
    int character,
  ) async {
    final response = await _sendRequest(
      method: 'textDocument/typeDefinition',
      params: _commonParams(filePath, line, character),
    );
    if (response['result'] == null) return {};
    return response['result']?[0] ?? '';
  }

  /// Gets the implementation locations for a symbol at the specified position.
  ///
  /// Useful for jumping from an interface or abstract method to concrete implementations.
  /// Returns the first location if available, otherwise an empty map.
  Future<Map<String, dynamic>> getImplementation(
    String filePath,
    int line,
    int character,
  ) async {
    final response = await _sendRequest(
      method: 'textDocument/implementation',
      params: _commonParams(filePath, line, character),
    );

    final result = response['result'];
    if (result == null || result.isEmpty) return {};
    return result[0];
  }

  /// Retrieves all symbols defined in the current document.
  ///
  /// This is used for outline views, breadcrumbs, and file structure panels.
  /// Returns either a hierarchical or flat symbol list depending on server support.
  Future<List<dynamic>> getDocumentSymbols(String filePath) async {
    final response = await _sendRequest(
      method: 'textDocument/documentSymbol',
      params: {
        'textDocument': {'uri': Uri.file(filePath).toString()},
      },
    );

    final result = response['result'];
    if (result is! List) return [];
    return result;
  }

  /// Searches for symbols across the entire workspace.
  ///
  /// Used for global symbol search (e.g., Ctrl+T).
  Future<List<dynamic>> getWorkspaceSymbols(String query) async {
    final response = await _sendRequest(
      method: 'workspace/symbol',
      params: {'query': query},
    );

    final result = response['result'];
    if (result is! List) return [];
    return result;
  }

  /// Formats the entire document according to server rules.
  ///
  /// Returns a list of text edits to apply to the document.
  Future<List<dynamic>> formatDocument(String filePath) async {
    final response = await _sendRequest(
      method: 'textDocument/formatting',
      params: {
        'textDocument': {'uri': Uri.file(filePath).toString()},
        'options': {'tabSize': 2, 'insertSpaces': true},
      },
    );

    final result = response['result'];
    if (result is! List) return [];
    return result;
  }

  /// Formats a specific range in the document.
  ///
  /// Useful for formatting selections.
  Future<List<dynamic>> formatRange({
    required String filePath,
    required int startLine,
    required int startCharacter,
    required int endLine,
    required int endCharacter,
  }) async {
    final response = await _sendRequest(
      method: 'textDocument/rangeFormatting',
      params: {
        'textDocument': {'uri': Uri.file(filePath).toString()},
        'range': {
          'start': {'line': startLine, 'character': startCharacter},
          'end': {'line': endLine, 'character': endCharacter},
        },
        'options': {'tabSize': 2, 'insertSpaces': true},
      },
    );

    final result = response['result'];
    if (result is! List) return [];
    return result;
  }

  /// Renames a symbol at the given position across the workspace.
  ///
  /// Returns a workspace edit containing all required text changes.
  Future<Map<String, dynamic>> renameSymbol(
    String filePath,
    int line,
    int character,
    String newName,
  ) async {
    final response = await _sendRequest(
      method: 'textDocument/rename',
      params: {..._commonParams(filePath, line, character), 'newName': newName},
    );

    return response['result'] ?? {};
  }

  /// Checks whether a symbol can be renamed at the given position.
  ///
  /// Returns range and placeholder information, or null if rename is invalid.
  Future<Map<String, dynamic>?> prepareRename(
    String filePath,
    int line,
    int character,
  ) async {
    final response = await _sendRequest(
      method: 'textDocument/prepareRename',
      params: _commonParams(filePath, line, character),
    );

    return response['result'];
  }

  /// Retrieves available code actions at a given range.
  ///
  /// Includes quick fixes, refactors, and source actions.
  Future<List<dynamic>> getCodeActions({
    required String filePath,
    required int startLine,
    required int startCharacter,
    required int endLine,
    required int endCharacter,
    List<Map<String, dynamic>> diagnostics = const [],
  }) async {
    final response = await _sendRequest(
      method: 'textDocument/codeAction',
      params: {
        'textDocument': {'uri': Uri.file(filePath).toString()},
        'range': {
          'start': {'line': startLine, 'character': startCharacter},
          'end': {'line': endLine, 'character': endCharacter},
        },
        'context': {
          'diagnostics': diagnostics,
          if (Platform.isAndroid && filePath.endsWith(".java"))
            'only': [
              'quickfix',
              'refactor.extract',
              'refactor.inline',
              'refactor.rewrite',
            ],
        },
      },
    );

    final result = response['result'];
    if (result is! List) return [];
    return result;
  }

  /// Execute a workspace command on the server
  /// Wrapper around the 'workspace/executeCommand' request.
  Future<void> executeCommand(String command, List<dynamic>? arguments) async {
    await _sendRequest(
      method: 'workspace/executeCommand',
      params: {'command': command, 'arguments': arguments ?? []},
    );
  }

  /// Retrieves document links such as import paths and URLs.
  ///
  /// These links can be clicked to open files or external resources.
  Future<List<dynamic>> getDocumentLinks(String filePath) async {
    final response = await _sendRequest(
      method: 'textDocument/documentLink',
      params: {
        'textDocument': {'uri': Uri.file(filePath).toString()},
      },
    );

    final result = response['result'];
    if (result is! List) return [];
    return result;
  }

  /// Prepares a call hierarchy item at the given position.
  ///
  /// This is required before requesting incoming or outgoing calls.
  Future<Map<String, dynamic>?> prepareCallHierarchy(
    String filePath,
    int line,
    int character,
  ) async {
    final response = await _sendRequest(
      method: 'textDocument/prepareCallHierarchy',
      params: _commonParams(filePath, line, character),
    );

    final result = response['result'];
    if (result is! List || result.isEmpty) return null;
    return result.first;
  }

  /// Retrieves incoming calls for a call hierarchy item.
  Future<List<dynamic>> getIncomingCalls(Map<String, dynamic> item) async {
    final response = await _sendRequest(
      method: 'callHierarchy/incomingCalls',
      params: {'item': item},
    );

    final result = response['result'];
    if (result is! List) return [];
    return result;
  }

  /// Retrieves outgoing calls for a call hierarchy item.
  Future<List<dynamic>> getOutgoingCalls(Map<String, dynamic> item) async {
    final response = await _sendRequest(
      method: 'callHierarchy/outgoingCalls',
      params: {'item': item},
    );

    final result = response['result'];
    if (result is! List) return [];
    return result;
  }

  /// Prepares a type hierarchy item at the given position.
  Future<Map<String, dynamic>?> prepareTypeHierarchy(
    String filePath,
    int line,
    int character,
  ) async {
    final response = await _sendRequest(
      method: 'textDocument/prepareTypeHierarchy',
      params: _commonParams(filePath, line, character),
    );

    final result = response['result'];
    if (result is! List || result.isEmpty) return null;
    return result.first;
  }

  /// Retrieves supertypes (base classes / interfaces).
  Future<List<dynamic>> getSupertypes(Map<String, dynamic> item) async {
    final response = await _sendRequest(
      method: 'typeHierarchy/supertypes',
      params: {'item': item},
    );

    final result = response['result'];
    if (result is! List) return [];
    return result;
  }

  /// Retrieves subtypes (derived classes / implementations).
  Future<List<dynamic>> getSubtypes(Map<String, dynamic> item) async {
    final response = await _sendRequest(
      method: 'typeHierarchy/subtypes',
      params: {'item': item},
    );

    final result = response['result'];
    if (result is! List) return [];
    return result;
  }

  /// Gets all references to a symbol at the specified position.
  ///
  /// Returns a list of reference locations, or an empty list if none found.
  Future<List<dynamic>> getReferences(
    String filePath,
    int line,
    int character,
  ) async {
    final params = _commonParams(filePath, line, character);
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
  Future<List<LspSemanticToken>> getSemanticTokensFull(String filePath) async {
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
/// This class is used internally by the [CodeForge] widget to display completion suggestions.
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

  /// The raw completion details returned by the LSP server.
  Map<String, dynamic> completionItem;

  LspCompletion({
    required this.label,
    required this.itemType,
    required this.completionItem,
    this.reference,
    this.importUri,
  }) : icon = Icon(
         completionItemIcons[itemType]!.icon,
         color: completionItemIcons[itemType]!.color,
         size: 18,
       );

  Map<String, dynamic> toJson() => completionItem;

  @override
  String toString() => toJson().toString();
}

/// Represents an error in the LSP (Language Server Protocol).
/// This class is used internally by the [CodeForge] widget to display errors in the editor.
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

class LspSignatureHelps {
  final int activeParameter, activeSignature;
  final String documentation, label;
  final List<Map<String, dynamic>> parameters;

  LspSignatureHelps({
    required this.activeParameter,
    required this.activeSignature,
    required this.documentation,
    required this.label,
    required this.parameters,
  });
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
  'struct': ['built_in', 'type'],
  'enum': ['built_in', 'type'],
  'function': ['section', 'function', 'bullet', 'selector-tag', 'selector-id'],
  'method': ['section', 'function', 'bullet', 'selector-tag', 'selector-id'],
  'decorator': ['meta', 'meta-keyword'],
  'variable': ['attr', 'attribute'],
  'parameter': ['attr', 'attribute'],
  'property': ['attr', 'attribute'],
  'field': ['attr', 'attribute'],
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
  'constant': ['number', 'literal'],
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
