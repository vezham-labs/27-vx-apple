import { Link } from '@tanstack/react-router'

import { HomeLayout } from '@vezham/docs-react/layouts/home'
import { buttonVariants } from '@vezham/react-v3'
import { localizedRouteParam } from '@vezham/start/runtime/docs'

import { i18n } from '@app/docs'
import { baseOptions } from '@config/layout'
import type { Locale } from '@generated/vx'

type Props = {
  locale?: Locale
}

export default ({ locale }: Props) => {
  const lang = localizedRouteParam(i18n, locale)

  return (
    <HomeLayout {...baseOptions(locale)}>
      <main className="mx-auto max-w-3xl px-6 py-20">
        <h1 className="mb-4 text-4xl font-semibold tracking-tight">
          Vezham Apple Docs
        </h1>
        <p className="mb-6">
          Engineering guides and integration notes for Vezham Apple apps.
        </p>
        <Link
          to="/{-$lang}/docs"
          params={{ lang }}
          className={buttonVariants({ variant: 'primary' })}>
          Open docs
        </Link>
      </main>
    </HomeLayout>
  )
}
