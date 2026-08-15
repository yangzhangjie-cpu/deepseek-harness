import { useEffect, useState } from 'react'
import type { PropsRuntime } from '@deepseek-ai/dsh-client-ui-slots'
import { IconRefreshOutline16 } from '@deepseek-ai/dsh-client-ui-primitives'
import css from './BalanceSettingsRow.module.css'

type DesktopUpdateBridge = {
  version: string
}

type UpdateState = {
  status: 'idle' | 'checking' | 'available' | 'downloading' | 'downloaded'
  message: string
}

declare global {
  interface Window {
    __DEEPSEEK_HARNESS_DESKTOP__?: DesktopUpdateBridge
    webkit?: {
      messageHandlers?: {
        desktopHarness?: { postMessage: (message: unknown) => void }
      }
    }
  }
}

/** Return whether the browser runs inside the supported desktop wrapper. */
export function hasDesktopUpdateBridge(): boolean {
  return typeof window !== 'undefined' && window.__DEEPSEEK_HARNESS_DESKTOP__ !== undefined
}

/** Render the desktop-only software update action in General settings. */
export function SoftwareUpdateSettingsRow(_props?: Partial<PropsRuntime<'settings.general.item'>>) {
  const version = window.__DEEPSEEK_HARNESS_DESKTOP__?.version ?? '未知'
  const [state, setState] = useState<UpdateState>({ status: 'idle', message: `当前版本 ${version}` })
  useEffect(() => {
    const receive = (event: Event) => {
      const detail = (event as CustomEvent<UpdateState>).detail
      setState(detail)
    }
    window.addEventListener('deepseek-harness-update-state', receive)
    return () => { window.removeEventListener('deepseek-harness-update-state', receive) }
  }, [])
  const busy = state.status === 'checking' || state.status === 'downloading'
  return (
    <div className={css.row}>
      <div className={css.text}>
        <div className={css.title}>软件更新</div>
        <div className={css.description}>{state.message}</div>
      </div>
      <button
        type="button"
        className={css.refresh}
        disabled={busy}
        onClick={() => { window.webkit?.messageHandlers?.desktopHarness?.postMessage({ action: 'check-update' }) }}
      >
        <IconRefreshOutline16 />
        <span>{state.status === 'checking' ? '检查中…' : state.status === 'downloading' ? '下载中…' : '检查更新'}</span>
      </button>
    </div>
  )
}
