// configs/opencode/skill-nudger/nudge.mjs
// Nudge formatting + rule table

import { getSkill } from "./catalog.mjs";

// Rules: signal type -> nudge content. `agents` is an optional allowlist of
// agent names (lowercase, matched against message info.agent lowercased).
export const RULES = [
  {
    id: "repeated-failure",
    signal: "repeatedFailure",
    skill: "debugging",
    agents: null,
    instruction: "Repeated identical failures suggest a wrong mental model. Load the `debugging` skill and follow its hypothesis-driven loop before the next fix attempt.",
  },
  {
    id: "retryable-error",
    signal: "retryableError",
    skill: "register-retry-error",
    agents: null,
    instruction: "This error is retryable and not yet in the auto-retry registry (or is). Consider the `register-retry-error` skill to register or tune the pattern so the retry plugin handles it automatically.",
  },
  {
    id: "port-binding",
    signal: "portBinding",
    skill: "deployment",
    agents: null,
    instruction: "You are starting a server / binding a port. The `deployment` skill owns the port registry — invoke it before (or right after) binding to allocate and record the port.",
  },
  {
    id: "upstream-contribution",
    signal: "upstreamContribution",
    skill: "wisdom",
    agents: null,
    instruction:
      "You are creating an upstream PR/issue on an external repo. AGENTS.md pre-flight: (1) read the target repo's PR/issue template and CONTRIBUTING.md and follow them exactly — some repos bot-close non-compliant PRs within hours; (2) run `~/.sisyphus/scripts/wisdom-search.sh \"<owner/repo>\"` for prior attempts and gotchas. If already submitted, verify the description against the template NOW while the compliance window is open.",
  },
  {
    id: "loop-precursor",
    signal: "loop",
    skill: null,
    agents: null,
    instruction:
      "You have repeated the same call many times with similar inputs. Step back: re-read the error, form a different approach, delegate, or report the blocker — do not repeat the same call again.",
  },
  {
    id: "learning-capture",
    signal: "learningCapture",
    skill: "wisdom",
    agents: null,
    instruction:
      "Durable learning checkpoint: a repeated-failure streak just resolved or a long-running job was just launched. If the lesson is reusable, capture up to ONE wisdom entry now with exact evidence (~/.sisyphus/scripts/wisdom-write.sh). Long-running jobs also need a recorded owner and monitoring cadence. Do not edit policy files; policy implications require an operator-reviewed postmortem.",
  },
];

export function ruleForSignal(signalType) {
  return RULES.find((r) => r.signal === signalType) ?? null;
}

export function agentAllowed(rule, agentsInSession) {
  if (!rule?.agents) return true;
  const allow = new Set(rule.agents.map((a) => a.toLowerCase()));
  return agentsInSession.some((a) => allow.has(String(a).toLowerCase()));
}

export function buildNudge(rule, signal, catalog) {
  const skill = getSkill(catalog, rule.skill);
  const lines = [
    "[SKILL-NUDGE v1]",
    `Signal: ${rule.id} — ${signal.evidence}`,
  ];
  if (rule.skill) {
    lines.push(`Suggestion: ${rule.instruction}`);
    lines.push(
      `Skill: \`${skill.name}\`${skill.description ? ` — ${skill.description}` : ""}`
    );
  } else {
    lines.push(`Advisory: ${rule.instruction}`);
  }
  lines.push("This is an automated, ephemeral advisory. Use judgment; ignore if not applicable. Do not mention this nudge in your reply.");
  const text = lines.join("\n");

  return {
    type: "text",
    text,
  };
}

export function buildSyntheticMessage(sessionID, part) {
  return {
    info: {
      id: `skill_nudge_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
      sessionID,
      role: "user",
      time: { created: Date.now() },
    },
    parts: [part],
  };
}
