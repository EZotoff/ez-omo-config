import { z } from "zod"
import type { Message, Session } from "./types"

const partSchema = z.object({
  id: z.string(), messageID: z.string(), type: z.string(), text: z.string().optional(), synthetic: z.boolean().optional(),
  tool: z.string().optional(), state: z.unknown().optional(),
}).passthrough()
const infoSchema = z.object({
  id: z.string(), sessionID: z.string(), role: z.enum(["user", "assistant"]),
  time: z.object({ created: z.number(), completed: z.number().optional() }).passthrough(),
  agent: z.string().optional(),
}).passthrough()
const messageEnvelopeSchema = z.object({ info: infoSchema, parts: z.array(partSchema) }).strict()
const sessionSchema = z.object({
  id: z.string(), directory: z.string(), parentID: z.string().optional(), parent_id: z.string().optional(), title: z.string().optional(),
  time: z.object({ created: z.number().optional(), updated: z.number().optional() }).passthrough().optional(),
}).passthrough()
const eventSchema = z.object({ type: z.string(), properties: z.record(z.string(), z.unknown()).optional() }).passthrough()

export type ServerEvent = z.infer<typeof eventSchema>

export class ClientError extends Error {
  readonly name = "ClientError"
  constructor(readonly operation: string, options?: ErrorOptions) {
    super(`opencode client failed: ${operation}`, options)
  }
}

const delay = (milliseconds: number, signal?: AbortSignal): Promise<void> =>
  Bun.sleep(milliseconds).then(() => {
    if (signal?.aborted === true) throw new DOMException("aborted", "AbortError")
  })

export type ClientAuth = { readonly username: string; readonly password: string }

export class OpencodeClient {
  constructor(readonly baseURL: string, private readonly auth?: ClientAuth) {}

  private authHeader(): Record<string, string> {
    if (this.auth === undefined) return {}
    const token = Buffer.from(`${this.auth.username}:${this.auth.password}`).toString("base64")
    return { Authorization: `Basic ${token}` }
  }

  private async request(path: string): Promise<unknown> {
    let lastError: Error | undefined
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        const response = await fetch(new URL(path, this.baseURL), { signal: AbortSignal.timeout(15_000), headers: this.authHeader() })
        if (!response.ok) throw new ClientError(`${path} HTTP ${response.status}`)
        return await response.json()
      } catch (error) {
        if (!(error instanceof Error)) throw error
        lastError = error
        if (attempt < 2) await delay(250 * 2 ** attempt)
      }
    }
    throw new ClientError(path, { cause: lastError })
  }

  async listSessions(directory: string): Promise<readonly Session[]> {
    const raw = z.array(sessionSchema).parse(await this.request(`/session?scope=project&directory=${encodeURIComponent(directory)}&limit=2000`))
    return raw.map((session) => {
      const parentID = session.parentID ?? session.parent_id
      const updated = session.time?.updated
      return {
        id: session.id,
        directory: session.directory,
        ...(parentID === undefined ? {} : { parentID }),
        ...(session.title === undefined ? {} : { title: session.title }),
        ...(updated === undefined ? {} : { timeUpdatedMs: updated }),
      }
    })
  }

  async listMessages(sessionID: string, directory: string): Promise<readonly Message[]> {
    const raw = z.array(messageEnvelopeSchema).parse(
      await this.request(`/session/${encodeURIComponent(sessionID)}/message?directory=${encodeURIComponent(directory)}`),
    )
    return raw.map(({ info, parts }) => ({
      id: info.id,
      sessionID: info.sessionID,
      role: info.role,
      time: { created: info.time.created, ...(info.time.completed === undefined ? {} : { completed: info.time.completed }) },
      ...(info.agent === undefined ? {} : { agent: info.agent }),
      parts: parts.map((part) => ({
        id: part.id,
        messageID: part.messageID,
        type: part.type,
        ...(part.text === undefined ? {} : { text: part.text }),
        ...(part.synthetic === undefined ? {} : { synthetic: part.synthetic }),
        ...(part.tool === undefined ? {} : { tool: part.tool }),
        ...(part.state === undefined ? {} : { state: part.state }),
      })),
    }))
  }

  async *events(directory: string, signal: AbortSignal): AsyncGenerator<ServerEvent> {
    let backoff = 500
    while (!signal.aborted) {
      try {
        const response = await fetch(new URL(`/event?directory=${encodeURIComponent(directory)}`, this.baseURL), { signal, headers: this.authHeader() })
        if (!response.ok || response.body === null) throw new ClientError(`event HTTP ${response.status}`)
        const reader = response.body.pipeThrough(new TextDecoderStream()).getReader()
        let buffer = ""
        while (!signal.aborted) {
          const chunk = await reader.read()
          if (chunk.done) break
          buffer += chunk.value
          const frames = buffer.split("\n\n")
          buffer = frames.pop() ?? ""
          for (const frame of frames) {
            const data = frame.split("\n").find((line) => line.startsWith("data:"))?.slice(5).trim()
            if (data !== undefined) yield eventSchema.parse(JSON.parse(data))
          }
        }
        backoff = 500
      } catch (error) {
        if (signal.aborted) return
        if (!(error instanceof Error)) throw error
        await delay(backoff, signal)
        backoff = Math.min(backoff * 2, 30_000)
      }
    }
  }
}
