# Design Document: ElixirScope.Correlator (elixir_scope_correlator)

## 1. Purpose & Vision

**Summary:** Manages the critical link between runtime events (captured by `elixir_scope_capture_core` and stored by `elixir_scope_storage`) and static code structures (specifically CPG nodes from `elixir_scope_ast_repo`). Enables AST-aware debugging and analysis.

**(Greatly Expanded Purpose based on your existing knowledge of ElixirScope and CPG features):**

The `elixir_scope_correlator` library is the central hub for bridging the dynamic execution of an Elixir application with its static code representation, primarily the Code Property Graph (CPG). Its core mission is to take runtime events, each potentially tagged with an `ast_node_id`, and map them to their precise counterparts in the static CPG, thereby enriching both runtime data with static context and static data with dynamic execution insights.

This library aims to:
*   **Establish AST-Runtime Linkage:** Use `ast_node_id`s present in runtime events (originating from `elixir_scope_compiler` which gets them from `elixir_scope_ast_repo`) to look up corresponding nodes in the CPG (managed by `elixir_scope_ast_repo`).
*   **Build Rich Runtime Contexts:** For a given runtime event, construct an `ASTContext` that includes not just the directly correlated CPG node, but also relevant surrounding CPG information (e.g., parent function, enclosing control flow structures, data dependencies).
*   **Enhance Events with Static Information:** Augment raw runtime events with metadata derived from the CPG, such as the type of AST node executed, semantic tags, or complexity scores associated with that code point.
*   **Construct AST-Aware Execution Traces:** Generate execution traces that are not just sequences of events, but sequences of CPG node traversals, providing a structural view of runtime behavior.
*   **Manage Correlation State & Caching:** Efficiently cache correlation results and AST context lookups to optimize performance for frequently accessed code paths.
*   **Facilitate CPG-Enhanced Debugging:** Provide the foundational data needed by `elixir_scope_debugger_features` and `elixir_scope_temporal_debug` to understand runtime behavior in the context of the CPG. For example, when a structural breakpoint (defined on a CPG pattern) is hit, this library helps identify which runtime event triggered it.

The `elixir_scope_correlator` is pivotal for realizing the "Execution Cinema." It allows developers and AI assistants to ask questions like, "What was the state of variables when execution passed through *this specific CPG node*?" or "Show me the CPG path taken by *this runtime request*." It translates opaque runtime event streams into meaningful narratives grounded in the code's structure.

This library will enable:
*   `elixir_scope_debugger_features` to resolve breakpoints and watchpoints against dynamic execution, correlating them with CPG elements.
*   `elixir_scope_temporal_debug` to enrich its time-travel states with CPG context, showing not just *what* happened but *where in the CPG* it happened.
*   `elixir_scope_ai` to receive runtime data that is already contextualized with static CPG information, leading to more insightful AI analyses.
*   `TidewaveScope` MCP tools to display runtime information overlaid on, or linked to, static code views (e.g., highlighting the CPG nodes executed during a specific web request).

## 2. Key Responsibilities

This library is responsible for:

*   **Event-to-AST/CPG Correlation (`EventCorrelator`):**
    *   Taking a runtime event (containing an `ast_node_id`) and querying `elixir_scope_ast_repo` to find the corresponding CPG node(s).
    *   Handling cases where an `ast_node_id` might map to multiple CPG elements or requires disambiguation.
*   **AST Context Building (`ContextBuilder`):**
    *   For a given `ast_node_id` (or CPG node), constructing a rich `ASTContext` struct that includes details about the CPG node, its parent function CPG, relevant CFG/DFG snippets, and variable scope information from the CPG.
*   **Runtime Event Enhancement:**
    *   Creating `EnhancedEvent` structs that combine original runtime events with their resolved `ASTContext`.
*   **Execution Trace Construction (`TraceBuilder`):**
    *   Taking a sequence of `EnhancedEvent`s and building an `ExecutionTrace` that represents the flow through CPG nodes.
    *   Identifying structural patterns or anomalies in these CPG-aware traces.
*   **Correlation State Management (`RuntimeCorrelator` GenServer):**
    *   Managing active correlations and potentially caching frequently accessed `ASTContext`s or CPG node details.
    *   Interfacing with `elixir_scope_ast_repo` for static data and `elixir_scope_storage` for runtime event data (if needed for more complex correlations, though primarily it uses the `ast_node_id` from the event itself).
*   **Breakpoint/Watchpoint Support:**
    *   Providing services to `elixir_scope_debugger_features` to evaluate if a runtime event (with its CPG context) matches a breakpoint or watchpoint definition.
*   **Caching (`CacheManager`):**
    *   Caching resolved AST/CPG contexts and trace fragments to improve performance.

Note: The original `ElixirScope.Capture.EventCorrelator` focused on call stack and message correlation. This new `elixir_scope_correlator` focuses on `ast_node_id` to static structure correlation. The original's functionality might be partly subsumed here if `parent_id` in events needs CPG context, or it could remain a separate concern within `elixir_scope_capture_core` or a dedicated causality-linking library. For now, we assume this library focuses on `ast_node_id` mapping.

## 3. Key Modules & Structure

The primary modules within this library will be:

*   `ElixirScope.Correlator.RuntimeCorrelator` (Main GenServer and public API, based on `elixir_scope/ast_repository/runtime_correlator.ex`)
*   `ElixirScope.Correlator.EventCorrelator` (Core logic for mapping event `ast_node_id` to static structures)
*   `ElixirScope.Correlator.ContextBuilder` (Builds `ASTContext` from CPG data)
*   `ElixirScope.Correlator.TraceBuilder` (Builds CPG-aware execution traces)
*   `ElixirScope.Correlator.CacheManager` (Manages caches for correlation results)
*   `ElixirScope.Correlator.Types` (Defines local types like `ASTContext`, `EnhancedEvent`, `ExecutionTrace`)
*   `ElixirScope.Correlator.Config` (Configuration specific to this correlator)
*   `ElixirScope.Correlator.Utils` (Local utilities, or use `elixir_scope_utils`)

### Proposed File Tree:

```
elixir_scope_correlator/
├── lib/
│   └── elixir_scope/
│       └── correlator/
│           ├── runtime_correlator.ex # GenServer API
│           ├── event_correlator.ex
│           ├── context_builder.ex
│           ├── trace_builder.ex
│           ├── cache_manager.ex
│           ├── types.ex
│           ├── config.ex
│           └── utils.ex
├── mix.exs
├── README.md
├── DESIGN.MD
└── test/
    ├── test_helper.exs
    └── elixir_scope/
        └── correlator/
            ├── runtime_correlator_test.exs
            ├── event_correlator_test.exs
            └── ... (tests for other modules)
```

**(Greatly Expanded - Module Description):**
*   **`ElixirScope.Correlator.RuntimeCorrelator` (GenServer):** The main public interface for this library. It orchestrates the correlation process. Other ElixirScope components (like `elixir_scope_debugger_features` or `TidewaveScope` tools) will call this GenServer to get AST/CPG context for runtime events or to build CPG-aware traces. It manages the lifecycle of its internal components like the `CacheManager`.
*   **`ElixirScope.Correlator.EventCorrelator`**: Contains the core logic to take a runtime event (from `elixir_scope_events`, which includes an `ast_node_id`) and query the `elixir_scope_ast_repo` to retrieve the corresponding CPG node data and relevant structural information.
*   **`ElixirScope.Correlator.ContextBuilder`**: Once a CPG node is identified by `EventCorrelator`, this module constructs the rich `ElixirScope.Correlator.Types.ast_context()`. This involves fetching details about the CPG node itself, its containing function's CPG, and potentially relevant CFG/DFG snippets or semantic properties from the `elixir_scope_ast_repo`.
*   **`ElixirScope.Correlator.TraceBuilder`**: Takes a sequence of `EnhancedEvent`s (runtime events already augmented with their `ast_context` by this library) and constructs an `ExecutionTrace`. This trace isn't just a list of events but highlights the sequence of CPG nodes traversed.
*   **`ElixirScope.Correlator.CacheManager`**: Implements caching (likely ETS-based) for frequently requested `ast_node_id` lookups and the resulting `ASTContext`s or CPG node details to reduce load on `elixir_scope_ast_repo`.
*   **`ElixirScope.Correlator.Types`**: Defines the primary data structures produced by this library, such as `ast_context()`, `enhanced_event()`, and `execution_trace()`.

## 4. Public API (Conceptual)

Via `ElixirScope.Correlator.RuntimeCorrelator` (GenServer):

*   `start_link(opts :: keyword()) :: GenServer.on_start()`
    *   Options: `ast_repo_ref :: pid() | atom()`, `event_store_ref :: pid() | atom()` (if needed for historical event lookups).
*   `correlate_event_to_ast_context(event :: ElixirScope.Events.t()) :: {:ok, ElixirScope.Correlator.Types.ast_context()} | {:error, :not_found | term()}`
    *   Takes a raw event, finds its `ast_node_id`, queries `elixir_scope_ast_repo`, and builds the `ast_context`.
*   `enhance_event(event :: ElixirScope.Events.t()) :: {:ok, ElixirScope.Correlator.Types.enhanced_event()} | {:error, term()}`
    *   Combines the original event with its `ast_context`.
*   `build_cpg_execution_trace(events :: [ElixirScope.Events.t()]) :: {:ok, ElixirScope.Correlator.Types.execution_trace()} | {:error, term()}`
    *   Takes a list of raw events, enhances them, and builds a CPG-aware trace.
*   `get_cpg_node_for_event(event :: ElixirScope.Events.t()) :: {:ok, ElixirScope.AST.Structures.CPGNode.t()} | {:error, :not_found | term()}`
    *   A more direct lookup if only the CPG node itself is needed.
*   `get_correlation_stats() :: {:ok, map()}`
*   `clear_correlation_caches() :: :ok`

## 5. Core Data Structures

This library defines and produces:

*   **`ElixirScope.Correlator.Types.ast_context()`**:
    ```elixir
    # In ElixirScope.Correlator.Types
    @type ast_context :: %{
      event_ast_node_id: String.t(),       # The ast_node_id from the runtime event
      cpg_node_id: String.t() | nil,       # ID of the main CPG node correlated to
      cpg_node_type: atom() | nil,         # Type of the CPG node
      cpg_node_label: String.t() | nil,    # Label of the CPG node
      cpg_node_properties: map() | nil,    # Properties from the CPG node
      function_cpg_id: String.t() | nil,   # ID of the containing function's CPG
      module_name: module() | nil,
      function_name: atom() | nil,
      arity: non_neg_integer() | nil,
      source_file_path: String.t() | nil,
      line_number_in_source: non_neg_integer() | nil,
      # Snippets or references to relevant CFG/DFG parts might be included
      # For example: current_cfg_block_id, active_dfg_variables
    }
    ```
*   **`ElixirScope.Correlator.Types.enhanced_event()`**:
    ```elixir
    # In ElixirScope.Correlator.Types
    @type enhanced_event :: %{
      original_event: ElixirScope.Events.t(),
      ast_context: ast_context() | nil,
      correlation_timestamp: integer() # When this enhancement was made
    }
    ```
*   **`ElixirScope.Correlator.Types.execution_trace()`**:
    ```elixir
    # In ElixirScope.Correlator.Types
    @type execution_trace :: %{
      trace_id: String.t(),
      enhanced_events: [enhanced_event()],
      cpg_path_taken: list(%{cpg_node_id: String.t(), timestamp: integer()}), # Ordered list of CPG nodes traversed
      start_time: integer(),
      end_time: integer(),
      metadata: map()
    }
    ```
*   Consumes: `ElixirScope.Events.t()` (from `elixir_scope_events`).
*   Consumes: `ElixirScope.AST.Structures.CPGNode.t()`, `CPGData.t()` etc. (queried from `elixir_scope_ast_repo`).

## 6. Dependencies

This library will depend on the following ElixirScope libraries:

*   `elixir_scope_utils` (for utilities).
*   `elixir_scope_config` (for its operational parameters, cache settings, timeouts).
*   `elixir_scope_events` (to understand the input event structures).
*   `elixir_scope_ast_structures` (to understand the CPG data it receives from the AST repo).
*   `elixir_scope_ast_repo` (crucially, to query for CPG nodes and static context based on `ast_node_id`).
*   `elixir_scope_storage` (potentially, if it needs to look up historical sequences of events to build more complex correlations, though this might be the job of a higher-level component like `TemporalDebug`).

It will depend on Elixir core libraries (`GenServer`, `:ets` for caching).

## 7. Role in TidewaveScope & Interactions

Within the `TidewaveScope` ecosystem, the `elixir_scope_correlator` library will:

*   Be a central service started by `TidewaveScope`.
*   Be used by `elixir_scope_debugger_features` to understand the CPG context of runtime events that might trigger breakpoints or affect watchpoints.
*   Be used by `elixir_scope_temporal_debug` to enrich reconstructed states and traces with static CPG context.
*   Provide data to `elixir_scope_ai` when AI models need to analyze runtime behavior in conjunction with code structure.
*   Indirectly serve `TidewaveScope` MCP tools by providing the contextual data that other components then expose. For example, if an AI asks, "What CPG node was active when this error occurred?", the `TidewaveScope` tool would use the `elixir_scope_correlator` (possibly via `elixir_scope_debugger_features`) to answer.

## 8. Future Considerations & CPG Enhancements

*   **Inter-procedural Correlation:** Enhancing correlation to trace across function calls, using call graph information from the CPG. If event `A` with `ast_node_id_A` calls a function leading to event `B` with `ast_node_id_B`, this library could link them using the CPG's call edges.
*   **Data Flow Correlation:** Correlating runtime variable values with DFG/CPG data flow paths. "This runtime value of `x` corresponds to this DFG edge in the CPG."
*   **Heuristic Correlation:** For events *without* an `ast_node_id`, implement heuristics (e.g., based on MFA, call stack, timing) to attempt a probabilistic correlation to CPG elements.
*   **Performance Optimization:** Aggressively optimize CPG lookups and context building, potentially using more sophisticated caching or pre-computation based on CPG analysis from `elixir_scope_ast_repo`.
*   **Correlation Confidence:** Assign a confidence score to correlations, especially if heuristics are used.

## 9. Testing Strategy

*   **`ElixirScope.Correlator.EventCorrelator` & `ContextBuilder` Unit Tests:**
    *   Provide mock runtime events (with `ast_node_id`s).
    *   Mock the `elixir_scope_ast_repo` API to return predefined CPG node data for given `ast_node_id`s.
    *   Verify that `correlate_event_to_ast_context` correctly calls the mock AST repo and constructs the expected `ast_context` struct.
    *   Test with events that have no `ast_node_id` or an `ast_node_id` not found in the mock repo.
*   **`ElixirScope.Correlator.TraceBuilder` Unit Tests:**
    *   Provide a sequence of mock `EnhancedEvent`s.
    *   Verify that `build_cpg_execution_trace` constructs the trace with the correct CPG path and metadata.
*   **`ElixirScope.Correlator.CacheManager` Unit Tests:**
    *   Test cache hits, misses, and eviction logic for `ASTContext`s.
*   **`ElixirScope.Correlator.RuntimeCorrelator` GenServer Tests:**
    *   Test all public API calls, ensuring they delegate correctly and manage state (like stats) appropriately.
    *   Test concurrent calls.
*   **Integration Tests:**
    *   A more complex test involving:
        1.  A mock `elixir_scope_ast_repo` serving a small, predefined CPG.
        2.  Mock runtime events with `ast_node_id`s corresponding to the mock CPG.
        3.  Asserting that `elixir_scope_correlator` produces the correct `EnhancedEvent`s and `ExecutionTrace`s.
*   **Performance Benchmarks:**
    *   Measure the latency of `correlate_event_to_ast_context` under various cache hit/miss scenarios and CPG complexity.
