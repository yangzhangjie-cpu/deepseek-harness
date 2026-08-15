import type { PropsRuntime } from '@deepseek-ai/dsh-client-ui-slots'
import type { ApiBalanceState } from './balance-controller.ts'
import css from './BalanceHeader.module.css'

export interface BalanceInjected {
  hooks: { balance: { getSnapshot: () => ApiBalanceState; subscribe: (listener: () => void) => () => void } }
  refresh: () => Promise<void>
}

export type BalanceHeaderProps = PropsRuntime<'conversation.session.header.utilities'> & {
  useBalance: <T>(selector: (state: ApiBalanceState) => T) => T
  refresh: () => Promise<void>
}

const SYMBOLS: Readonly<Record<string, string>> = { CNY: '¥', USD: '$' }

function balanceText(state: ApiBalanceState): string {
  if (state.status === 'idle' || state.status === 'loading' && state.balances.length === 0) return 'API 余额…'
  if (state.status === 'error' && state.balances.length === 0) {
    return state.error === 'missing-api-key' ? '未配置 API Key' : '余额获取失败'
  }
  const values = state.balances.map(row => `${SYMBOLS[row.currency] ?? `${row.currency} `}${row.total_balance}`)
  return `API 余额 ${values.join(' / ')}`
}

export function BalanceHeader({ useBalance, refresh }: BalanceHeaderProps) {
  const state = useBalance(value => value)
  return (
    <button
      type="button"
      className={css.balanceButton}
      aria-label="刷新 API 余额"
      aria-busy={state.status === 'loading'}
      title="每 30 秒自动刷新，点击立即刷新"
      onClick={() => { void refresh() }}
    >
      <span className={css.status} data-available={state.available === false ? 'false' : 'true'} />
      <span>{balanceText(state)}</span>
    </button>
  )
}
