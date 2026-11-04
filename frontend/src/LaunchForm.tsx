import { useState } from 'react'
import { api, ApiError, type Segment } from './api'

type Props = {
  segment: Segment
  onLaunched: () => void
  onCancel: () => void
}

// Name and message for a new campaign, sent to one saved segment.
export function LaunchForm({ segment, onLaunched, onCancel }: Props) {
  const [name, setName] = useState('')
  const [message, setMessage] = useState('')
  const [launching, setLaunching] = useState(false)
  const [errors, setErrors] = useState<string[]>([])

  async function launch(event: React.FormEvent) {
    event.preventDefault()
    setLaunching(true)
    setErrors([])
    try {
      await api.launchCampaign(segment.id, name, message)
      onLaunched()
    } catch (error) {
      setErrors(error instanceof ApiError ? error.errors : ['Could not reach the server.'])
      setLaunching(false)
    }
  }

  return (
    <form className="launch" onSubmit={launch}>
      <h2>Launch a campaign</h2>
      <p className="muted">
        To <strong>{segment.name}</strong>: only guests who opted in to email will get it. Nothing is really sent.
      </p>

      <label>
        Campaign name
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Spring pass sale" />
      </label>

      <label>
        Message
        <textarea value={message} onChange={(e) => setMessage(e.target.value)} rows={4} />
      </label>

      {errors.length > 0 && (
        <ul className="errors">
          {errors.map((e) => <li key={e}>{e}</li>)}
        </ul>
      )}

      <div className="buttons">
        <button type="submit" className="primary" disabled={launching}>
          {launching ? 'Launching…' : 'Launch'}
        </button>
        <button type="button" onClick={onCancel}>Cancel</button>
      </div>
    </form>
  )
}
