// Node APIs used by the test runner; they are not part of the browser bundle.
declare module "node:path" {
  export function resolve(...paths: string[]): string
}

declare module "node:url" {
  export function fileURLToPath(path: URL | string): string
  export function pathToFileURL(path: string): URL
}

declare module "node:process" {
  export const env: Record<string, string | undefined>
}
