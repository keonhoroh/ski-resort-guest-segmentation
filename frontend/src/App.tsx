import { useEffect, useState } from 'react'
import { api, type Options, type Segment } from './api'
import { SegmentBuilder } from './SegmentBuilder'
import { SegmentList } from './SegmentList'

// Which screen is showing. When editing, it also holds the segment being edited.
type View = { name: 'list' } | { name: 'builder'; segment?: Segment }

export default function App() {
  const [view, setView] = useState<View>({ name: 'list' })
  const [options, setOptions] = useState<Options | null>(null)
  const [optionsError, setOptionsError] = useState(false)

  // Load the rule allow-lists once, when the page first opens.
  useEffect(() => {
    api.options().then(setOptions).catch(() => setOptionsError(true))
  }, [])

  return (
    <div className="app">
      <header>
        <h1>Liftline</h1>
        <nav>
          <button className={view.name === 'list' ? 'tab active' : 'tab'} onClick={() => setView({ name: 'list' })}>
            Saved segments
          </button>
          <button
            className={view.name === 'builder' && !view.segment ? 'tab active' : 'tab'}
            onClick={() => setView({ name: 'builder' })}
          >
            New segment
          </button>
        </nav>
      </header>

      <main>
        {optionsError && <p className="errors">Could not reach the server. Is Rails running?</p>}
        {!optionsError && !options && <p className="muted">Loading…</p>}

        {options && view.name === 'list' && (
          <SegmentList onEdit={(segment) => setView({ name: 'builder', segment })} onNew={() => setView({ name: 'builder' })} />
        )}

        {options && view.name === 'builder' && (
          <SegmentBuilder
            // A new key makes React start a fresh form when switching segments.
            key={view.segment?.id ?? 'new'}
            options={options}
            segment={view.segment}
            onSaved={() => setView({ name: 'list' })}
          />
        )}
      </main>
    </div>
  )
}
