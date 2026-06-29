## 1.0.0

<details>
<summary><h3>🎉 Initial Release</h3></summary>

**CodeForge** is a sophisticated, feature-rich code editor widget for Flutter applications, inspired by VS Code and Monaco Editor. This release introduces a comprehensive set of editing capabilities with modern developer experience features.

### ✨ Core Features

#### 📝 Advanced Text Editing
- **Efficient Text Management**: Uses rope data structures for optimal performance with large files
- **Multi-language Syntax Highlighting**: Support for numerous programming languages via `re_highlight`
- **Code Folding**: Visual fold/unfold indicators with automatic range detection
- **Smart Indentation**: Auto-indentation with customizable behavior
- **Bracket Matching**: Automatic bracket highlighting and matching
- **Line Operations**: Move lines up/down, duplicate lines, smart indentation
- **Word Navigation**: Ctrl+arrow key navigation and word-level deletion

#### 🎨 Customizable UI & Theming
- **Flexible Styling**: Extensive customization options for all UI elements
- **Theme Support**: Built-in VS2015 dark theme with full customization
- **Gutter Customization**: Line numbers, fold icons, error/warning highlighting
- **Selection Styling**: Custom cursor colors, selection highlighting, cursor bubbles
- **Overlay Styling**: Suggestion popups, hover documentation with themes
- **Font Integration**: Custom icon fonts for completion items (auto-loaded)

#### 🔧 Developer Experience
- **Undo/Redo System**: Sophisticated operation merging with timestamp-based grouping
- **Read-only Mode**: Optional read-only editing for display purposes
- **Auto-focus**: Automatic focus on widget mount
- **Line Wrapping**: Configurable line wrapping vs horizontal scrolling
- **Indentation Guides**: Visual guides for code structure
- **Search Highlighting**: Highlight search results and matches

### 🚀 Language Server Protocol (LSP) Integration

- **Full LSP Support**: Complete Language Server Protocol implementation
- **Semantic Highlighting**: Advanced token-based syntax coloring
- **Intelligent Completions**: Context-aware code completion with custom icons
- **Hover Documentation**: Rich hover information with markdown support
- **Diagnostics Integration**: Real-time error and warning display
- **Multiple Server Types**: Support for stdio and WebSocket LSP servers
- **Document Synchronization**: Bidirectional sync with LSP servers
- **Error Gutter**: Visual error/warning indicators in line numbers

### 🤖 AI-Powered Code Completion

- **Multi-Model Support**: Integration with Gemini and extensible to other AI models
- **Completion Modes**: Auto, manual, and mixed completion triggering
- **Smart Debouncing**: Prevents excessive API calls during typing
- **Response Processing**: Intelligent parsing and code cleaning
- **Custom Instructions**: Configurable AI prompts for different use cases
- **Caching**: Response caching for improved performance

### 🎯 Key Capabilities

#### Performance & Efficiency
- **Optimized Rendering**: Custom viewport with efficient repaint management
- **Large File Support**: Handles files of any size with rope-based operations
- **Debounced Operations**: Semantic token updates and AI requests are debounced
- **Memory Efficient**: Minimal memory footprint with smart caching

#### Integration & Extensibility
- **Flutter Native**: Seamless integration with Flutter's text input system
- **Custom Controllers**: Flexible controller architecture for advanced use cases
- **Event Streaming**: LSP response streaming for real-time updates
- **Plugin Architecture**: Extensible design for custom features

#### Accessibility & UX
- **Keyboard Shortcuts**: Full keyboard navigation support
- **Context Menus**: Right-click context menus with copy/paste/select-all
- **Visual Feedback**: Loading states, error handling, and user feedback
- **Mobile Support**: Touch-friendly interactions for mobile platforms

### 📚 Documentation & Examples

- **Comprehensive API Docs**: Fully documented public APIs with examples
- **Example Application**: Complete working example in `/example/`
- **Type Safety**: Strong typing throughout the codebase
- **Error Handling**: Robust error handling with user-friendly messages

### 🔧 Technical Highlights

- **Pure Dart**: No native dependencies, works on all Flutter platforms
- **Widget Architecture**: Built as a proper Flutter widget with state management
- **Custom Rendering**: Optimized rendering pipeline for code editing
- **Test Coverage**: Comprehensive test suite for reliability
- **Linting**: Follows Flutter best practices and linting rules

### 🎨 Supported Languages & Features

**Syntax Highlighting**: Dart, Python, JavaScript, TypeScript, Java, C++, C#, Go, Rust, PHP, Ruby, Swift, Kotlin, Scala, and many more via `re_highlight`

**LSP Servers**: Compatible with any LSP-compliant language server (Dart Analysis Server, Pyright, TypeScript, etc.)

**AI Models**: Gemini integration with extensible architecture for other providers

---

This release establishes **CodeForge** as a powerful, production-ready code editor for Flutter applications, offering the same level of sophistication found in professional code editors while maintaining Flutter's declarative UI paradigm.
</details>

## 1.0.1

- Updated README.md

## 1.0.2
- Updated README.md

## 1.1.0
- Fixed keyboard would not appear in Android.
- Added more public API methods in the controller, such as copy, paste, selectAll, cut, arrow key navigations, etc

## 1.2.0
- FEATURE: Added LSP Code Actions.
- FEATURE: Enhanced AI Completion for large files.
- FEATURE: Added more public method APIs in the controller and the LspConfig class.
- FIX: Completion bug in the first line.

## 1.2.1
- suggestion/code actions persist on screen.

## 1.3.0
- FIX: Editor width had been determined by the width of the longest line, fixed it by using the viewport width.
- FIX: Changed filePath based LSP initialization to workspace based approach to manage multiple files from a single server instance.
- FIX: Tapping the end of the longest line won't focus the editor.

## 1.3.1
- Updated README

## 1.4.0
- FEATURE: Added LSP `completionItem/resolve` to show documentation for completion items.
- FEATURE: Added LSP auto import.
- FEATURE: Theme based dynamic color for suggestion popup.

## 1.5.0
- FIX: Backspace, delete, undo-redo, etc works on read-only mode.

## 2.0.0
- REFACTOR: Moved the LSP configuration and logic from the `CodeForge` to the `CodeForgeController`.
- FIX: Code action persists on mobile.

## 2.1.0
- FEATURE: Added more public APIs in the `CodeForgeController`.

## 2.2.0
- FIX: Asynchronous highlighting.
- FIX: Delayed LSP diagnostic lints.

## 3.0.0
- FEATURE: Find and highlight multiple words with the new `FindWordController` API. Seperate styling is available for both focused **word** and unfocued **words**.
- FEATURE: *Double click to select a word* is now available in desktop also.
- FIX: Code reslove for focused suggestion persists on the screen.
- FIX: Removed cut, paste and other writing operations from read only mode.
- FIX: Line wrap wasn't responsive on resizing the screen.
- FIX: Suggestions persists on cursor movement.

## 4.0.0
- ENHANCEMENT: Enhanced `FindWordController` for efficient word searching.
- FEATURE: Added new `finderBuilder` API to implement the find-replace serach bar.
- FEATURE: Added keyboard shortcuts Ctrl + F and Ctrl + H to show the find-replace search bar.
- FIX: Scroll doesn't work after selecting a word.

## 4.1.0
- FEATURE: Added semantic highlight support for the custom protocol used by the `ccls` language server.

## 4.2.0
- FEATURE: Added LSP signature help.
- ENHANCEMENT: Improved and responsive selection tool bar for mobile.

## 4.3.0
- FEATURE: BiDi support in `Rope` data structure.
- FEATURE: Immutable rope operations - insert and delete.

## 5.0.0
- FEATURE: Added git diff support:
<p align="left">
  <img src="https://raw.githubusercontent.com/heckmon/code_forge/refs/heads/main/gifs/git_diff.png" alt="Git diff" heihght="400" width="400"/>
</p>

- ENHANCEMENT: Removed built-in AI completion and APi calls, user can use `controller.setGhostText()`.
- ENHANCEMENT: Enhanced large text handling.

## 5.0.1
- Updated README

## 5.1.0
- FEATURE: Scoll to the desired line using the `controller.scrollToLine(int line)` API.
- ENHANCEMENT: Removed unused http package.

## 5.2.0
- ENHANCEMENT: Greatly enhanced large text handling.

## 6.0.0
- FIX: [#15](https://github.com/heckmon/code_forge/issues/15)
- FIX: [#16](https://github.com/heckmon/code_forge/issues/16)
- FIX: [#18](https://github.com/heckmon/code_forge/issues/18)
- FIX: Highlight glitch in ccls LSP server.
- FEATURE: Added `enableKeybordSuggestions` and `keyboardType` parameters as requested in [#20](https://github.com/heckmon/code_forge/issues/20)
- ENHANCEMENT: Enahanced large text handling by caching fold ranges and bracket matches.

## 6.1.0
- FEATURE: Added more public API methods to the controller.<br>
    • `duplicateLine()`<br>
    • `moveLineDown()`<br>
    • `moveLineUp()`<br>
    • `callSignatureHelp()`<br>
- ENHANCEMENT: LSP suggestions color

## 7.0.0
- FEATURE: Added `LspClientCapabilities` class to selectively enable/disable LSP features during initialization.<br>
    • `semanticHighlighting` — Enable/disable semantic token highlighting<br>
    • `codeCompletion` — Enable/disable code completion suggestions<br>
    • `hoverInfo` — Enable/disable hover documentation<br>
    • `codeAction` — Enable/disable code actions and quick fixes<br>
    • `signatureHelp` — Enable/disable signature help<br>
    • `documentColor` — Enable/disable document color detection<br>
    • `documentHighlight` — Enable/disable document highlighting<br>
    • `codeFolding` — Enable/disable code folding<br>
    • `inlayHint` — Enable/disable inlay hints<br>
    • `goToDefinition` — Enable/disable "go to definition"<br>
    • `rename` — Enable/disable symbol renaming<br>
- FEATURE: Added `deleteFoldRangeOnDeletingFirstLine` parameter to `CodeForge` widget as requested in [#24](https://github.com/heckmon/code_forge/issues/24). When set to `true`, deleting the entire first line of a folded block will delete the whole folded region.
- ENHANCEMENT: Mobile context menu toolbar now persists after "Select All" action.
- ENHANCEMENT: Repositioned code action bulb icon on mobile to avoid overlap with fold icons and gutter.
- ENHANCEMENT: LSP methods now check capability flags before executing, returning early with appropriate empty values when features are disabled.
- ENHANCEMENT: Dynamic capability building during LSP initialization — only enabled features are advertised to the language server.
- FEATURE: Inlay hints and color picker:<br>
    - Added LSP inlay hints and Colour picker as requested in [#22](https://github.com/heckmon/code_forge/issues/22).<br><br>
    Inlay hint demo: https://github.com/user-attachments/assets/658fd76f-5650-4374-b44d-58db69813e66 <br>
    Color pciker demo: https://github.com/user-attachments/assets/a7e1795c-83ca-411f-9c1d-81c8d4949926

- FEATURE: Added doucment highlight as requested in [#22](https://github.com/heckmon/code_forge/issues/22).<br>
  - demo: https://github.com/user-attachments/assets/593a524f-f5d7-45af-b5a5-d67cc1ed95fa

- FEATURE: Added arrow key navigation for LSP suggestions in mobile as requested in [#21](https://github.com/heckmon/code_forge/issues/21).<br>
   - demo: https://github.com/user-attachments/assets/8237dbdb-ba36-490d-9db2-4ffe1e24da8a

- FIX: [#25](https://github.com/heckmon/code_forge/issues/25)
- FIX: Fixed action icon misposition in mobile as requested in [#23](https://github.com/heckmon/code_forge/issues/23)

## 8.0.0

### ✨ Major Features

#### 🌍 RTL (Right-to-Left) Language Support
- FEATURE: Added comprehensive RTL support for right-to-left languages (Arabic, Hebrew, etc.)
  - Added `textDirection` parameter to `CodeForge` widget to control text layout direction
  - Gutter automatically positions on the right side for RTL mode
  - Text rendering properly aligned for RTL languages with full visual direction support
  - Caret positioning and movement follow visual direction (not logical) for intuitive editing
  - Selection highlighting works correctly for RTL text
  - All UI elements (fold icons, line numbers, indentation guides) properly mirrored for RTL
  - Bracket pair highlighting supports RTL
  - Scroll behavior adapted for RTL layout

#### 🔤 RTL Text Input & Navigation
- FEATURE: Arrow keys follow visual direction for RTL
  - Left arrow visually moves left (logically moves right in RTL)
  - Right arrow visually moves right (logically moves left in RTL)
  - Home key moves to visual line start (line end in RTL)
  - End key moves to visual line end (line start in RTL)
  - Ctrl+Arrow word navigation follows visual direction for RTL
- FEATURE: Arabic and Hebrew word detection for code completion
  - Updated word pattern matching to include Arabic (U+0600-U+06FF), Extended Arabic (U+08A0-U+08FF), and Hebrew (U+0590-U+05FF) Unicode ranges
  - LSP suggestions now work correctly for RTL languages
  - Word cache includes RTL script characters
  - Fold icons display correctly for RTL (< for folded, down arrow for unfolded)

### 🎯 Hover Documentation Improvements
- ENHANCEMENT: Improved hover popup positioning and visibility
  - Hover documentation now positions above cursor if space is limited below
  - Better width constraints and viewport-aware positioning
  - Added hover content caching for improved performance
  - Hover content is fetched asynchronously without blocking rendering
  - Diagonal offset adjustment prevents hover from blocking cursor area
- ENHANCEMENT: Hover triggered by tap on mobile/desktop now persists properly
  - Added `onHoverSetByTap` callback for better tap-based hover handling
  - Hover state properly managed to avoid flicker

### 🔧 Code Improvements & Fixes
- FIX: Auto-indentation now only triggers on single Enter key press
  - Paste operations no longer re-indent pasted multi-line content incorrectly
  - Only the first newline in pasted text triggers auto-indent
- FIX: CCLS semantic highlighting refresh debouncing
  - Added `_scheduleCclsRefresh` with 1 second debounce to avoid excessive document saves
  - CCLS servers that use custom semantic token protocol now work more reliably
- ENHANCEMENT: Better suggestion popup positioning
  - Popup now positions above cursor when limited space below
  - Horizontal alignment adjusted to stay within viewport
  - Improved mobile responsiveness

### 📊 Internal Changes
- Modified paragraph style to respect textDirection property
- Added RTL-aware cache invalidation for paragraph building
- Improved caret info calculation for RTL text positioning
- Enhanced text offset to line/char conversion for RTL
- Selection handle positioning adapted for RTL layout
- Ghost text (AI completion) positioning corrected for RTL
- Inlay hints and document colors properly positioned for RTL

## 8.0.1
- FEATURE: Added `clearAllSuggestions()` API on controller to clear all suggestions.
- Updated README.

## 8.1.0
- ENHANCEMENT: Enhanced RTL support

## 8.1.1
 - FEATURE: added a public API called `acceptSuggestion` in the controller to manually accept LSP suggestions.

## 8.1.2
- FIX: mobile scroll issue in RTL mode.

## 8.2.0
 - FIX: [#36](https://github.com/heckmon/code_forge/issues/36)
 - FIX: [#35](https://github.com/heckmon/code_forge/issues/35)
 - FEATURE: [#33](https://github.com/heckmon/code_forge/issues/33)

## 8.3.0
 - FIX: [#37](https://github.com/heckmon/code_forge/issues/37)
 - FIX: [#36](https://github.com/heckmon/code_forge/issues/36)
 - FEATURE: [#38](https://github.com/heckmon/code_forge/issues/38)

## 8.4.0
 - FEATURE: [#39](https://github.com/heckmon/code_forge/issues/39)
 - FIX: html/xml guide lines.

## 8.4.1
  - Typo fix

## 8.5.0
  - FIX: [#47](https://github.com/heckmon/code_forge/issues/47)
  - FIX: [#41](https://github.com/heckmon/code_forge/issues/41)

## 8.5.1
  - FEATURE: Enhanced Mac keyboard support

## 9.0.0
  - #### FEATURE: Multi-cursor
      - Alt + Click to add multiple cursors in the editor.
      - APIs:
      ```dart
      // Multi-cursor operations
      controller.addMultiCursor(int line, int character);
      controller.clearMultiCursor();
      controller.backspaceAtAllCursors();
      controller.insertAtAllCursors(String textToInsert);

      ```
  - #### FIX: [#43](https://github.com/heckmon/code_forge/issues/43)
  - #### ENHANCEMENT: Virtual lines for git diff removed ranges.
  - #### Added `customCodeSnippets` parameter on the editor to add external code snippets on the suggestions as requested in [#46](https://github.com/heckmon/code_forge/issues/46)

## 9.1.0
  - FIX: [#49](https://github.com/heckmon/code_forge/issues/49)
  - FIX: [#50](https://github.com/heckmon/code_forge/issues/50)

## 9.2.0
  - FEATURE: [#51](https://github.com/heckmon/code_forge/issues/51)
  - FIX: [#53](https://github.com/heckmon/code_forge/issues/53)

## 9.3.0
  - FIX: [#54](https://github.com/heckmon/code_forge/issues/54)
  - FEATURE: Multiple highlight grammars for a single editor instance.

## 9.4.0
  - FIX: [#57](https://github.com/heckmon/code_forge/issues/57)
  - FIX: [#58](https://github.com/heckmon/code_forge/issues/58)
  - FIX: Anchored gutter for `controller.setGitDiffDecorations`

## 9.5.0
  - FIX: [#57](https://github.com/heckmon/code_forge/issues/57)
  - FIX: [#58](https://github.com/heckmon/code_forge/issues/58)
  
## 9.6.0
  - FIX: [#60](https://github.com/heckmon/code_forge/issues/60)
  - FEATURE: Empty `Mode` as default highlight grammar instead of dart grammar as requested in [#59](https://github.com/heckmon/code_forge/discussions/59)

## 9.7.0
  - Enhanced large text handling.

## 9.8.0
  -  FIX: LSP initialization bug.

## 9.9.0
  - FIX: Cursor jump on typing.
  - FIX: Frozen horizontal scroll on dynamic font size.

## 9.10.0
  - FEATURE: Added `tabSize` to customize tab spaces in the Controller.
  - FIX: [#63](https://github.com/heckmon/code_forge/issues/63)
  - FIX: [#61](https://github.com/heckmon/code_forge/issues/61)
  - FIX: [#65](https://github.com/heckmon/code_forge/issues/65)
  - FIX: [#62](https://github.com/heckmon/code_forge/issues/62)

## 10.0.0
  - ### Migrated the backend from dart to rust:
      - Uses [ropey](https://crates.io/crates/ropey) crate for text storage.
      - Introduced [SumTree](https://zed.dev/blog/zed-decoded-rope-sumtree) data structure to store line details using the [zed-sum-tree](https://crates.io/crates/zed-sum-tree) crate, used by the [Zed editor](https://zed.dev/).
      - Bidi support has been enhanced using the [unicode-bidi](https://crates.io/crates/unicode-bidi?utm_source=chatgpt.com) crate for RTL languages.
      - Bracket pair calculation, fold range calculation, etc has been moved to rust side.
  - FEATURE: Line number index in scrollbar.
  - FEATURE: New `ScrollbarDecoration` API to customize the scroll bar.
  - FEATURE: Code action bulb icon now shows on the line start.
  - API CHANGE: `enableSuggestions` has been changed to `enableLocalSuggestions` and default value is false. This API cannot be used to disable LSP suggestions. Use `capabilities` field in the `LspConfig` instead.
  - FIX: [#72](https://github.com/heckmon/code_forge/issues/72)
  <p align="center">
    <img src="https://raw.githubusercontent.com/heckmon/code_forge/refs/heads/main/gifs/1M.gif" alt="CodeForge Demo" width="800"/><sub><br>Smooth editing in 1M+ lines of code, tested on a low end PC with pentium dual core CPU and no dedicated graphics card.</sub>
  </p>

## 10.0.1:
  - Update README.md

## 10.1.0
  - FIX: [#76](https://github.com/heckmon/code_forge/issues/76)
  - FIX: Semantic highlight flicker on backspace.
  - FIX: Fold bug on indentation based languages
  - FEATURE: Added chinese and spanish translation on README

## 10.2.0
  - FIX: [#45](https://github.com/heckmon/code_forge/issues/45)

## 10.3.0
  - FIX: [#45](https://github.com/heckmon/code_forge/issues/45)
  - FIX: Code action bulb icon placement issue.

## 10.4.0
  - FIX: Fixed focus bug in mobile.

## 10.4.1
  - FIX: Syntax warning.

## 10.5.0
  - FIX: [#81](https://github.com/heckmon/code_forge/issues/81)
  - FEATURE: Added a custom gutter builder as requested in [#79](https://github.com/heckmon/code_forge/issues/79)
  - FEATURE: Exposed keyboard shortcuts overriding via `CodeForgeKeyboardShortcuts` and Added multiple column editing and multicursot extending with `Alt + Shift + ArrowUp/ArrowDown` as requested in [#80](https://github.com/heckmon/code_forge/issues/80)

## 10.6.0
  - FIX: [#82](https://github.com/heckmon/code_forge/issues/82)
  - FIX: Gutter mismatch.
  - FEATURE: Exposed vertical scroll physics.

## 10.7.0
  - FIX: Emoji crash
  - FIX: LSP hover infinite waiting.