part of 'lsp.dart';

/// minimal requirements for LSP transport mode
abstract class LspTransport {
  Stream<Map<String, dynamic>> get stream;
  Future<void> send(Map<String, dynamic> message);
  void dispose();
}

/// process content-length and I/O of a process
class StdioTransport extends LspTransport {
  final Process _process;
  final StreamController<Map<String, dynamic>> _responseController =
      StreamController.broadcast();
  final List<int> _buffer = [];
  bool _isSending = false;

  StdioTransport(this._process) {
    _process.stdout.listen(_handleStdoutData);
    _process.stderr.listen((data) => debugPrint(utf8.decode(data)));
  }
  void _handleStdoutData(List<int> data) {
    _buffer.addAll(data);
    while (_buffer.isNotEmpty) {
      final headerEnd = _findHeaderEnd();
      if (headerEnd == -1) return;
      final header = utf8.decode(_buffer.sublist(0, headerEnd));
      final contentLength = int.parse(
        RegExp(r'Content-Length: (\d+)').firstMatch(header)?.group(1) ?? '0',
      );
      if (_buffer.length < headerEnd + 4 + contentLength) return;
      final messageStart = headerEnd + 4;
      final messageEnd = messageStart + contentLength;
      final messageBytes = _buffer.sublist(messageStart, messageEnd);
      _buffer.removeRange(0, messageEnd);
      try {
        final json = jsonDecode(utf8.decode(messageBytes));
        _responseController.add(json);
      } catch (e) {
        throw FormatException(
          'Invalid JSON message $e',
          utf8.decode(messageBytes),
        );
      }
    }
  }
  @override
  Future<void> send(Map<String, dynamic> message) async {
    final completer = Completer<void>();
    Future<void> sendOperation() async {
      try {
        final body = utf8.encode(jsonEncode(message));
        final header = utf8.encode('Content-Length: ${body.length}\r\n\r\n');
        final combined = <int>[...header, ...body];
        _process.stdin.add(combined);
        await _process.stdin.flush();
        completer.complete();
      } catch (e) {
        completer.completeError(e);
      }
    }

    if (!_isSending) {
      _isSending = true;
      await sendOperation();
      _isSending = false;
    } else {
      while (_isSending) {
        await Future.delayed(const Duration(microseconds: 100));
      }
      _isSending = true;
      await sendOperation();
      _isSending = false;
    }

    return completer.future;
  }

  int _findHeaderEnd() {
    final endSequence = [13, 10, 13, 10];
    for (var i = 0; i <= _buffer.length - endSequence.length; i++) {
      if (List.generate(
        endSequence.length,
        (j) => _buffer[i + j],
      ).every((byte) => endSequence.contains(byte))) {
        return i;
      }
    }
    return -1;
  }

  @override
  Stream<Map<String, dynamic>> get stream => _responseController.stream;

  @override
  void dispose() {
    _process.kill();
    _responseController.close();
  }


}

// simple transport mode for socket
class SocketTransport extends LspTransport {
  final WebSocketChannel _channel;
  final StreamController<Map<String, dynamic>> _controller =
      StreamController.broadcast();

  SocketTransport(this._channel) {
    _channel.stream.listen((data) {
      _controller.add(jsonDecode(data as String));
    });
  }

  @override
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  @override
  Future<void> send(Map<String, dynamic> message) async =>
      _channel.sink.add(jsonEncode(message));

  @override
  void dispose() {
    _channel.sink.close();
    _controller.close();
  }
}
