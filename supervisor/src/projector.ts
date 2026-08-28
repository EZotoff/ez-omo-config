import { matchesMachineTemplate } from "./patterns"
import type { Message, Origin, OriginRegistry, Turn } from "./types"

function textOf(message: Message): string {
  return message.parts
    .filter((part) => part.type === "text" && typeof part.text === "string")
    .map((part) => part.text ?? "")
    .join("\n")
    .trim()
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
    const userText = textOf(user)
    const origin = classify(user, userText, registry)
    const next = messages[index + 1]
    const assistant = next?.role === "assistant" ? next : undefined
    const assistantText = assistant === undefined ? "" : textOf(assistant)
    const machine = origin === "machine-synthetic" || origin === "machine-template" || origin === "supervisor"
    const label = origin === "unknown" ? " [origin: unknown]" : ""
    const transcript = machine
      ? ""
      : `USER${label}: ${userText}${assistantText === "" ? "" : `\nASSISTANT: ${assistantText}`}`
    turns.push({
      sessionID: user.sessionID,
      userMessageID: user.id,
      ...(assistant === undefined ? {} : { assistantMessageID: assistant.id }),
      origin,
      userText,
      assistantText,
      transcript,
    })
  }
  return turns
}
