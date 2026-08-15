/** Browser-side DeepSeek balance polling controller. */

export interface ApiBalanceInfo {
  readonly currency: string
  readonly total_balance: string
  readonly granted_balance: string
  readonly topped_up_balance: string
}

/** Immutable browser projection of the latest DeepSeek account-balance request. */
export interface ApiBalanceState {
  readonly status: 'idle' | 'loading' | 'ready' | 'error'
  readonly available?: boolean
  readonly balances: readonly ApiBalanceInfo[]
  readonly updatedAt?: number
  readonly error?: string | undefined
}

const INITIAL_STATE: ApiBalanceState = { status: 'idle', balances: [] }
const REFRESH_INTERVAL_MS = 30_000

function isBalanceInfo(value: unknown): value is ApiBalanceInfo {
  if (typeof value !== 'object' || value === null) return false
  const row = value as Record<string, unknown>
  return typeof row.currency === 'string'
    && typeof row.total_balance === 'string'
    && typeof row.granted_balance === 'string'
    && typeof row.topped_up_balance === 'string'
}

/** Owns immediate/manual balance refreshes and the single 30-second polling timer. */
export class ApiBalanceController {
  private snapshot = INITIAL_STATE
  private readonly listeners = new Set<() => void>()
  private readonly interval: ReturnType<typeof setInterval>
  private pending: Promise<void> | undefined

  /** External-store adapter consumed by header and settings React slots. */
  readonly store = {
    getSnapshot: (): ApiBalanceState => this.snapshot,
    subscribe: (listener: () => void): (() => void) => {
      this.listeners.add(listener)
      return () => { this.listeners.delete(listener) }
    },
  }

  constructor() {
    void this.refresh()
    this.interval = setInterval(() => { void this.refresh() }, REFRESH_INTERVAL_MS)
  }

  /** Refresh now; concurrent callers share one in-flight request. */
  refresh(): Promise<void> {
    if (this.pending !== undefined) return this.pending
    this.publish({ ...this.snapshot, status: 'loading', error: undefined })
    this.pending = this.load().finally(() => { this.pending = undefined })
    return this.pending
  }

  /** Stop polling and release every store subscriber. */
  dispose(): void {
    clearInterval(this.interval)
    this.listeners.clear()
  }

  private async load(): Promise<void> {
    try {
      const response = await fetch('/api/desktop.balance', { headers: { accept: 'application/json' } })
      if (!response.ok) throw new Error(response.status === 401 ? 'missing-api-key' : `http-${response.status}`)
      const value: unknown = await response.json()
      if (typeof value !== 'object' || value === null) throw new Error('invalid-response')
      const body = value as Record<string, unknown>
      if (typeof body.is_available !== 'boolean' || !Array.isArray(body.balance_infos)
        || !body.balance_infos.every(isBalanceInfo)) throw new Error('invalid-response')
      this.publish({
        status: 'ready',
        available: body.is_available,
        balances: body.balance_infos,
        updatedAt: Date.now(),
      })
    } catch (error) {
      this.publish({
        ...this.snapshot,
        status: 'error',
        error: error instanceof Error ? error.message : String(error),
      })
    }
  }

  private publish(next: ApiBalanceState): void {
    this.snapshot = next
    for (const listener of this.listeners) listener()
  }
}
