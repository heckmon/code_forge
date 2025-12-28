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