import { mkdirSync, writeFileSync } from 'node:fs'
import path from 'node:path'

export type GeneratedFile = {
  path: string
  content: string
}

export const writeGeneratedFiles = (files: GeneratedFile[]): string[] => {
  for (const file of files) {
    mkdirSync(path.dirname(file.path), { recursive: true })
    writeFileSync(file.path, file.content)
  }

  return files.map(({ path: filePath }) => filePath)
}
