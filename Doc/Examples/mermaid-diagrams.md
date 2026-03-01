Mermaid diagrams
===============================================================================

Examples of mermaid diagram types rendered by Mud.


## Flowchart

```mermaid
graph TD
    A[Start] --> B{Is it working?}
    B -->|Yes| C[Great!]
    B -->|No| D[Debug]
    D --> B
```


## Sequence diagram

```mermaid
sequenceDiagram
    participant App
    participant Core
    participant WebView

    App->>Core: renderUpModeDocument()
    Core->>Core: Parse markdown (cmark)
    Core->>Core: Walk AST (UpHTMLVisitor)
    Core-->>App: HTML string
    App->>WebView: loadHTMLString()
    WebView->>WebView: mermaid.run()
```


## State diagram

```mermaid
stateDiagram-v2
    [*] --> Up
    Up --> Down: Space bar
    Down --> Up: Space bar

    Up --> Up: Cmd+R (reload)
    Down --> Down: Cmd+R (reload)
```


## Class diagram

```mermaid
classDiagram
    class AppState {
        +Theme theme
        +Lighting lighting
        +Mode modeInActiveTab
    }
    class DocumentState {
        +Mode mode
        +toggleMode()
    }
    class FindState {
        +String searchText
        +Bool isVisible
    }
    DocumentState --> FindState
```


## Pie chart

```mermaid
pie title Lines of code
    "Swift" : 3200
    "JavaScript" : 800
    "CSS" : 600
    "Other" : 200
```


## Regular code block (not mermaid)

This should render as a normal syntax-highlighted code block, not a diagram:

```swift
let html = MudCore.renderUpToHTML("# Hello\n")
```
