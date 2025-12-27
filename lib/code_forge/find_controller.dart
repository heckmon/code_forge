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

  /// Creates a [FindController] associated with the given [CodeForgeController].
  FindController(this._codeController);

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
      find(_lastQuery);
    }
  }

  /// Performs a text search.
  ///
  /// [query] is the text to search for.
  void find(String query) {
    _lastQuery = query;

    if (query.isEmpty) {
      _clearMatches();
      return;
    }

    final text = _codeController.text;
    String pattern = query;

    if (!_isRegex) {
      pattern = RegExp.escape(query);
    }

    if (_matchWholeWord) {
      // Look for word boundaries
      pattern = '\\b$pattern\\b';
    }

    try {
      final regExp = RegExp(pattern, caseSensitive: _caseSensitive);
      _matches = regExp.allMatches(text).toList();
    } catch (e) {
      // Invalid regex or pattern
      _matches = [];
      debugPrint('FindController: Invalid regex pattern: $pattern. Error: $e');
    }

    if (_matches.isEmpty) {
      _currentMatchIndex = -1;
    } else {
      // Try to find the match closest to the current cursor position
      final currentSelectionStart = _codeController.selection.start;
      int closestIndex = 0;

      for (int i = 0; i < _matches.length; i++) {
        final match = _matches[i];
        if (match.start >= currentSelectionStart) {
          closestIndex = i;
          break;
        }
      }
      _currentMatchIndex = closestIndex;
    }

    _updateHighlights();
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

  void _clearMatches() {
    _matches = [];
    _currentMatchIndex = -1;
    _codeController.searchHighlights = [];
    _codeController.searchHighlightsChanged = true;
    _codeController.notifyListeners(); // Ensure UI clears highlights
    notifyListeners();
  }

  void _scrollToCurrentMatch() {
    if (_currentMatchIndex >= 0 && _currentMatchIndex < _matches.length) {
      final match = _matches[_currentMatchIndex];
      _codeController.setSelectionSilently(
        TextSelection(baseOffset: match.start, extentOffset: match.end),
      );
      // Changing selection typically triggers ensureVisible in the editor logic
      // providing selectionOnly logic is handled in code_area.
      // We explicitly set selectionOnly to true to force scroll to cursor
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
