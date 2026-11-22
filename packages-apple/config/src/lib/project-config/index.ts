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

export type MacReleaseConfig = {
  scheme: string
  productName: string
  teamId?: string
  sparkle?: {
    feedUrl: string
    publicKey: string
    downloadBaseUrl: string
    bucket?: string
  }
}

export type AppleDeploymentConfig = {
  targets: {
    ios: AppleDeploymentTarget
    macos: AppleDeploymentTarget & { release?: MacReleaseConfig }
  }
  filterRulesUrl?: string
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

const readHttpsUrl = (
  value: unknown,
  file: string,
  location: string
): string => {
  const input = string(value, file, location)
  try {
    const url = new URL(input)
    if (
      !input.startsWith('https://') ||
      !url.hostname ||
      url.username ||
      url.password ||
      url.search ||
      url.hash ||
      /[\s?#"$\\]/.test(input)
    )
      throw new Error()
    return url.href
  } catch {
    throw new Error(
      `${file}: ${location} must be an absolute HTTPS URL without credentials, query or fragment`
    )
  }
}

const readMacRelease = (value: unknown, file: string): MacReleaseConfig => {
  const location = 'targets.macos.release'
  const release = object(value, file, location)
  validateKeys(
    release,
    file,
    location,
    ['scheme', 'productName'],
    ['scheme', 'productName', 'teamId', 'sparkle']
  )
  const scheme = string(release.scheme, file, `${location}.scheme`)
  const productName = string(
    release.productName,
    file,
    `${location}.productName`
  )
  if (
    ![scheme, productName].every(
      value =>
        /^[A-Za-z0-9][A-Za-z0-9 ._-]*$/.test(value) && value === value.trim()
    )
  ) {
    throw new Error(
      `${file}: ${location} scheme and productName must be valid names`
    )
  }
  const result: MacReleaseConfig = { scheme, productName }
  if ('teamId' in release) {
    const teamId = string(release.teamId, file, `${location}.teamId`)
    if (!/^[A-Z0-9]{10}$/.test(teamId))
      throw new Error(
        `${file}: ${location}.teamId must be a 10-character Apple team ID`
      )
    result.teamId = teamId
  }
  if ('sparkle' in release) {
    const key = `${location}.sparkle`
    const sparkle = object(release.sparkle, file, key)
    validateKeys(
      sparkle,
      file,
      key,
      ['feedUrl', 'publicKey', 'downloadBaseUrl'],
      ['feedUrl', 'publicKey', 'downloadBaseUrl', 'bucket']
    )
    const feedUrl = readHttpsUrl(sparkle.feedUrl, file, `${key}.feedUrl`)
    const downloadBaseUrl = readHttpsUrl(
      sparkle.downloadBaseUrl,
      file,
      `${key}.downloadBaseUrl`
    )
    const publicKey = string(sparkle.publicKey, file, `${key}.publicKey`)
    if (!/^[A-Za-z0-9+/]{43}=$/.test(publicKey))
      throw new Error(
        `${file}: ${key}.publicKey must be a base64 Sparkle public key`
      )
    result.sparkle = {
      feedUrl,
      publicKey,
      downloadBaseUrl: downloadBaseUrl.endsWith('/')
        ? downloadBaseUrl
        : `${downloadBaseUrl}/`
    }
    if ('bucket' in sparkle) {
      const bucket = string(sparkle.bucket, file, `${key}.bucket`)
      if (!/^[a-z0-9][a-z0-9-]*[a-z0-9]$/.test(bucket))
        throw new Error(`${file}: ${key}.bucket is invalid`)
      result.sparkle.bucket = bucket
    }
  }
  return result
}

export const readDeployConfig = (root: string): AppleDeploymentConfig => {
  const file = 'vx.deploy.yaml'
  const config = object(readFile(root, file), file, 'top level')
  validateKeys(
    config,
    file,
    'top level',
    ['targets'],
    ['targets', 'filterRulesUrl']
  )
  const targets = object(config.targets, file, 'targets')
  const platforms: ApplePlatform[] = ['ios', 'macos']
  validateKeys(targets, file, 'targets', platforms)

  const validatedTargets = Object.fromEntries(
    platforms.map(platform => {
      const target = object(targets[platform], file, `targets.${platform}`)
      const required = ['bundleIdentifier', 'deploymentTarget', 'distribution']
      const allowed = platform === 'macos' ? [...required, 'release'] : required
      validateKeys(target, file, `targets.${platform}`, required, allowed)
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
      const release =
        'release' in target ? readMacRelease(target.release, file) : undefined
      return [
        platform,
        {
          bundleIdentifier,
          deploymentTarget,
          distribution,
          ...(release && { release })
        }
      ]
    })
  ) as AppleDeploymentConfig['targets']

  const filterRulesUrl =
    'filterRulesUrl' in config
      ? readHttpsUrl(config.filterRulesUrl, file, 'filterRulesUrl')
      : undefined
  return {
    targets: validatedTargets,
    ...(filterRulesUrl && { filterRulesUrl })
  }
}

const getXcconfig = (
  platform: ApplePlatform,
  target: AppleDeploymentTarget & { release?: MacReleaseConfig },
  core: AppleAppCore,
  filterRulesUrl?: string
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
    VX_APP_BUNDLE_IDENTIFIER: target.bundleIdentifier,
    VX_APP_NAME: validateXcconfigValue(core.name, 'vx.app.yaml', 'core.name'),
    VX_APP_VERSION: core.version,
    VX_DISTRIBUTION_METHOD: target.distribution
  }

  // vx-bot/NOTE: A literal // starts a comment in xcconfig files.
  const escapedUrl = (url: string): string =>
    url.replaceAll('//', '$(VX_URL_SLASH)$(VX_URL_SLASH)')
  if (filterRulesUrl || target.release?.sparkle) settings.VX_URL_SLASH = '/'

  if (target.release) {
    settings.VX_MAC_PRODUCT_NAME = target.release.productName
    if (target.release.teamId) settings.DEVELOPMENT_TEAM = target.release.teamId
    if (target.release.sparkle) {
      settings.VX_SPARKLE_PUBLIC_KEY = target.release.sparkle.publicKey
      settings.VX_SPARKLE_FEED_URL = escapedUrl(target.release.sparkle.feedUrl)
    }
  }
  if (filterRulesUrl) {
    settings.VX_FILTER_RULES_URL = escapedUrl(filterRulesUrl)
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
      appConfig.core,
      deployConfig.filterRulesUrl
    )
  }))
}

export const generateProjectConfig = (
  options: GenerateProjectConfigOptions = {}
): string[] => {
  const projectRoot = path.resolve(options.projectRoot ?? process.cwd())
  return writeGeneratedFiles(getProjectConfigFiles(projectRoot))
}
