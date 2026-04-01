import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

class TextMateSidecarConfig {
  final String executablePath;
  final String onigWasmPath;
  final List<String> packDirs;
  final String theme;

  const TextMateSidecarConfig({
    required this.executablePath,
    required this.onigWasmPath,
    required this.packDirs,
    required this.theme,
  });
}

class TextMateEdit {
  final int startLine;
  final int startChar;
  final int endLine;
  final int endChar;
  final String text;

  const TextMateEdit({
    required this.startLine,
    required this.startChar,
    required this.endLine,
    required this.endChar,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
    'startLine': startLine,
    'startChar': startChar,
    'endLine': endLine,
    'endChar': endChar,
    'text': text,
  };
}

class TextMateLineTokens {
  final int line;
  final int lineLength;
  /// Raw `tokenizeLine2` output: `[startIndex0, metadata0, startIndex1, metadata1, ...]`.
  final List<int> tokens;

  const TextMateLineTokens({
    required this.line,
    required this.lineLength,
    required this.tokens,
  });

  factory TextMateLineTokens.fromJson(Map<String, dynamic> json) {
    return TextMateLineTokens(
      line: json['line'] as int,
      lineLength: json['lineLength'] as int,
      tokens: (json['tokens'] as List).cast<int>(),
    );
  }
}

class TextMateSidecarStatus {
  final List<String> themes;
  final List<String> scopes;
  final List<String> colorMap;
  final String defaultThemePath;
  final Map<String, String> themeRoles;

  const TextMateSidecarStatus({
    required this.themes,
    required this.scopes,
    required this.colorMap,
    required this.defaultThemePath,
    required this.themeRoles,
  });

  factory TextMateSidecarStatus.fromJson(Map<String, dynamic> json) {
    final rawColorMap = (json['colorMap'] as List?) ?? const [];
    final rawRoles = json['themeRoles'];
    final roles = <String, String>{};
    if (rawRoles is Map) {
      rawRoles.forEach((key, value) {
        if (key is String && value is String) {
          roles[key] = value;
        }
      });
    }
    return TextMateSidecarStatus(
      themes: (json['themes'] as List).cast<String>(),
      scopes: (json['scopes'] as List).cast<String>(),
      colorMap: rawColorMap.map((e) => e is String ? e : '').toList(),
      defaultThemePath: json['defaultThemePath'] as String,
      themeRoles: roles,
    );
  }
}

class TextMateSidecarClient {
  final Process _process;
  final StreamSubscription<String> _stdoutSub;
  final StreamSubscription<String> _stderrSub;
  final StreamSubscription _exitSub;

  int _nextId = 1;
  final Map<int, Completer<dynamic>> _pending = {};

  TextMateSidecarStatus? _status;

  TextMateSidecarStatus? get status => _status;
  List<String> get colorMap => _status?.colorMap ?? const [];

  static const int _maxCachedLinesPerDoc = 1200;
  final Map<String, LinkedHashMap<int, _CachedLineTokens>> _tokenCacheByDoc = {};
  final Set<String> _openDocuments = <String>{};

  TextMateSidecarClient._(
    this._process,
    this._stdoutSub,
    this._stderrSub,
    this._exitSub,
  );

  static Future<TextMateSidecarClient> start(TextMateSidecarConfig config) async {
    final args = <String>[
      for (final dir in config.packDirs) ...['--pack-dir', dir],
      '--theme',
      config.theme,
      '--onig-wasm',
      config.onigWasmPath,
      '--stdio',
    ];

    final process = await Process.start(
      config.executablePath,
      args,
      mode: ProcessStartMode.normal,
      runInShell: false,
    );

    final clientCompleter = Completer<TextMateSidecarClient>();

    late final TextMateSidecarClient client;

    final stdoutLines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final stderrLines = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    late final StreamSubscription<String> stdoutSub;
    late final StreamSubscription<String> stderrSub;
    late final StreamSubscription exitSub;

    stdoutSub = stdoutLines.listen((line) {
      if (line.trim().isEmpty) return;
      Map<String, dynamic> msg;
      try {
        msg = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        return;
      }

      final id = msg['id'];
      if (id is! int) return;
      final c = client._pending.remove(id);
      if (c == null) return;

      if (msg.containsKey('error')) {
        final err = msg['error'];
        c.completeError(StateError(err is Map ? (err['message'] ?? 'Sidecar error').toString() : err.toString()));
        return;
      }
      c.complete(msg['result']);
    });

    stderrSub = stderrLines.listen((line) {
      // Keep stderr visible for debugging but don’t crash the client.
      // ignore: avoid_print
      print('[textmate-sidecar] $line');
    });

    exitSub = process.exitCode.asStream().listen((code) {
      for (final c in client._pending.values) {
        c.completeError(StateError('TextMate sidecar exited with code $code'));
      }
      client._pending.clear();
    });

    client = TextMateSidecarClient._(process, stdoutSub, stderrSub, exitSub);
    clientCompleter.complete(client);

    final statusJson = await client._call('status', const {});
    client._status = TextMateSidecarStatus.fromJson(statusJson as Map<String, dynamic>);

    return clientCompleter.future;
  }

  Future<void> dispose() async {
    try {
      _process.kill(ProcessSignal.sigterm);
    } catch (_) {
      //
    }
    await _stdoutSub.cancel();
    await _stderrSub.cancel();
    await _exitSub.cancel();
  }

  Future<dynamic> _call(String method, Map<String, dynamic> params) {
    final id = _nextId++;
    final c = Completer<dynamic>();
    _pending[id] = c;
    final msg = {'id': id, 'method': method, 'params': params};
    _process.stdin.writeln(jsonEncode(msg));
    return c.future;
  }

  Future<void> openDocument({
    required String docId,
    required String content,
    String? filePath,
    String? scopeName,
    String? language,
  }) async {
    _tokenCacheByDoc.remove(docId);
    await _call('openDocument', {
      'docId': docId,
      'content': content,
      if (filePath != null) 'filePath': filePath,
      if (scopeName != null) 'scopeName': scopeName,
      if (language != null) 'language': language,
    });
    _openDocuments.add(docId);
  }

  Future<void> setDocumentText({
    required String docId,
    required String content,
  }) async {
    _tokenCacheByDoc.remove(docId);
    await _call('setDocumentText', {'docId': docId, 'content': content});
  }

  Future<void> applyEdits({
    required String docId,
    required List<TextMateEdit> edits,
  }) async {
    int? minStartLine;
    for (final e in edits) {
      final s = e.startLine;
      if (minStartLine == null || s < minStartLine) minStartLine = s;
    }
    await _call('applyEdits', {
      'docId': docId,
      'edits': edits.map((e) => e.toJson()).toList(),
    });
    final fromLine = minStartLine ?? 0;
    if (fromLine <= 0) {
      _tokenCacheByDoc.remove(docId);
    } else {
      final cache = _tokenCacheByDoc[docId];
      if (cache != null && cache.isNotEmpty) {
        final keysToRemove = cache.keys.where((k) => k >= fromLine).toList();
        for (final k in keysToRemove) {
          cache.remove(k);
        }
      }
    }
  }

  Future<List<TextMateLineTokens>> tokenizeLines({
    required String docId,
    required int startLine,
    required int endLineExclusive,
  }) async {
    final res = await _call('tokenizeLines', {
      'docId': docId,
      'startLine': startLine,
      'endLineExclusive': endLineExclusive,
    });

    final map = res as Map<String, dynamic>;
    final lines = (map['lines'] as List).cast<Map<String, dynamic>>();
    return lines.map(TextMateLineTokens.fromJson).toList(growable: false);
  }

  /// Cache tokens for later synchronous rendering.
  ///
  /// Provide `lineTextHashes` (lineIndex -> `lineText.hashCode`) when possible
  /// so we can safely reuse cached tokens without risking mismatches.
  void cacheLineTokens({
    required String docId,
    required List<TextMateLineTokens> lines,
    Map<int, int>? lineTextHashes,
  }) {
    final cache = _tokenCacheByDoc.putIfAbsent(
      docId,
      () => LinkedHashMap<int, _CachedLineTokens>(),
    );

    for (final tl in lines) {
      final key = tl.line;
      final entry = _CachedLineTokens(
        tokens: tl,
        textHash: lineTextHashes?[key],
      );
      // Update LRU order by removing before re-inserting.
      cache.remove(key);
      cache[key] = entry;
    }

    while (cache.length > _maxCachedLinesPerDoc) {
      cache.remove(cache.keys.first);
    }
  }

  /// Try to synchronously retrieve tokens for `lineText`.
  ///
  /// We only return cached tokens if we have a matching `textHash` recorded,
  /// to avoid showing incorrect colors for a different line that happens to
  /// share the same length.
  TextMateLineTokens? peekCachedLineTokens({
    required String docId,
    required int line,
    required String lineText,
  }) {
    final cache = _tokenCacheByDoc[docId];
    if (cache == null || cache.isEmpty) return null;
    final entry = cache[line];
    if (entry == null) return null;
    if (entry.tokens.lineLength != lineText.length) return null;
    final hash = entry.textHash;
    if (hash == null || hash != lineText.hashCode) return null;

    // Touch the entry to keep it hot.
    cache.remove(line);
    cache[line] = entry;
    return entry.tokens;
  }

  Future<void> closeDocument(String docId) async {
    _tokenCacheByDoc.remove(docId);
    await _call('closeDocument', {'docId': docId});
    _openDocuments.remove(docId);
  }

  bool isDocumentOpen(String docId) => _openDocuments.contains(docId);
}

class _CachedLineTokens {
  final TextMateLineTokens tokens;
  final int? textHash;

  const _CachedLineTokens({
    required this.tokens,
    required this.textHash,
  });
}

class CodeForgeTextMate {
  static TextMateSidecarClient? _client;

  static TextMateSidecarClient? get client => _client;

  static Map<int, int> _computeLineTextHashesInRange(
    String content, {
    required int startLine,
    required int endLineExclusive,
  }) {
    if (content.isEmpty) return const {};
    if (endLineExclusive <= startLine) return const {};

    final hashes = <int, int>{};

    int line = 0;
    int offset = 0;

    // Fast-forward to `startLine` without splitting the whole document.
    while (line < startLine) {
      final nextNl = content.indexOf('\n', offset);
      if (nextNl == -1) return hashes;
      offset = nextNl + 1;
      line++;
    }

    while (line < endLineExclusive && offset <= content.length) {
      final nextNl = content.indexOf('\n', offset);
      final end = nextNl == -1 ? content.length : nextNl;
      hashes[line] = content.substring(offset, end).hashCode;
      if (nextNl == -1) break;
      offset = nextNl + 1;
      line++;
    }

    return hashes;
  }

  static Future<void> configure(TextMateSidecarConfig config) async {
    await _client?.dispose();
    _client = await TextMateSidecarClient.start(config);
  }

  /// Best-effort warm-up to reduce initial “plain text” frames when opening a file.
  ///
  /// This pre-opens the TextMate document (if needed), tokenizes a small line
  /// range, and caches results with line hashes so the renderer can paint
  /// colored tokens synchronously on the first frame.
  static Future<void> prefetchTokensForFile({
    required String filePath,
    required String content,
    required int startLine,
    required int endLineExclusive,
  }) async {
    final client = _client;
    if (client == null) return;
    if (filePath.isEmpty) return;
    if (endLineExclusive <= startLine) return;

    try {
      if (!client.isDocumentOpen(filePath)) {
        await client.openDocument(
          docId: filePath,
          content: content,
          filePath: filePath,
        );
      }

      final tokenLines = await client.tokenizeLines(
        docId: filePath,
        startLine: startLine,
        endLineExclusive: endLineExclusive,
      );

      if (tokenLines.isEmpty) return;

      final hashes = _computeLineTextHashesInRange(
        content,
        startLine: startLine,
        endLineExclusive: endLineExclusive,
      );
      client.cacheLineTokens(
        docId: filePath,
        lines: tokenLines,
        lineTextHashes: hashes,
      );
    } catch (_) {
      // If the grammar can’t be resolved, or the sidecar isn’t available yet,
      // treat warm-up as a no-op.
      return;
    }
  }
}
