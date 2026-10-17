---
name: codegraph-exploring
description: Use codegraph MCP to explore codebase structure and relationships
---

Use codegraph MCP tools to explore codebase architecture, symbols, and relationships.

## When to use

- Understanding codebase structure
- Finding symbol definitions and usage
- Tracing call chains and dependencies
- Analyzing architecture before changes
- Exploring unfamiliar code areas

## Tools

### codegraph_files
File tree with language and symbol counts.
```bash
codegraph_files --projectPath <path> --format tree
codegraph_files --projectPath <path> --path src --format tree
codegraph_files --projectPath <path> --format grouped
```

### codegraph_explore
Primary tool. Returns source with call paths.
```bash
codegraph_explore --projectPath <path> --query "function1 function2"
codegraph_explore --projectPath <path> --query "how does authentication work"
codegraph_explore --projectPath <path> --query "src/auth.c src/user.c"
```

### codegraph_search
Find symbols by name.
```bash
codegraph_search --projectPath <path> --query "authenticate" --kind function
codegraph_search --projectPath <path> --query "User" --kind class
```

### codegraph_node
Read file or symbol with dependencies.
```bash
codegraph_node --projectPath <path> --file src/main.c
codegraph_node --projectPath <path> --symbol "main" --includeCode true
```

### codegraph_callees
Functions called by symbol.
```bash
codegraph_callees --projectPath <path> --symbol "main"
```

### codegraph_callers
Functions that call symbol.
```bash
codegraph_callers --projectPath <path> --symbol "authenticate"
```

### codegraph_impact
Blast radius of changes.
```bash
codegraph_impact --projectPath <path> --direction upstream --target "function_name"
codegraph_impact --projectPath <path> --direction downstream --target "function_name"
```

## Workflow

1. `codegraph_files` for project structure
2. `codegraph_explore` for investigation
3. `codegraph_search` for specific symbols
4. `codegraph_node` for detailed source
5. `codegraph_impact` before changes

## Tips

- `codegraph_explore` returns verbatim source - treat as already read
- One call covers approximately 6 files with relationships
- Use `codegraph_impact` before refactoring
- `codegraph_node` shows file dependencies
