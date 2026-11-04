import { useEffect, useState } from 'react'
import { api, type Options, type Segment } from './api'
import { CampaignList } from './CampaignList'
import { LaunchForm } from './LaunchForm'
import { SegmentBuilder } from './SegmentBuilder'
import { SegmentList } from './SegmentList'

// Which screen is showing. Some screens also hold the segment they are about.
type View =
  | { name: 'list' }
  | { name: 'builder'; segment?: Segment }
  | { name: 'launch'; segment: Segment }
  | { name: 'campaigns' }

export default function App() {
  const [view, setView] = useState<View>({ name: 'list' })
  const [options, setOptions] = useState<Options | null>(null)
  const [optionsError, setOptionsError] = useState(false)

  // Load the rule allow-lists once, when the page first opens.
  useEffect(() => {
    api.options().then(setOptions).catch(() => setOptionsError(true))
  }, [])

  function tab(active: boolean) {
    return active ? 'tab active' : 'tab'
  }

  return (
    <div className="app">
      <header>
        <h1>Guest Segment Builder</h1>
        <nav>
          <button className={tab(view.name === 'list')} onClick={() => setView({ name: 'list' })}>
            Saved segments
          </button>
          <button
            className={tab(view.name === 'builder' && !view.segment)}
            onClick={() => setView({ name: 'builder' })}
          >
            New segment
          </button>
          <button className={tab(view.name === 'campaigns')} onClick={() => setView({ name: 'campaigns' })}>
            Campaigns
          </button>
        </nav>
      </header>

      <main>
        {optionsError && <p className="errors">Could not reach the server. Is Rails running?</p>}
        {!optionsError && !options && <p className="muted">Loading…</p>}

        {options && view.name === 'list' && (
          <SegmentList
            onEdit={(segment) => setView({ name: 'builder', segment })}
            onLaunch={(segment) => setView({ name: 'launch', segment })}
            onNew={() => setView({ name: 'builder' })}
          />
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

        {options && view.name === 'launch' && (
          <LaunchForm
            segment={view.segment}
            onLaunched={() => setView({ name: 'campaigns' })}
            onCancel={() => setView({ name: 'list' })}
          />
        )}

        {options && view.name === 'campaigns' && <CampaignList />}
      </main>
    </div>
  )
}
