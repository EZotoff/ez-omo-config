import { z } from "zod"

export interface ReasoningAdapter {
  complete(prompt: string): Promise<string>
}

const responseSchema = z.object({
  choices: z.array(z.object({ message: z.object({ content: z.string() }).passthrough() }).passthrough()).min(1),
}).passthrough()

export class AdapterError extends Error {
  readonly name = "AdapterError"
  constructor(readonly status: number | undefined, options?: ErrorOptions) {
    super("reasoning adapter request failed", options)
  }
}

export class ZaiAdapter implements ReasoningAdapter {
  constructor(readonly baseURL: string, readonly model: string, private readonly apiKey: string) {}

  async complete(prompt: string): Promise<string> {
    let lastError: Error | undefined
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        const response = await fetch(`${this.baseURL.replace(/\/$/, "")}/chat/completions`, {
          method: "POST",
          headers: { authorization: `Bearer ${this.apiKey}`, "content-type": "application/json" },
          body: JSON.stringify({ model: this.model, messages: [{ role: "user", content: prompt }], response_format: { type: "json_object" }, tools: [] }),
          signal: AbortSignal.timeout(120_000),
        })
        if (!response.ok) throw new AdapterError(response.status)
        const parsed = responseSchema.parse(await response.json())
        const content = parsed.choices[0]?.message.content
        if (content === undefined) throw new AdapterError(response.status)
        return content
      } catch (error) {
        if (!(error instanceof Error)) throw error
        lastError = error
        if (attempt === 0) await Bun.sleep(1000)
      }
    }
    throw new AdapterError(undefined, { cause: lastError })
  }
}
