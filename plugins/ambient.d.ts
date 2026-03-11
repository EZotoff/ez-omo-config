declare const Bun: {
	file(path: string): {
		text(): Promise<string>
		exists(): Promise<boolean>
	}
	spawn(args: string[], options?: any): {
		stdout: any
		stderr: any
		exited: Promise<number>
		kill(): void
	}
	spawnSync(args: string[], options?: any): {
		success?: boolean
		exitCode?: number
		stdout?: any
		stderr?: any
	}
	write(path: string, data: any): Promise<void>
	sleep(ms: number): Promise<void>
	sleepSync(ms: number): void
	randomUUIDv7(): string
}
declare const process: {
	env: Record<string, string | undefined>
	platform: string
	once(event: string, listener: (...args: any[]) => void): void
}
type Timer = ReturnType<typeof setTimeout>

declare module "bun:sqlite" {
	export class Database {
		constructor(path: string)
		exec(sql: string): void
		prepare(sql: string): {
			run(params?: any): any
			get(params?: any): any
			all(params?: any): any[]
		}
		close(): void
	}
}

declare module "node:fs" {
	export const appendFileSync: any
	export const mkdirSync: any
	export const readFileSync: any
	export const realpathSync: { native(path: string): string }
}

declare module "node:fs/promises" {
	export const access: any
	export const chmod: any
	export const copyFile: any
	export const cp: any
	export const mkdir: any
	export const rm: any
	export const stat: any
	export const symlink: any
}

declare module "node:path" {
	export const dirname: (...args: any[]) => string
	export const isAbsolute: (...args: any[]) => boolean
	export const join: (...args: any[]) => string
	export const resolve: (...args: any[]) => string
	export const sep: string
}

declare module "node:os" {
	export const homedir: () => string
	export const release: () => string
	export const tmpdir: () => string
}

declare module "node:crypto" {
	export const createHash: (...args: any[]) => { update: (...inner: any[]) => { digest: (...digestArgs: any[]) => string } }
}

declare module "@opencode-ai/plugin" {
	type ToolSchema<T = any> = {
		describe(description: string): ToolSchema<T>
		optional(): ToolSchema<T | undefined>
	}

	type ToolCallback = (args: any, toolCtx: { sessionID: string }) => any
	type HookInput = {
		tool: string
		args: any
		callID?: string
		sessionID?: string
	}
	type HookBeforeOutput = { args: any }
	type HookAfterOutput = { output?: string }
	type PluginContext = { directory: string; client: any }
	type PluginDefinition = {
		tool?: Record<string, any>
		event?: (input: { event: any }) => Promise<void> | void
		"tool.execute.before"?: (input: HookInput, output: HookBeforeOutput) => Promise<void> | void
		"tool.execute.after"?: (input: HookInput, output: HookAfterOutput) => Promise<void> | void
	}

	export type Plugin = (ctx: PluginContext) => Promise<PluginDefinition> | PluginDefinition
	export function tool(config: {
		description?: string
		args?: Record<string, any>
		execute?: ToolCallback
	}): any
	export namespace tool {
		const schema: {
			string(): ToolSchema<string>
		}
	}
}

declare module "@opencode-ai/sdk" {
	export type Event = { type: string; [key: string]: any }
	export function createOpencodeClient(...args: any[]): any
}

declare module "jsonc-parser" {
	export const parse: any
}

declare module "zod" {
	type ZodResult<T> = { success: true; data: T } | { success: false; error: { issues: Array<{ message?: string }> } }
	type ZodSchema<T = any> = {
		parse(value: unknown): T
		safeParse(value: unknown): ZodResult<T>
		min(length: number, message?: string): ZodSchema<T>
		max(length: number, message?: string): ZodSchema<T>
		refine(check: (value: T) => boolean, message?: any): ZodSchema<T>
		optional(): ZodSchema<T | undefined>
		default(value: any): ZodSchema<T>
		describe(description: string): ZodSchema<T>
	}

	export const z: {
		string(): ZodSchema<string>
		array<T>(schema: ZodSchema<T>): ZodSchema<T[]>
		object<T extends Record<string, unknown>>(shape: T): ZodSchema<any>
	}
	export namespace z {
		export type infer<_T> = any
	}
}
