#!/usr/bin/env node
import { generateNavigation } from './index'

const [, , command = 'generate', projectRoot = process.cwd()] = process.argv

if (command === 'generate') {
  const files = generateNavigation({ projectRoot })
  console.log(`Generated ${files.length} navigation file(s) for ${projectRoot}`)
} else {
  console.error(
    `Unknown Apple navigation command "${command}". Use "generate".`
  )
  process.exitCode = 1
}
