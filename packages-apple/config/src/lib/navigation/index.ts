import { existsSync } from 'node:fs'
import path from 'node:path'

import { type GeneratedFile, writeGeneratedFiles } from '../generated-file'
import { readYamlConfig } from '../yaml-config'

export type NavigationItem = {
  key: string
  title: string
  href: string
  icon: string
}

export type GenerateNavigationOptions = {
  projectRoot?: string
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value)

const validateNavigation = (value: unknown, file: string): NavigationItem[] => {
  if (
    !isObject(value) ||
    Object.keys(value).some(key => key !== 'navigation')
  ) {
    throw new Error(`${file} must contain only the navigation field`)
  }
  if (!Array.isArray(value.navigation) || value.navigation.length === 0) {
    throw new Error(`${file}.navigation must be a non-empty array`)
  }

  const keys = new Set<string>()
  return value.navigation.map((item: unknown, index: number) => {
    const location = `${file}.navigation[${index}]`
    if (!isObject(item)) throw new Error(`${location} must be a mapping`)
    const fields = ['key', 'title', 'href', 'icon']
    const unknownFields = Object.keys(item).filter(key => !fields.includes(key))
    if (unknownFields.length > 0) {
      throw new Error(
        `${location} has unsupported fields: ${unknownFields.join(', ')}`
      )
    }

    for (const field of fields) {
      if (typeof item[field] !== 'string' || !item[field].trim()) {
        throw new Error(`${location}.${field} must be a non-empty string`)
      }
    }

    const route = item as NavigationItem
    if (!/^[a-zA-Z_][a-zA-Z0-9_-]*$/.test(route.key)) {
      throw new Error(
        `${location}.key must use letters, digits, underscores, or hyphens`
      )
    }
    if (!route.href.startsWith('/') || route.href.startsWith('//')) {
      throw new Error(`${location}.href must be an absolute app path`)
    }
    if (keys.has(route.key))
      throw new Error(`Duplicate navigation key: ${route.key}`)
    keys.add(route.key)
    return route
  })
}

const swiftString = (value: string): string => {
  const escaped = Array.from(value, character => {
    const codePoint = character.codePointAt(0)!
    switch (codePoint) {
      case 0x22:
        return '\\"'
      case 0x5c:
        return '\\\\'
      case 0x0a:
        return '\\n'
      case 0x0d:
        return '\\r'
      case 0x09:
        return '\\t'
      default:
        return codePoint <= 0x1f || codePoint === 0x7f
          ? `\\u{${codePoint.toString(16)}}`
          : character
    }
  }).join('')
  return `"${escaped}"`
}

const getGeneratedNavigation = (items: NavigationItem[]): string => {
  const swiftItems = items
    .map(
      ({ key, title, href, icon }) =>
        `    SchoolRoute(key: ${swiftString(key)}, title: ${swiftString(title)}, href: ${swiftString(href)}, icon: ${swiftString(icon)})`
    )
    .join(',\n')

  return `// Generated from vx.nav.yaml. Do not edit.
import Foundation

struct SchoolRoute: Identifiable, Hashable {
  let key: String
  let title: String
  let href: String
  let icon: String
  var id: String { key }
}

enum GeneratedNavigation {
  static let routes: [SchoolRoute] = [
${swiftItems}
  ]
}
`
}

export const getNavigationFiles = (projectRoot: string): GeneratedFile[] => {
  const configFile = path.resolve(projectRoot, 'vx.nav.yaml')
  if (!existsSync(configFile))
    throw new Error(`Missing vx.nav.yaml at ${configFile}`)
  const config = readYamlConfig<unknown>(configFile)
  const navigation = validateNavigation(config, configFile)

  return [
    {
      path: path.join(
        path.resolve(projectRoot),
        'Shared/GeneratedNavigation.swift'
      ),
      content: getGeneratedNavigation(navigation)
    }
  ]
}

export const generateNavigation = (
  options: GenerateNavigationOptions = {}
): string[] => {
  const projectRoot = path.resolve(options.projectRoot ?? process.cwd())
  return writeGeneratedFiles(getNavigationFiles(projectRoot))
}
