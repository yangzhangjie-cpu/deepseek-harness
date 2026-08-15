import { Context } from '@deepseek-ai/cordis'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { SlotRegistry } from '@deepseek-ai/dsh-client-runtime/client'
import type { SessionId } from '@deepseek-ai/dsh-client-runtime/client'
import { LocaleRuntime } from '@deepseek-ai/dsh-client-locale/client'
import type {} from '@deepseek-ai/dsh-client-ui-conversation/client'
import { SessionLogDownloadHeaderAction } from '../src/client/HeaderAction.tsx'
import { apply, inject } from '../src/client/index.ts'
import { SoftwareUpdateSettingsRow } from '../src/client/SoftwareUpdateSettingsRow.tsx'

const SID = 'session-export-apply' as SessionId

afterEach(() => { vi.unstubAllGlobals() })

function declare(slots: SlotRegistry): () => void {
  return slots.register({
    name: 'root',
    children: {
      'conversation.session.header.actions': { kind: 'list', scope: 'session' },
      'conversation.session.header.utilities': { kind: 'list', scope: 'session' },
      'settings.general.item': { kind: 'list', scope: 'global' },
    },
  } as never, () => null)
}

async function bench() {
  const ctx = new Context()
  await ctx.plugin(SlotRegistry).await()
  const slots = ctx.get('slots') as SlotRegistry
  const declaration = declare(slots)
  ctx.provide('locale', new LocaleRuntime(ctx))
  const fiber = ctx.plugin({ inject: [...inject], apply })
  await fiber.await()
  return { ctx, slots, declaration, fiber }
}

describe('session-log-download browser plugin', () => {
  it('registers the software update row only inside the desktop wrapper', async () => {
    vi.stubGlobal('window', { __DEEPSEEK_HARNESS_DESKTOP__: { version: '0.1.0' } })
    const b = await bench()
    const entry = b.slots.entries('settings.general.item')
      .find(candidate => candidate.options?.id === 'desktop-software-update')
    expect(entry?.component).toBe(SoftwareUpdateSettingsRow)
    await b.fiber.dispose()
  })

  it('provides one controller and removes its Header contribution on disposal', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('', { status: 500 })))
    const b = await bench()
    expect(inject).toEqual(['slots', 'locale'])
    expect(b.ctx.sessionLogDownload).toBeDefined()
    expect(b.slots.entries('conversation.session.header.actions')).toHaveLength(0)
    const entry = b.slots.entries('conversation.session.header.utilities')
      .find(candidate => candidate.options?.id === 'session-log-download')
    expect(entry?.component).toBe(SessionLogDownloadHeaderAction)
    expect(entry?.options).toMatchObject({ id: 'session-log-download' })
    const injected = (entry?.inject as unknown as () => import('../src/client/Dialog.tsx').SessionLogDownloadDialogInjected)()
    await injected.request(SID)
    expect(b.ctx.sessionLogDownload.store.getSnapshot().bySession[SID]?.status).toBe('error')
    injected.dismiss(SID)
    expect(b.ctx.sessionLogDownload.store.getSnapshot().bySession[SID]?.open).toBe(false)

    await b.fiber.dispose()
    expect(b.slots.entries('conversation.session.header.utilities')).toHaveLength(0)
  })

  it('downloads only for an export execution acknowledged by this browser client', async () => {
    const fetcher = vi.fn(async () => new Response('', { status: 500 }))
    vi.stubGlobal('fetch', fetcher)
    const first = await bench()
    const second = await bench()
    const hasExportRequest = () => fetcher.mock.calls.some(call =>
      String((call as unknown[])[0]).includes('/api/session.export'))

    first.ctx.emit('command/executed', SID, 'plan', { kind: 'success' })
    expect(hasExportRequest()).toBe(false)
    first.ctx.emit('command/executed', SID, 'export', { kind: 'error', text: 'bad path' })
    expect(hasExportRequest()).toBe(false)
    first.ctx.emit('command/executed', SID, 'export', { kind: 'success' })
    await vi.waitFor(() => {
      expect(hasExportRequest()).toBe(true)
      expect(first.ctx.sessionLogDownload.store.getSnapshot().bySession[SID]?.status).toBe('error')
    })
    expect(second.ctx.sessionLogDownload.store.getSnapshot().bySession[SID]).toBeUndefined()

    await first.fiber.dispose()
    await second.fiber.dispose()
  })

  it('re-registers after the declaring Header slot collapses and returns', async () => {
    const b = await bench()
    b.declaration()
    expect(b.slots.entries('conversation.session.header.utilities')).toHaveLength(0)
    const redeclare = declare(b.slots)
    await Promise.resolve()
    expect(b.slots.entries('conversation.session.header.utilities')
      .find(candidate => candidate.options?.id === 'session-log-download')?.component)
      .toBe(SessionLogDownloadHeaderAction)
    redeclare()
    await b.fiber.dispose()
  })
})
