import 'package:flutter/material.dart';

import 'controller.dart';
import 'styling.dart';

/// Controller for managing text search functionality in [CodeForge].
///
/// This controller handles searching for text, navigating through matches,
/// and highlighting results in the editor.
class FindController extends ChangeNotifier {
  final CodeForgeController _codeController;

  List<Match> _matches = [];
  int _currentMatchIndex = -1;
  bool _isRegex = false;
  bool _caseSensitive = false;
  bool _matchWholeWord = false;
  String _lastQuery = '';

  String _lastText = '';
  VoidCallback? _controllerListener;

  /// Creates a [FindController] associated with the given [CodeForgeController].
  FindController(this._codeController) {
    _lastText = _codeController.text;
    _controllerListener = _onCodeControllerChanged;
    _codeController.addListener(_controllerListener!);
  }

  @override
  void dispose() {
    if (_controllerListener != null) {
      _codeController.removeListener(_controllerListener!);
    }
    super.dispose();
  }

  void _onCodeControllerChanged() {
    final currentText = _codeController.text;
    if (currentText != _lastText) {
      _lastText = currentText;
      _reperformSearch();
    }
  }

  /// The number of matches found for the current query.
  int get matchCount => _matches.length;

  /// The current match index (0-based) or -1 if no match is selected.
  int get currentMatchIndex => _currentMatchIndex;

  /// The case sensitivity of the search.
  bool get caseSensitive => _caseSensitive;

  /// Whether the search uses regular expressions.
  bool get isRegex => _isRegex;

  /// Whether the search matches whole words only.
  bool get matchWholeWord => _matchWholeWord;

  /// Sets the case sensitivity of the search.
  set caseSensitive(bool value) {
    if (_caseSensitive == value) return;
    _caseSensitive = value;
    _reperformSearch();
    notifyListeners();
  }

  /// Sets whether the search uses regular expressions.
  set isRegex(bool value) {
    if (_isRegex == value) return;
    _isRegex = value;
    _reperformSearch();
    notifyListeners();
  }

  /// Sets whether the search matches whole words only.
  set matchWholeWord(bool value) {
    if (_matchWholeWord == value) return;
    _matchWholeWord = value;
    _reperformSearch();
    notifyListeners();
  }

  void _reperformSearch() {
    if (_lastQuery.isNotEmpty) {
      find(_lastQuery, scrollToMatch: false);
    }
  }

  /// Performs a text search.
  ///
  /// [query] is the text to search for.
  /// [scrollToMatch] determines if the editor should scroll to the selected match.
  void find(String query, {bool scrollToMatch = true}) {
    _lastQuery = query;

    if (query.isEmpty) {
      _clearMatches();
      return;
    }

    final text = _codeController.text;
    String pattern = query;

    if (!_isRegex) {
      pattern = RegExp.escape(pattern);
    }

    if (_matchWholeWord) {
      pattern = r'\b' + pattern + r'\b';
    }

    try {
      final regExp = RegExp(
        pattern,
        caseSensitive: _caseSensitive,
        multiLine: true,
      );

      _matches = regExp.allMatches(text).toList();
    } catch (e) {
      _matches = [];
      _currentMatchIndex = -1;
      _updateHighlights();
      notifyListeners();
      return;
    }
    if (_matches.isEmpty) {
      _currentMatchIndex = -1;
      _updateHighlights();
      notifyListeners();
      return;
    }

    final cursor = _codeController.selection.start;
    int index = 0;
    bool found = false;

    for (int i = 0; i < _matches.length; i++) {
      if (_matches[i].start >= cursor) {
        index = i;
        found = true;
        break;
      }
    }

    _currentMatchIndex = found ? index : 0;

    _updateHighlights();

    if (scrollToMatch) {
      _scrollToCurrentMatch();
    }
    notifyListeners();
  }

  /// Moves to the next match.
  void next() {
    if (_matches.isEmpty) return;
    _currentMatchIndex = (_currentMatchIndex + 1) % _matches.length;
    _scrollToCurrentMatch();
    _updateHighlights();
  }

  /// Moves to the previous match.
  void previous() {
    if (_matches.isEmpty) return;
    _currentMatchIndex =
        (_currentMatchIndex - 1 + _matches.length) % _matches.length;
    _scrollToCurrentMatch();
    _updateHighlights();
  }

  /// Clears search results and highlights.
  void clear() {
    _lastQuery = '';
    _clearMatches();
  }

  /// Replaces the currently selected match with [replacement].
  void replace(String replacement) {
    if (_currentMatchIndex < 0 || _currentMatchIndex >= _matches.length) return;

    final match = _matches[_currentMatchIndex];
    _codeController.replaceRange(match.start, match.end, replacement);
  }

  /// Replaces all matches with [replacement].
  void replaceAll(String replacement) {
    if (_matches.isEmpty) return;

    final text = _codeController.text;
    String pattern = _lastQuery;

    if (!_isRegex) {
      pattern = RegExp.escape(_lastQuery);
    }

    if (_matchWholeWord) {
      pattern = '\\b$pattern\\b';
    }

    try {
      final regExp = RegExp(pattern, caseSensitive: _caseSensitive);
      final newText = text.replaceAll(regExp, replacement);

      _codeController.replaceRange(0, text.length, newText);
    } catch (e) {
      debugPrint('FindController: Replace All failed. Error: $e');
    }
  }

  void _clearMatches() {
    _matches = [];
    _currentMatchIndex = -1;
    _codeController.searchHighlights = [];
    _codeController.searchHighlightsChanged = true;
    _codeController.notifyListeners();
    notifyListeners();
  }

  void _scrollToCurrentMatch() {
    if (_currentMatchIndex >= 0 && _currentMatchIndex < _matches.length) {
      final match = _matches[_currentMatchIndex];
      _codeController.setSelectionSilently(
        TextSelection(baseOffset: match.start, extentOffset: match.end),
      );
      _codeController.selectionOnly = true;
      _codeController.notifyListeners();
    }
  }

  void _updateHighlights() {
    final highlights = <SearchHighlight>[];

    for (int i = 0; i < _matches.length; i++) {
      final match = _matches[i];
      final isCurrent = i == _currentMatchIndex;

      highlights.add(
        SearchHighlight(
          start: match.start,
          end: match.end,
          isCurrentMatch: isCurrent,
        ),
      );
    }

    _codeController.searchHighlights = highlights;
    _codeController.searchHighlightsChanged = true;
    _codeController.notifyListeners();
    notifyListeners();
  }
}
