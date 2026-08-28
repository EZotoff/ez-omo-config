export type MachineWriterPattern = {
  readonly writer: "ralph-loop" | "provider-connect-retry" | "aspect-dynamics" | "system-notification"
  readonly regex: RegExp
  readonly description: string
}

export const patternFixtures = {
  ralph: "[SYSTEM DIRECTIVE: OH-MY-OPENCODE - RALPH LOOP 2/100]\nContinue. Output <promise>DONE</promise> when done.\nBuild it",
  retry: "Proceed with the execution of the plan NOW. Give me response.",
  aspect: "[ASPECT-DYNAMICS-NUDGE v1]\nAspect: distress\nInstruction: Be direct\nEvidence: Scored 0.90 with 3 weighted hits\nApply this guidance quietly in your next reply. Do not mention the nudge explicitly.",
} as const

const retryPrompts = [
  "Proceed with the execution of the plan NOW. Give me response.",
  "Continue working on the current task. Follow your todos and produce output.",
  "You were in the middle of work. Resume immediately — check your todo list and act on the next item.",
  "RESPOND NOW. Review the conversation above, find where you left off, and continue from there.",
  "This is your final retry. Execute the next step of your plan immediately. Do not output an empty response.",
  "Continue with the execution of the plan please, following the last executed steps, todos or plans.",
  "Proceed with your work. Check what was done so far and move to the next step.",
  "Resume the task. Look at the todos, find the next incomplete item, and execute it now.",
  "You must respond with actual content. Review the plan and continue working on the next pending task.",
  "FINAL ATTEMPT — respond immediately. Check your todos and plans, then execute the next action step.",
  "Continue. Produce your response now.",
  "Proceed now. Use the current context and respond directly.",
  "Resume working. Check what needs to be done next and do it.",
  "You need to respond with content. Review the context above and continue.",
  "FINAL RETRY — you must produce a response now. Review everything and act.",
] as const

const escapeRegex = (text: string): string => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")

export const machineWriterPatterns: readonly MachineWriterPattern[] = [
  {
    writer: "ralph-loop",
    regex: /^(?:ultrawork\s+)?\[SYSTEM DIRECTIVE: OH-MY-OPENCODE - (?:RALPH LOOP|ULTRAWORK LOOP VERIFICATION(?: FAILED)?) \d+\/(?:\d+|unbounded)\]/,
    description: "OMO ralph-loop continuation and verification prompts",
  },
  {
    writer: "provider-connect-retry",
    regex: new RegExp(`^(?:${retryPrompts.map(escapeRegex).join("|")})$`),
    description: "provider-connect-retry escalating nudge prompts",
  },
  {
    writer: "system-notification",
    // OMO/system background-task notifications and internal markers are injected
    // as ordinary user-role messages without the synthetic flag (observed live:
    // 60 of 124 "human-visible" veran turns in a 21-day window were these).
    regex: /^<system-reminder>|<!-- OMO_INTERNAL_(?:INITIATOR|NOREPLY) -->/,
    description: "OMO/system background notifications injected as user messages",
  },
  {
    writer: "aspect-dynamics",
    regex: /^\[ASPECT-DYNAMICS-NUDGE v1\]\nAspect: .+\nInstruction: .+\nEvidence: Scored \d+\.\d{2} with \d+ weighted hits\nApply this guidance quietly in your next reply\. Do not mention the nudge explicitly\.$/s,
    description: "aspect-dynamics transcript-visible advisory nudge",
  },
] as const

export function matchesMachineTemplate(text: string): boolean {
  return machineWriterPatterns.some((entry) => entry.regex.test(text))
}
