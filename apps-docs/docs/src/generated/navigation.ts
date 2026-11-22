// Generated from vx.nav.yaml. DO NOT EDIT.
import type { AppNavigationItem, AppMenuItem } from '@vezham/react'
import type { ControlCenterConfig } from '@vezham/react/control-center'

export const navigationItems = [] satisfies AppNavigationItem[]

export const appMenu = [] satisfies AppMenuItem[]

export const controlCenter = {
  "tiles": []
} satisfies ControlCenterConfig

export const getNavigationChildren = (key: string) => {
  const items: readonly AppNavigationItem[] = navigationItems
  const item = items.find(item => item.key === key)
  if (!item) {
    throw new Error('Unknown navigation key: ' + key)
  }
  return 'children' in item && Array.isArray(item.children) ? item.children : []
}
