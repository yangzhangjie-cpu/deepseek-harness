import type { PropsRuntime } from '@deepseek-ai/dsh-client-ui-slots'
import { IconRefreshOutline16 } from '@deepseek-ai/dsh-client-ui-primitives'
import type { ApiBalanceState } from './balance-controller.ts'
import css from './BalanceSettingsRow.module.css'

export type BalanceSettingsRowProps = PropsRuntime<'settings.general.item'> & {
  useBalance: <T>(selector: (state: ApiBalanceState) => T) => T
  refresh: () => Promise<void>
}

export function BalanceSettingsRow({ useBalance, refresh }: BalanceSettingsRowProps) {
  const state = useBalance(value => value)
  return (
    <div className={css.row}>
      <div className={css.text}>
        <div className={css.title}>API 余额</div>
        <div className={css.description}>右上角余额默认每 30 秒刷新一次</div>
      </div>
      <button
        type="button"
        className={css.refresh}
        disabled={state.status === 'loading'}
        onClick={() => { void refresh() }}
      >
        <IconRefreshOutline16 />
        <span>{state.status === 'loading' ? '更新中…' : '立即更新'}</span>
      </button>
    </div>
  )
}
