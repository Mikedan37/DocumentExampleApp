# documentExampleApp  

### Advanced Document Architecture for SwiftUI Editors Using BlazeFSM and BlazeBinary

documentExampleApp demonstrates a modern, deterministic approach to building document-based editors on Apple platforms.  

It integrates event-driven finite state machines, a binary-encoded document format, and a replay-driven annotation model to deliver a scalable foundation for high-performance creative and productivity tools.

This project illustrates architectural patterns suitable for macOS and iOS applications requiring reproducible state, extensible persistence, and predictable rendering behavior.

---

## 1. Introduction

Traditional document editors often persist state directly, resulting in fragile save formats, complex migration paths, and non-deterministic behavior during undo/redo.

documentExampleApp uses a different strategy:

- All annotation and tool interactions emit **state transitions**.  

- Documents store only these transitions using **BlazeBinary**, a strict sequential binary format.  

- On load, the application **replays** the transition log to reconstruct the complete document state.  

- Each annotation is governed by an independent **BlazeFSM** instance to ensure correctness, isolation, and predictability.

This architecture simplifies persistence, enables robust undo/redo semantics, and provides a reliable platform for advanced editing behaviors.

---

## 2. Core Technologies

### BlazeFSM

A minimal, strongly typed finite state machine framework used to model annotation lifecycles and tool interactions.

### BlazeBinary

A low-level binary encoding system optimized for deterministic field ordering, forward compatibility, and efficient decoding.

### documentExampleApp Document Model

The application persists three primary elements:

1. Metadata (title, timestamps)  

2. Transition log (ordered sequence of AnnotationStateTransition)  

3. Initial tool state  

These components fully define the document.

---

## 3. High-Level Architecture

```mermaid

flowchart LR

    UI[SwiftUI Editor] --> VM[NotebookEditorViewModel]
    VM --> ToolFSM[ToolFSM]
    VM --> AnnotationFSM[AnnotationFSM]
    AnnotationFSM -.-> VM
    VM -.-> UI
    
    style UI fill:#e1f5ff
    style VM fill:#fff4e1
    style ToolFSM fill:#e8f5e9
    style AnnotationFSM fill:#e8f5e9

```

---

## 4. Binary File Format (BlazeBinary Layout)

The file format uses sequential BlazeBinary encoding with no magic header or version field. The format is defined by the encoding order of NotebookFileData fields.

```mermaid

flowchart LR

    A["Metadata Block"] --> B["Title String<br/>(varint length + UTF-8)"]
    B --> C["CreatedAt UInt64<br/>(8 bytes, little-endian)"]
    C --> D["UpdatedAt UInt64<br/>(8 bytes, little-endian)"]
    D --> E["Transition Count<br/>(varint LEB128)"]
    E --> F["Transition Stream<br/>(AnnotationStateTransition[])"]
    F --> G["Initial Tool State<br/>(EditorToolState String rawValue)"]
    
    style A fill:#fff4e1
    style B fill:#fff4e1
    style C fill:#fff4e1
    style D fill:#fff4e1
    style E fill:#e8f5e9
    style F fill:#e8f5e9
    style G fill:#f3e5f5

```

**Format Characteristics**

- Deterministic sequential encoding (metadata → transitions → tool state)

- No Codable or JSON - pure BlazeBinary encoding

- Arrays encoded as varint count prefix followed by elements

- Strings encoded as varint length prefix followed by UTF-8 bytes

- Fixed-width integers use little-endian byte order

- Efficient replay for restoration via transition log

---

## 5. Annotation State Machine

```mermaid

stateDiagram-v2

    [*] --> idle: Initial state
    
    idle --> selected: select(annotationID)
    idle --> creating: createAnnotation(payload)
    
    selected --> editing: beginEditing(annotationID)
    selected --> moving: beginMove(annotationID)
    selected --> resizing: beginResize(annotationID)
    selected --> deleted: delete(annotationID)
    selected --> idle: deselect(annotationID)
    
    editing --> committed: commitEdit(annotationID, payload)
    editing --> selected: cancel (implicit)
    
    moving --> selected: endMove(annotationID)
    
    resizing --> selected: endResize(annotationID)
    
    creating --> committed: finishCreate
    
    committed --> selected: select(annotationID)
    committed --> deleted: delete(annotationID)
    
    deleted --> [*]: Terminal state

```

Each annotation maintains an independent FSM instance. The state machine validates all transitions and emits transition records for persistence.

---

## 6. Execution Flow

```mermaid

sequenceDiagram

    participant View as SwiftUI View
    participant ViewModel as NotebookEditorViewModel
    participant ToolFSM as ToolFSM
    participant AnnotationFSM as AnnotationFSM

    View->>ViewModel: User gesture/input
    ViewModel->>ToolFSM: Get current tool state
    ToolFSM-->>ViewModel: Current tool
    ViewModel->>AnnotationFSM: processEvent(AnnotationEvent)
    AnnotationFSM->>AnnotationFSM: Validate transition
    AnnotationFSM->>AnnotationFSM: Update state
    AnnotationFSM-->>ViewModel: onTransition callback (AnnotationStateTransition)
    ViewModel->>ViewModel: Accumulate transition
    ViewModel->>ViewModel: Update @Published annotations
    ViewModel-->>View: Trigger SwiftUI rerender

```

**Flow Notes:**
- ViewModel directly calls AnnotationFSM.processEvent() with events
- AnnotationFSM emits transitions via onTransition callback
- ViewModel accumulates transitions in internal array
- ViewModel updates @Published properties which trigger SwiftUI rerender
- No separate Reducer component - state updates happen directly in ViewModel

---

## 7. Components

**NotebookDocument**

A SwiftUI FileDocument implementation responsible for encoding and decoding document state using BlazeBinary.

**NotebookEditorViewModel**

Coordinates tool interactions, annotation FSM instances, transition replay, and rendering updates.

**FSM Extensions**

Adds BlazeBinaryCodable conformance to FSM types.

External conformance warnings are expected and safe.

---

## 8. Example Integration

```swift

@main

struct documentExampleApp: App {

    var body: some Scene {

        DocumentGroup(newDocument: NotebookDocument()) { file in

            NotebookEditorView(document: file.$document)

        }

    }

}

```

---

## 9. Limitations

- PDF backgrounds not yet integrated

- Undo/redo UI not exposed (engine supports it)

- Minimal hit-testing and selection handles

- Rendering pipeline intentionally simplified

---

## 10. Roadmap

**Near-Term**

- PDFKit integration

- Selection handles and bounds manipulation

- Stroke smoothing

**Mid-Term**

- Full layering model

- BlazeDB indexing

- Multi-page documents

**Long-Term**

- Cross-device sync using transition diffs

- Collaborative editing

---

## 11. License

MIT License.

---

## Summary

documentExampleApp demonstrates how deterministic state machines, binary document formats, and declarative UI composition form a reliable foundation for building advanced editors on Apple platforms.

The architectural principles prioritize correctness, reproducibility, and extensibility, enabling future expansion into sophisticated creative and productivity workflows.
