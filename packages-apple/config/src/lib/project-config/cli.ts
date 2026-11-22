#!/usr/bin/env node
import { generateProjectConfig } from './index'

const [, , command = 'generate', projectRoot = process.cwd()] = process.argv

if (command === 'generate') {
  const files = generateProjectConfig({ projectRoot })
  console.log(
    `Generated ${files.length} Apple project config file(s) for ${projectRoot}`
  )
} else {
  console.error(
    `Unknown Apple project config command "${command}". Use "generate".`
  )
  process.exitCode = 1
}
