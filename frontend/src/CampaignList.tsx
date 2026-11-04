import { useEffect, useState } from 'react'
import { api, type Campaign } from './api'

// How often to ask the server for progress while a campaign is still going.
const POLL_MS = 1000

export function CampaignList() {
  const [campaigns, setCampaigns] = useState<Campaign[] | null>(null)
  const [error, setError] = useState(false)

  useEffect(() => {
    let timer: number | undefined
    let stopped = false

    function load() {
      api
        .listCampaigns()
        .then((list) => {
          if (stopped) return
          setCampaigns(list)
          setError(false)
          // Keep checking only while something is still queued or running.
          if (list.some((c) => c.status === 'queued' || c.status === 'running')) {
            timer = window.setTimeout(load, POLL_MS)
          }
        })
        .catch(() => !stopped && setError(true))
    }

    load()
    // When this screen closes, stop checking.
    return () => {
      stopped = true
      window.clearTimeout(timer)
    }
  }, [])

  if (error) return <p className="errors">Could not load campaigns.</p>
  if (campaigns === null) return <p className="muted">Loading…</p>
  if (campaigns.length === 0) {
    return <p className="empty muted">No campaigns yet. Launch one from a saved segment.</p>
  }

  return (
    <table className="segments">
      <thead>
        <tr>
          <th>Campaign</th>
          <th>Segment</th>
          <th>Progress</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
        {campaigns.map((c) => (
          <tr key={c.id}>
            <td>
              {c.name}
              <div className="muted small">{new Date(c.created_at).toLocaleString()}</div>
            </td>
            <td>{c.segment_name}</td>
            <td className="progress-cell">
              <Progress sent={c.sent_count} total={c.audience_count} />
            </td>
            <td><span className={`status ${c.status}`}>{c.status}</span></td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

function Progress({ sent, total }: { sent: number; total: number | null }) {
  // The total is unknown until the job has counted the audience.
  const percent = total ? Math.round((sent / total) * 100) : total === 0 ? 100 : 0
  return (
    <>
      <div className="bar" role="progressbar" aria-valuenow={percent} aria-valuemin={0} aria-valuemax={100}>
        <div style={{ width: `${percent}%` }} />
      </div>
      <div className="muted small">
        {sent.toLocaleString()} of {total === null ? '…' : total.toLocaleString()} sent
      </div>
    </>
  )
}
