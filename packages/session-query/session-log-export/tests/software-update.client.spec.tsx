// @vitest-environment jsdom

import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { SoftwareUpdateSettingsRow } from '../src/client/SoftwareUpdateSettingsRow.tsx'

afterEach(() => {
  cleanup()
  delete window.webkit
  vi.unstubAllGlobals()
})

describe('SoftwareUpdateSettingsRow', () => {
  it('shows the current version and requests a native update check', () => {
    const postMessage = vi.fn()
    vi.stubGlobal('__DEEPSEEK_HARNESS_DESKTOP__', { version: '0.1.0' })
    Object.defineProperty(window, 'webkit', {
      configurable: true,
      value: { messageHandlers: { desktopHarness: { postMessage } } },
    })
    render(<SoftwareUpdateSettingsRow />)
    expect(screen.getByText('当前版本 0.1.0')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: /检查更新/ }))
    expect(postMessage).toHaveBeenCalledWith({ action: 'check-update' })
  })

  it('reflects native checking and download states', () => {
    vi.stubGlobal('__DEEPSEEK_HARNESS_DESKTOP__', { version: '0.1.0' })
    render(<SoftwareUpdateSettingsRow />)
    act(() => {
      window.dispatchEvent(new CustomEvent('deepseek-harness-update-state', {
        detail: { status: 'checking', message: '正在检查更新…' },
      }))
    })
    expect(screen.getByRole<HTMLButtonElement>('button', { name: /检查中/ }).disabled).toBe(true)
    expect(screen.getByText('正在检查更新…')).toBeTruthy()
  })
})
