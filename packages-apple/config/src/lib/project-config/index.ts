import { existsSync } from 'node:fs'
import path from 'node:path'

import { type GeneratedFile, writeGeneratedFiles } from '../generated-file'
import { readYamlConfig } from '../yaml-config'

export type ApplePlatform = 'ios' | 'macos'
export type DistributionMethod =
  | 'app-store-connect'
  | 'release-testing'
  | 'debugging'
  | 'enterprise'
  | 'developer-id'
  | 'mac-application'
  | 'validation'

export type AppleDeploymentTarget = {
  bundleIdentifier: string
  deploymentTarget: string
  distribution: DistributionMethod
}

export type AppleDeploymentConfig = {
  targets: Record<ApplePlatform, AppleDeploymentTarget>
}

export type AppleAppCore = {
  id: string
  name: string
  shortName: string
  version: string
  description: string
  publisher: {
    name: string
    url: string
  }
  url: string
}

export type AppleAppConfig = {
  core: AppleAppCore
}

export type GenerateProjectConfigOptions = {
  projectRoot?: string
}

type ConfigRecord = Record<string, unknown>

const distributionMethods: Record<
  ApplePlatform,
  readonly DistributionMethod[]
> = {
  ios: [
    'app-store-connect',
    'release-testing',
    'debugging',
    'enterprise',
    'validation'
  ],
  macos: [
    'app-store-connect',
    'release-testing',
    'debugging',
    'developer-id',
    'mac-application',
    'validation'
  ]
}

const isObject = (value: unknown): value is ConfigRecord =>
  typeof value === 'object' && value !== null && !Array.isArray(value)

const object = (
  value: unknown,
  file: string,
  location: string
): ConfigRecord => {
  if (!isObject(value))
    throw new Error(`${file}: ${location} must be a mapping`)
  return value
}

const string = (value: unknown, file: string, location: string): string => {
  if (typeof value !== 'string' || !value.trim()) {
    throw new Error(`${file}: ${location} must be a non-empty string`)
  }
  return value
}

const validateKeys = (
  value: ConfigRecord,
  file: string,
  location: string,
  required: readonly string[],
  allowed: readonly string[] = required
): void => {
  const missing = required.filter(key => !(key in value))
  const extra = Object.keys(value).filter(key => !allowed.includes(key))
  if (missing.length > 0) {
    throw new Error(
      `${file}: ${location} missing fields: ${missing.join(', ')}`
    )
  }
  if (extra.length > 0) {
    throw new Error(
      `${file}: ${location} has unsupported fields: ${extra.join(', ')}`
    )
  }
}

const validateUrl = (value: unknown, file: string, location: string): void => {
  const input = string(value, file, location)
  try {
    const parsed = new URL(input)
    if (!['http:', 'https:'].includes(parsed.protocol) || !parsed.hostname)
      throw new Error()
  } catch {
    throw new Error(`${file}: ${location} must be an absolute HTTP(S) URL`)
  }
}

const validateXcconfigValue = (
  value: unknown,
  file: string,
  location: string
): string => {
  const input = string(value, file, location)
  const hasControlCharacter = Array.from(input).some(
    character => character.charCodeAt(0) <= 0x1f
  )
  if (hasControlCharacter || /[\\#/$"]/.test(input)) {
    throw new Error(
      `${file}: ${location} contains characters that cannot be written safely to an xcconfig file`
    )
  }
  return input
}

const readFile = (root: string, filename: string): unknown => {
  const file = path.join(root, filename)
  if (!existsSync(file)) throw new Error(`Missing ${filename} at ${file}`)
  return readYamlConfig<unknown>(file)
}

const readAppConfig = (root: string): AppleAppConfig => {
  const file = 'vx.app.yaml'
  const config = object(readFile(root, file), file, 'top level')
  validateKeys(config, file, 'top level', ['core'])

  const core = object(config.core, file, 'core')
  const fields = [
    'id',
    'name',
    'shortName',
    'version',
    'description',
    'publisher',
    'url'
  ]
  validateKeys(core, file, 'core', fields)
  for (const field of ['id', 'name', 'shortName', 'version', 'description']) {
    string(core[field], file, `core.${field}`)
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(core.id as string)) {
    throw new Error(`${file}: core.id has an invalid format`)
  }
  if (
    !/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(
      core.version as string
    )
  ) {
    throw new Error(`${file}: core.version must be a SemVer version`)
  }
  validateUrl(core.url, file, 'core.url')

  const publisher = object(core.publisher, file, 'core.publisher')
  validateKeys(publisher, file, 'core.publisher', ['name', 'url'])
  string(publisher.name, file, 'core.publisher.name')
  validateUrl(publisher.url, file, 'core.publisher.url')
  return { core: core as unknown as AppleAppCore }
}

const readDeployConfig = (root: string): AppleDeploymentConfig => {
  const file = 'vx.deploy.yaml'
  const config = object(readFile(root, file), file, 'top level')
  validateKeys(config, file, 'top level', ['targets'])
  const targets = object(config.targets, file, 'targets')
  const platforms: ApplePlatform[] = ['ios', 'macos']
  validateKeys(targets, file, 'targets', platforms)

  const validatedTargets = Object.fromEntries(
    platforms.map(platform => {
      const target = object(targets[platform], file, `targets.${platform}`)
      validateKeys(target, file, `targets.${platform}`, [
        'bundleIdentifier',
        'deploymentTarget',
        'distribution'
      ])
      const bundleIdentifier = string(
        target.bundleIdentifier,
        file,
        `targets.${platform}.bundleIdentifier`
      )
      if (!/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/.test(bundleIdentifier)) {
        throw new Error(
          `${file}: targets.${platform}.bundleIdentifier is invalid`
        )
      }
      const deploymentTarget = string(
        target.deploymentTarget,
        file,
        `targets.${platform}.deploymentTarget`
      )
      if (!/^\d+\.\d+(?:\.\d+)?$/.test(deploymentTarget)) {
        throw new Error(
          `${file}: targets.${platform}.deploymentTarget must use major.minor[.patch] format`
        )
      }
      const distribution = string(
        target.distribution,
        file,
        `targets.${platform}.distribution`
      )
      if (
        !(distributionMethods[platform] as readonly string[]).includes(
          distribution
        )
      ) {
        throw new Error(
          `${file}: targets.${platform}.distribution must be one of: ${distributionMethods[platform].join(', ')}`
        )
      }
      return [platform, { bundleIdentifier, deploymentTarget, distribution }]
    })
  ) as AppleDeploymentConfig['targets']

  return { targets: validatedTargets }
}

const getXcconfig = (
  platform: ApplePlatform,
  target: AppleDeploymentTarget,
  core: AppleAppCore
): string => {
  const versionSetting =
    platform === 'ios'
      ? 'IPHONEOS_DEPLOYMENT_TARGET'
      : 'MACOSX_DEPLOYMENT_TARGET'
  const settings: Record<string, string> = {
    PRODUCT_BUNDLE_IDENTIFIER: target.bundleIdentifier,
    [versionSetting]: target.deploymentTarget,
    INFOPLIST_KEY_CFBundleDisplayName: validateXcconfigValue(
      core.shortName,
      'vx.app.yaml',
      'core.shortName'
    ),
    MARKETING_VERSION: core.version,
    VX_APP_ID: core.id,
    VX_APP_NAME: validateXcconfigValue(core.name, 'vx.app.yaml', 'core.name'),
    VX_APP_VERSION: core.version,
    VX_DISTRIBUTION_METHOD: target.distribution
  }

  return `// Generated from vx.app.yaml and vx.deploy.yaml. Do not edit.\n${Object.entries(
    settings
  )
    .map(([key, value]) => `${key} = ${value}`)
    .join('\n')}\n`
}

export const getProjectConfigFiles = (projectRoot: string): GeneratedFile[] => {
  const root = path.resolve(projectRoot)
  const appConfig = readAppConfig(root)
  const deployConfig = readDeployConfig(root)

  return (['ios', 'macos'] as const).map(platform => ({
    path: path.join(root, 'Config/Generated', `${platform}.xcconfig`),
    content: getXcconfig(
      platform,
      deployConfig.targets[platform],
      appConfig.core
    )
  }))
}

export const generateProjectConfig = (
  options: GenerateProjectConfigOptions = {}
): string[] => {
  const projectRoot = path.resolve(options.projectRoot ?? process.cwd())
  return writeGeneratedFiles(getProjectConfigFiles(projectRoot))
}
