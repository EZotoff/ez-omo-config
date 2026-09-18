# OC Beacon Portable Supervisor Prototype

> **Snapshot note** (added 2026-09-18): proposal authored outside the repo (originally at
> `~/Downloads/OC_BEACON_PORTABLE_SUPERVISOR_PROTOTYPE.md`), copied here for versioning.
> Implementation status and the component/contract split it drove:
> [portable-supervisor-contract.md](portable-supervisor-contract.md).
# OC Beacon Portable Supervisor Prototype

## Purpose

Build a new **Portable Supervisor Mode** inside an OC Beacon fork to validate a mobile interaction model for supervising multiple OpenCode sessions across multiple projects while walking or otherwise away from the desktop.

The prototype is not intended to reproduce the desktop OpenCode experience on a phone. Its purpose is to test a lower-bandwidth, context-aware interaction model built around:

- rapid switching between projects and sessions;
- highly condensed session state;
- voice interaction with a cross-project Supervisor agent;
- explicit sharing of the currently viewed UI context with that voice agent;
- compact visual surfaces for information that is faster to consume visually than through speech;
- minimal physical interaction while moving;
- sound and haptic notifications;
- a future transition from the smartphone UI to separate wearable or physical devices without redesigning the interaction model.

The smartphone is therefore a **prototype and emulator for a future portable hardware interface**, not necessarily the final form factor.

---

## Product Intent

The desktop workflow and the portable workflow serve different purposes.

On the desktop, the user may have multiple OpenCode sessions visible simultaneously, use TUI key combinations, navigate detailed conversations, inspect files, and perform arbitrary terminal operations.

The portable workflow should not attempt to reproduce this.

Instead, Portable Supervisor Mode should provide a compact supervisory layer for answering questions such as:

- What needs my attention?
- What are my recently active projects doing?
- What are my recently active sessions doing?
- What is this particular session waiting for?
- What did I ask this session to do?
- What did the agent answer most recently?
- What changed while I was away?
- What are the important differences between several options?
- What action should I take next?
- Can I instruct the Supervisor to act on the session I am currently viewing?

The core interaction model is:

> **Navigate visually to establish context, then use voice to reason or act on that context.**

This should reduce the need to verbally identify project names, session names, technical identifiers, or other context that the application already knows.

---

# Scope

## In Scope

The prototype should add a new mode inside the existing OC Beacon application with:

1. A portable, condensed UI optimized for one-handed or minimal-touch use.
2. Fast switching between projects and sessions.
3. A persistent concept of the **currently viewed context**.
4. Voice interaction with a Supervisor agent.
5. Mandatory inclusion of current view context in voice interactions.
6. Compact Supervisor-generated visual views such as cards, lists, mini-tables, choices, progress summaries, and short comparisons.
7. Views focused on recently active projects and sessions.
8. An attention-oriented view for sessions that need human input.
9. Lightweight semantic actions for common supervisory operations.
10. Sound and haptic notification controls available globally in OC Beacon, not only inside Portable Supervisor Mode.
11. Instrumentation sufficient to evaluate whether the interaction model works during real walking use.
12. A clean path toward replacing phone-specific inputs and display with dedicated physical devices later.

## Out of Scope

The following are explicitly outside the prototype:

- Rebuilding or extending OC Beacon's existing raw TUI/terminal control.
- Reproducing the desktop split-screen layout.
- Full terminal operation from Portable Supervisor Mode.
- Full chat transcript browsing as a primary interaction pattern.
- Designing the underlying Supervisor data architecture.
- Designing low-level protocols, classes, repositories, schemas, or application architecture.
- Solving speech recognition for arbitrary technical terms through a dedicated exact-token UI.
- Selecting or integrating final wearable hardware.
- Finalizing production UX for smart glasses, rings, watches, buttons, or other peripherals.

OC Beacon's existing TUI functionality remains available elsewhere in the app as a fallback, but it is not part of this prototype.

---

# Core Functional Requirements

## 1. Portable Supervisor Mode

OC Beacon must gain a dedicated **Portable Supervisor Mode** that is visually and behaviorally distinct from the normal OC Beacon interface.

The mode should deliberately constrain information density.

The goal is not to exploit the full smartphone display. The phone should emulate the limitations of a future wearable interface so that the interaction model can be validated before dedicated hardware is purchased.

### The mode should favor:

- one primary object or decision at a time;
- short text;
- short lists;
- compact tables;
- large interaction targets;
- minimal typing;
- strong use of gesture navigation;
- voice for complex instructions;
- very fast context switching.

### The mode should avoid:

- dense multi-pane layouts;
- long scrolling transcripts;
- large forms;
- keyboard-first interaction;
- miniature replicas of desktop views.

---

# 2. Navigation Model

Navigation must make it easy to move across both **projects** and **sessions**.

The initial interaction model should test two orthogonal gesture axes:

- **Swipe left/right:** switch between projects.
- **Swipe up/down:** switch between sessions within the current project.

This should make project/session navigation possible without menus or precise tapping.

Example:

```text
                ↑
          previous session

← previous project   CURRENT   next project →

            next session
                ↓
```

The currently selected project and session must always be visually obvious.

A gesture should update the active context immediately, even before the user issues a voice command.

### Additional navigation

The prototype should also support:

- entering the currently selected session;
- returning to the previous level/view;
- moving through recently active projects;
- moving through recently active sessions;
- returning quickly to the most recently viewed item.

Exact gesture mappings beyond the primary project/session swipes may evolve during testing.

---

# 3. Current View Context

The application must maintain an explicit concept of **what the user is currently viewing**.

At minimum, the current context should distinguish:

- current project;
- current session;
- current Portable Mode view;
- any currently selected item within that view.

The purpose is conversational grounding.

If the user is looking at a particular session and says:

> "Why is it waiting?"

the Supervisor should know which session "it" refers to.

If the Supervisor displays a comparison and the user selects an item and says:

> "Use this one."

the selected visual object should form part of the conversational context.

This context is a required part of the prototype and should be treated as a core product behavior rather than optional metadata.

---

# 4. Voice Interaction with the Supervisor

Portable Supervisor Mode must provide a convenient way to speak to the Supervisor.

The Supervisor acts as the conversational intelligence layer across OpenCode projects and sessions.

The exact speech stack is not specified by this document.

## Mandatory behavior

Every voice interaction initiated from Portable Supervisor Mode must include sufficient UI context for the Supervisor to understand what the user is currently looking at.

The effective interaction should be equivalent to:

```text
User speech
+
current project
+
current session
+
current view
+
current selection
+
relevant recent navigation context
```

This allows natural deictic language such as:

- "What happened here?"
- "Why is this blocked?"
- "What was I asking it to do?"
- "Compare this with the previous one."
- "Tell it to proceed."
- "Show me the alternatives."
- "What changed since I last looked at this?"
- "Go back to the project I was looking at before."

The prototype should test whether this combination of **visual context + speech** substantially reduces the need for exact verbal naming.

---

# 5. Recent User Activity Context

Portable Mode should prioritize what is relevant **now**, rather than exposing every project and session equally.

The system should therefore maintain a useful concept of the user's recent activity.

This primarily means:

- projects the user recently viewed or worked with;
- sessions the user recently viewed or interacted with;
- the order in which the user moved between them.

The main purpose is UI relevance.

For example:

```text
RECENT PROJECTS

1. Veran
2. SerVal
3. Temporal KG
4. Paper
```

and within a project:

```text
RECENT SESSIONS

1. retrieval architecture
2. backend implementation
3. integration tests
```

The UI should make it easy to cycle through these recently relevant objects rather than repeatedly navigating the entire project/session universe.

## Supervisor access to recent activity

The Supervisor may also receive a small amount of recent-navigation context when useful.

For example, this may allow:

> "Compare this with the session I looked at just before."

or:

> "Go back to the previous project."

This is secondary to the UI requirement, but should be preserved as a potentially valuable capability.

---

# 6. Condensed Session View

Portable Mode must provide a compact representation of a session.

The Supervisor has access to the same cross-project session view as the user, but the portable UI should reduce this to the information most useful for supervisory decisions.

A session view should prioritize:

- project;
- session name or concise identifier;
- current state;
- whether human attention is required;
- latest user prompt;
- latest agent response or a condensed representation of it;
- recent activity time;
- useful lightweight status information where available.

Example:

```text
VERAN
retrieval architecture

WAITING FOR INPUT

YOU
"Evaluate whether we should..."

AGENT
"Two viable approaches remain.
Option B reduces latency but..."

updated 3m ago
```

The prototype should optimize for rapid comprehension rather than completeness.

---

# 7. Attention View

Portable Mode should include a dedicated view showing items that currently require human attention.

The goal is to answer:

> "Where is my intervention valuable right now?"

Example:

```text
NEEDS YOU · 3

VERAN / retrieval
architecture choice
2m

TEMPORAL KG / tests
2 failures
4m

SERVAL / planner
question
7m
```

The user should be able to move directly from an attention item into the corresponding session context.

The exact logic for identifying attention-worthy items is delegated to the agentic stack and Supervisor.

---

# 8. Supervisor Visual Output

The Supervisor must be able to explicitly **show** compact information in Portable Mode.

This is important because some information is faster to consume visually than through speech.

Examples include:

- statistics;
- choices;
- mini-tables;
- short comparisons;
- progress information;
- compact status summaries;
- short diffs;
- lists of sessions or projects.

The Supervisor should be able to request a visual presentation without assuming a phone-specific layout.

Portable Mode should support a small family of semantic visual forms such as:

- card;
- list;
- mini-table;
- choice;
- progress;
- short comparison;
- compact diff.

Example:

```text
RETRIEVAL OPTIONS

OPTION      LATENCY   COMPLEXITY
pgvector      81ms       LOW
Qdrant        29ms       MED
hybrid        24ms       HIGH
```

The user can then speak naturally about what is visible:

> "Why is the second one more complex?"

or:

> "Use the middle option."

The currently displayed view and current selection must be included in the voice-agent context.

---

# 9. Semantic Actions

Portable Mode should expose a small set of common supervisory actions without requiring raw TUI interaction.

Initial candidates include:

- interrupt;
- continue;
- compact context;
- approve/proceed;
- defer;
- send instruction;
- request more detail;
- ask Supervisor to show options;
- switch project;
- switch session.

The prototype should treat these as user intentions, not as desktop keystroke sequences.

The agentic stack may later decide how those intentions are implemented against OpenCode.

The exact action vocabulary should remain deliberately small during the first prototype so that real usage can reveal which actions are actually important.

---

# 10. Sound Notifications

OC Beacon should gain a **global sound notifications setting**.

This is not limited to Portable Supervisor Mode.

Requirements:

- Sound notifications can be turned ON or OFF by the user.
- The setting applies consistently across OC Beacon.
- The implementation should be able to use the existing/custom state sounds from the user's OpenCode environment.
- The details of obtaining, mapping, or packaging those sounds are delegated to the implementation agentic stack.

The prototype should preserve the semantic distinction between relevant session states so that different sounds may correspond to different events.

Examples may include:

- completion;
- attention required;
- failure;
- blocking state;
- other meaningful state transitions.

The exact sound mapping is not specified here.

---

# 11. Haptic Notifications

OC Beacon should gain a **global haptic notifications setting**.

This is also not limited to Portable Supervisor Mode.

Requirements:

- Haptic notifications can be turned ON or OFF independently of sound.
- Sound and haptics must therefore support four combinations:

```text
Sound ON   + Haptics ON
Sound ON   + Haptics OFF
Sound OFF  + Haptics ON
Sound OFF  + Haptics OFF
```

- Haptic patterns may differ between important state transitions if useful.
- Exact haptic patterns are deferred to implementation and user testing.

The purpose is to test whether a phone in a pocket can already provide a useful ambient supervisory channel.

---

# 12. Portable Interaction Modes to Emulate

The smartphone prototype should deliberately emulate the interaction channels expected from later hardware.

## Visual channel

Emulate future glasses or another compact display.

Use:

- constrained information density;
- short cards;
- short lists;
- mini-tables;
- current selection;
- obvious project/session context.

## Gesture/control channel

Emulate future temple gestures, buttons, rings, watches, or other physical controls.

Use the phone initially for:

- left/right project switching;
- up/down session switching;
- selection;
- back;
- push-to-talk or voice activation;
- optional quick action.

The implementation may additionally experiment with physical phone buttons if useful, but this is not a core functional requirement.

## Audio channel

Emulate future earbuds, open-ear audio, bone-conduction audio, or integrated wearable speakers.

The prototype should support:

- spoken Supervisor responses;
- short spoken alerts;
- user voice input.

Long information should not automatically be read aloud when a compact visual presentation would be more efficient.

---

# Prototype UX

## Default Portable Home

The default view should emphasize:

1. items needing attention;
2. current/recent project;
3. current/recent session;
4. recent activity.

Example:

```text
PORTABLE SUPERVISOR

NEEDS YOU · 2

VERAN / retrieval
WAITING · 3m

KG / tests
FAILED · 5m

──────────────

CURRENT
SERVAL / implementation
RUNNING · 14m
```

---

## Project Switching

Horizontal swipe:

```text
← VERAN | SERVAL | TEMPORAL KG →
```

The selected project becomes part of the Supervisor context immediately.

---

## Session Switching

Vertical swipe within the selected project:

```text
↑ planner
  implementation
> tests
  review
↓
```

The selected session becomes part of the Supervisor context immediately.

---

## Voice-Grounded Interaction

Example sequence:

1. User swipes horizontally to **Veran**.
2. User swipes vertically to **retrieval architecture**.
3. Session card shows that the agent is waiting.
4. User activates voice and says:

> "What's it waiting for?"

5. Supervisor receives both the utterance and the active view context.
6. Supervisor answers through audio and/or a compact visual response.

---

## Supervisor "Show Me" Interaction

Example:

User:

> "Show me the options."

Portable Mode:

```text
DB OPTIONS

A  pgvector
   simple

B  Qdrant
   faster

C  hybrid
   complex
```

User highlights B and says:

> "What do we lose with this?"

The Supervisor receives B as the selected object.

The UI is therefore part of the conversation.

---

# Prototype Validation

The prototype should be evaluated through actual walking use, not only desk testing.

A useful initial test is:

- several active OpenCode sessions;
- several projects;
- 30-60 minutes away from the desktop;
- Portable Supervisor Mode used as the primary supervisory interface.

During the test, record when the user has to abandon Portable Mode and use:

- normal OC Beacon views;
- keyboard entry;
- existing raw TUI;
- desktop computer;
- another workaround.

Each fallback should be classified afterward.

The important question is not merely whether the prototype works.

The important questions are:

- What information was missing?
- What actions were missing?
- What was too slow?
- What required too much visual attention?
- What was easier by voice?
- What was easier visually?
- Where did project/session navigation become confusing?
- Which context references worked naturally?
- Which voice instructions were ambiguous?
- How often was raw terminal access actually necessary?
- Which alerts were useful while the phone stayed in the pocket?
- Were sound and haptic notifications informative or distracting?

These observations should drive the next iteration.

---

# Roadmap

## Phase 1 - Portable Interaction Skeleton

Build the minimal Portable Supervisor Mode.

Must include:

- dedicated Portable Mode entry point;
- condensed project/session UI;
- horizontal project switching;
- vertical session switching;
- current view context;
- recent project/session ordering;
- basic attention view;
- basic session card;
- voice interaction with mandatory view context.

### Goal

Validate whether:

> navigation + visible context + voice

is sufficient for useful cross-project supervision while walking.

---

## Phase 2 - Supervisor Visual Surfaces

Add structured visual responses from the Supervisor.

Support a minimal set:

- cards;
- lists;
- mini-tables;
- choices;
- progress;
- comparisons.

Ensure that visual selection is fed back into subsequent voice context.

### Goal

Validate whether mixed visual/audio interaction is materially better than voice alone.

---

## Phase 3 - Semantic Actions

Add a small action vocabulary for common supervisory operations.

Initial candidates:

- continue;
- interrupt;
- compact;
- approve/proceed;
- defer;
- send instruction;
- request detail.

### Goal

Determine which desktop operations can be replaced by portable semantic controls and which still require fallback to normal OC Beacon/TUI functionality.

---

## Phase 4 - Ambient Notifications

Add global OC Beacon settings for:

- sound ON/OFF;
- haptics ON/OFF.

Integrate relevant OpenCode state notifications using the existing/custom sound vocabulary from the user's stack.

### Goal

Test supervision with the phone mostly in the pocket.

Determine whether the user can remain aware of important agent states without continuously looking at the screen.

---

## Phase 5 - Real Walking Validation

Run repeated real-world sessions with multiple active projects and sessions.

Collect:

- interaction failures;
- fallback events;
- missed context;
- unnecessary interruptions;
- useful/unused actions;
- voice ambiguity;
- navigation friction.

Refine the Portable Mode based on observed behavior.

### Exit criterion

The interaction model should feel useful enough that dedicated hardware could plausibly improve ergonomics rather than compensate for conceptual UX problems.

---

# Deferred Hardware Extension

The smartphone prototype is intentionally designed as the first implementation of a broader **Portable Supervisor Interface**.

After the interaction model has been validated, individual smartphone functions may migrate onto separate devices.

Possible future mapping:

| Prototype function | Possible future device |
|---|---|
| compact visual output | smart glasses / monocular HUD |
| project/session navigation | glasses gestures / ring / button / wearable controller |
| voice input | glasses microphone / headset / earbud microphone |
| spoken output | open-ear headphones / earbuds / glasses audio |
| haptic alerts | smartwatch / ring / phone |
| quick semantic actions | ring / button / wearable controller |
| fallback rich display | smartphone |

The exact hardware is intentionally **not selected during the prototype phase**.

The important constraint is that the interaction concepts remain stable:

```text
PROJECT
SESSION
VIEW
SELECTION
VOICE
ACTION
SHOW
ATTENTION
```

A later device should provide alternative input/output mechanisms for these same concepts rather than introduce a completely different interaction model.

---

# Hardware-Agnostic Design Principle

The prototype should distinguish between:

## What the user means

Examples:

- next project;
- previous session;
- select;
- back;
- continue;
- interrupt;
- compact;
- ask Supervisor;
- show comparison.

and:

## How the user expressed it

Examples:

- phone swipe;
- touchscreen tap;
- physical button;
- ring gesture;
- glasses temple swipe;
- watch crown;
- voice;
- headset control.

Likewise, the system should distinguish between:

## What the Supervisor wants to show

Examples:

- card;
- table;
- choice;
- list;
- progress.

and:

## Where it is rendered

Examples:

- phone;
- glasses;
- watch;
- another compact display.

This separation is essential to the deferred hardware strategy.

---

# Success Criteria

The prototype is successful if it demonstrates that the user can supervise multiple OpenCode projects while mobile with substantially less interaction than normal desktop or full OC Beacon use.

Specifically:

1. The user can move rapidly between recently relevant projects and sessions.
2. Project/session identity remains clear despite the condensed UI.
3. Voice interactions correctly inherit what the user is viewing.
4. Natural references such as "this", "here", "the previous one", and "this session" work reliably.
5. The Supervisor can communicate structured information visually when speech would be inefficient.
6. The user can perform the most common supervisory actions without entering raw TUI control.
7. Sound and/or haptics can provide useful background awareness while the phone is not being viewed.
8. Walking interaction does not require sustained attention to the screen.
9. The prototype reveals a small, stable vocabulary of actions and visual primitives suitable for later wearable hardware.
10. Replacing smartphone input/output with future physical devices should require adaptation of interaction channels, not redesign of the supervisory workflow.

---

# Guiding Principle

> **The portable interface is not a smaller desktop. It is a context-aware control surface for a Supervisor that already sees the wider agent system.**

The user should navigate enough to establish *what they mean*, then let the Supervisor handle the complexity.

The smartphone prototype exists to validate that interaction model before committing to dedicated wearable hardware.
