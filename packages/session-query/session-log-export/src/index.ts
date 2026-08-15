/** Web Session-log download command and DeepSeek balance endpoint. */

import type { Context } from '@deepseek-ai/cordis'
import type { IncomingMessage, ServerResponse } from 'node:http'
import type { CommandResult } from '@deepseek-ai/dsh-commands'
import { credentialRef } from '@deepseek-ai/dsh-credentials'
import type {} from '@deepseek-ai/dsh-host-webserver'

export const name = 'session-log-download'
export const inject = ['commands']

const BALANCE_PATH = '/api/desktop.balance'
const BALANCE_URL = 'https://api.deepseek.com/user/balance'
const API_KEY = credentialRef('DEEPSEEK_API_KEY')

const REQUESTED: CommandResult = {
  kind: 'success',
  text: 'Session log download requested.',
}

/**
 * Register the Web-only `/export` command that the browser download plugin observes.
 * @param ctx - Host context carrying the human-command registry.
 */
export function apply(ctx: Context): void {
  ctx.effect(() => ctx.commands.register({
    name: 'export',
    description: 'Download this Session log as a ZIP archive',
    handler: invocation => Promise.resolve(invocation.rawInput.trim() === ''
      ? REQUESTED
      : { kind: 'error', text: 'The Web /export command does not accept a path.' }),
  }), 'session-log-download: command')
  ctx.inject(['credentials', 'webServer'], (host) => {
    host.effect(() => host.webServer.register({
      kind: 'exact',
      path: BALANCE_PATH,
      handler: async (req: IncomingMessage, res: ServerResponse) => {
        if (req.method !== 'GET') {
          res.writeHead(405, { allow: 'GET' })
          res.end()
          return
        }
        const credential = await host.credentials.resolve(API_KEY)
        if (credential === undefined) {
          res.writeHead(401, { 'content-type': 'application/json; charset=utf-8' })
          res.end(JSON.stringify({ error: 'missing-api-key' }))
          return
        }
        const upstream = await fetch(BALANCE_URL, {
          headers: {
            accept: 'application/json',
            authorization: `Bearer ${credential.value}`,
          },
          signal: AbortSignal.timeout(15_000),
        })
        const body = await upstream.text()
        res.writeHead(upstream.status, {
          'cache-control': 'no-store',
          'content-type': 'application/json; charset=utf-8',
        })
        res.end(body)
      },
    }), 'session-log-download: balance route')
  })
}
