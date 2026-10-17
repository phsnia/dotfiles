---
name: codegraph-guide
description: Guide for using codegraph MCP tools effectively
---

Guide for effective use of codegraph MCP tools.

## Project context

The project uses codegraph MCP server for code analysis. The codegraph index is located at `.codegraph/codegraph.db`.

## Quick reference

### Common patterns

**Explore architecture:**
```
codegraph_files --projectPath . --format tree
codegraph_explore --projectPath . --query "main auth user"
```

**Find symbol usage:**
```
codegraph_search --projectPath . --query "authenticate" --kind function
codegraph_callers --projectPath . --symbol "authenticate_user"
```

**Check impact before changes:**
```
codegraph_impact --projectPath . --direction upstream --target "process_request"
```

**Read specific file:**
```
codegraph_node --projectPath . --file src/main.c
```

## Project structure

Use `codegraph_files` to discover the actual structure:
- Source directories (src/, lib/, etc.)
- Header files (include/, includes/, etc.)
- External dependencies (deps/, vendor/, etc.)
- Test directories (test/, tests/, spec/)

## Best practices

1. Start with `codegraph_files` to understand scope
2. Use `codegraph_explore` for multi-file investigation with source and relationships
3. Use `codegraph_impact` before refactoring to see dependencies
4. `codegraph_node` shows which files depend on a target
5. One `codegraph_explore` call covers approximately 6 files efficiently

## Tool selection

| Goal | Tool |
|------|------|
| Understand project layout | codegraph_files |
| Find specific symbol | codegraph_search |
| Explore multiple related symbols | codegraph_explore |
| Read single file with dependencies | codegraph_node |
| See what calls a function | codegraph_callers |
| See what function calls | codegraph_callees |
| Analyze change impact | codegraph_impact |

## Workflow integration

Use `/codegraph-explore` workflow for automated exploration patterns.

## External resources

### Codegraph documentation
Official codegraph MCP documentation: https://colbymchenry.github.io/codegraph/reference/mcp-server/

Key points:
- Default tool is `codegraph_explore` - returns verbatim source with line numbers and call paths
- Other tools (node, search, callers, callees, impact, files, status) are unlisted by default
- Re-enable tools with `CODEGRAPH_MCP_TOOLS` environment variable
- Each tool has a CLI equivalent for scripts

### Third-party library documentation
Fetch documentation for external dependencies when codegraph does not provide sufficient context.

```bash
# Search for library documentation
search_web --query "library API documentation"

# Fetch documentation page
read_url_content --url "https://example.com/docs"

# Fetch README from GitHub
mcp3_fetchGithubReadme --url "https://github.com/user/repo"
```

### When to use external resources
- Understanding third-party library APIs
- Finding official documentation for unfamiliar functions
- Researching best practices and patterns
- Getting context for external dependencies
