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
    id: "loop-precursor",
    signal: "loop",
    skill: null,
    agents: null,
    instruction:
      "You have repeated the same call many times with similar inputs. Step back: re-read the error, form a different approach, delegate, or report the blocker — do not repeat the same call again.",
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
