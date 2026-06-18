import { pathToFileURL } from 'node:url';

/** Reliable CLI entry detection on Windows and Unix. */
export function isMainModule(metaUrl: string): boolean {
  const entry = process.argv[1];
  if (!entry) return false;
  return metaUrl === pathToFileURL(entry).href;
}
