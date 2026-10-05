import { matchesMachineTemplate } from "./patterns"
import { pendingQuestionPart, pendingQuestionText } from "./awaiting-input"
import type { Message, Origin, OriginRegistry, Turn } from "./types"

export function messageText(message: Message): string {
  return message.parts
    .filter((part) => part.type === "text" && typeof part.text === "string")
    .map((part) => part.text ?? "")
    .join("\n")
    .trim()
}

/**
 * The assistant run after a user message is ALL contiguous assistant messages
 * (reasoning-only and tool-only messages included), not just messages[i+1].
 * Taking only the immediate follower drops the text-bearing message whenever
 * it is preceded by reasoning/tool-only messages (corpus bug class, 31/217 items).
 */
export function contiguousAssistantRun(messages: readonly Message[], userIndex: number): readonly Message[] {
  const run: Message[] = []
  for (let index = userIndex + 1; index < messages.length && messages[index]?.role === "assistant"; index += 1) {
    run.push(messages[index]!)
  }
  return run
}

function classify(message: Message, text: string, registry: OriginRegistry): Origin {
  if (message.parts.some((part) => part.synthetic === true)) return "machine-synthetic"
  if (matchesMachineTemplate(text)) return "machine-template"
  if (registry.supervisorMessageIDs.has(message.id) || text.startsWith("[supervisor]")) return "supervisor"
  if (registry.humanMessageIDs.has(message.id)) return "human"
  return "unknown"
}

export function projectTurns(messages: readonly Message[], registry: OriginRegistry): readonly Turn[] {
  const turns: Turn[] = []
  for (let index = 0; index < messages.length; index += 1) {
    const user = messages[index]
    if (user?.role !== "user") continue
    const userText = messageText(user)
    const origin = classify(user, userText, registry)
    const assistantRun = contiguousAssistantRun(messages, index)
    const assistantText = assistantRun.map(messageText).filter((text) => text !== "").join("\n")
    const lastAssistant = assistantRun.at(-1)
    const machine = origin === "machine-synthetic" || origin === "machine-template" || origin === "supervisor"
    const label = origin === "unknown" ? " [origin: unknown]" : ""
    const pendingQuestion = pendingQuestionPart(assistantRun)
    turns.push({
      sessionID: user.sessionID,
      userMessageID: user.id,
      ...(lastAssistant === undefined ? {} : { assistantMessageID: lastAssistant.id }),
      origin,
      userText,
      assistantText,
      ...(pendingQuestion === undefined ? {} : { awaitingOperatorAnswer: true }),
      transcript: machine
        ? ""
        : `USER${label}: ${userText}${assistantText === "" ? "" : `\nASSISTANT: ${assistantText}`}${pendingQuestion === undefined ? "" : `\nASSISTANT: [awaiting operator answer via question tool: ${pendingQuestionText(pendingQuestion)}]`}`,
    })
  }
  return turns
}
