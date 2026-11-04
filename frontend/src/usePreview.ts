import { useEffect, useState } from 'react'
import { api, ApiError, type Definition, type Preview } from './api'

export type PreviewResult =
  | ({ kind: 'ok' } & Preview)
  | { kind: 'invalid'; errors: string[] }
  | { kind: 'error'; message: string }

const DEBOUNCE_MS = 300

// Asks the API how many guests match `rules`, waiting until the rules have
// stopped changing for 300 ms. If the rules change while a request is still
// running, that request is cancelled so an old answer never replaces a new one.
export function usePreview(rules: Definition) {
  // Comparing the rules as text means "only re-run when the rules really changed".
  const rulesKey = JSON.stringify(rules)

  // The latest answer, and which rules it was for.
  const [latest, setLatest] = useState<{ rulesKey: string; result: PreviewResult } | null>(null)

  useEffect(() => {
    const controller = new AbortController()
    const finish = (result: PreviewResult) => setLatest({ rulesKey, result })

    const timer = setTimeout(() => {
      api
        .preview(JSON.parse(rulesKey), controller.signal)
        .then((preview) => finish({ kind: 'ok', ...preview }))
        .catch((error) => {
          if (controller.signal.aborted) return
          if (error instanceof ApiError && error.status === 422) {
            finish({ kind: 'invalid', errors: error.errors })
          } else {
            finish({ kind: 'error', message: error instanceof ApiError ? error.message : 'Could not reach the server.' })
          }
        })
    }, DEBOUNCE_MS)

    // Runs when the rules change again (or the page closes): stop the timer
    // and cancel any request still in flight.
    return () => {
      clearTimeout(timer)
      controller.abort()
    }
  }, [rulesKey])

  return {
    result: latest?.result ?? null,
    // Still loading if we have no answer yet for the current rules.
    loading: latest?.rulesKey !== rulesKey,
  }
}
