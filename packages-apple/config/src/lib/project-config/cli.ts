#!/usr/bin/env node
import { generateProjectConfig, readDeployConfig } from './index'

const [, , command = 'generate', projectRoot = process.cwd()] = process.argv

if (command === 'generate') {
  const files = generateProjectConfig({ projectRoot })
  console.log(
    `Generated ${files.length} Apple project config file(s) for ${projectRoot}`
  )
} else if (command === 'deployment') {
  console.log(JSON.stringify(readDeployConfig(projectRoot)))
} else {
  console.error(
    `Unknown Apple project config command "${command}". Use "generate" or "deployment".`
  )
  process.exitCode = 1
}
