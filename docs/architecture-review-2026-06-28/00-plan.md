# Analysis Plan: Custom Agentic Harness Patch Management Architecture

## Question
Should we maintain a fork of OpenCode? A merged OpenCode+OMO fork? Or is the current patch-tracker overlay approach correct but underbuilt? What is the systematic root cause of update pain?

## Frame
AI agent developer's perspective. The human never works on this directly. All maintenance is done by AI agents (Sisyphus/etc) operating inside the running harness.

## Phases

### Phase 1: Parallel Research (delegate to sub-agents, collect summaries)
- R1: External best practices for patching AI tools, OpenCode/OMO community sentiment on forks
- R2: Enumerate and assess the current patch-tracker system (all patches, lifecycle, failure evidence)
- R3: Case study — today's session-info bug chain (root causes, systematic patterns)
- R4: The update-to-latest process and past update pain points
- R5: OMO's own architecture for extending OpenCode (patterns to learn from)

### Phase 2: Synthesize Root Causes (from R1-R5)
- Identify systematic/architectural root causes vs one-off failures

### Phase 3: Architecture Debate (/debate)
- Fork vs patch-overlay vs hybrid
- Scope: OpenCode-only fork, OMO-only fork, merged fork, or none

### Phase 4: Write Final Analysis Document
- Evidence-based recommendation
- Implementation roadmap
- Risk assessment

## Context Management
- Each sub-agent writes its findings to /tmp/opencode-fork-analysis/R{n}.md
- Main agent reads summaries only
- Debate produces structured output
- Final doc synthesizes everything
