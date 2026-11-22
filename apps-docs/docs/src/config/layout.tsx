import type { BaseLayoutProps } from '@vezham/docs-react/layouts/shared'
import { VezhamLogo } from '@vezham/icons-react'
import { localizedUrl } from '@vezham/start/runtime/docs'

import { i18n } from '@app/docs'
import type { Locale } from '@generated/vx'

export const baseOptions = (
  locale: Locale = i18n.defaultLanguage
): BaseLayoutProps => {
  return {
    nav: {
      title: (
        <span className="inline-flex items-center gap-2 font-semibold">
          <VezhamLogo size={22} />
          Apple Docs
        </span>
      )
    },
    links: [
      {
        text: 'Ark',
        url: localizedUrl(i18n, locale, '/docs/ark'),
        active: 'nested-url'
      }
    ]
  }
}
