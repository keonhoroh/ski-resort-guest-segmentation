import { useEffect, useState } from 'react'
import { api, type Segment } from './api'

type Props = {
  onEdit: (segment: Segment) => void
  onLaunch: (segment: Segment) => void
  onNew: () => void
}

export function SegmentList({ onEdit, onLaunch, onNew }: Props) {
  const [segments, setSegments] = useState<Segment[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [confirmingId, setConfirmingId] = useState<number | null>(null)

  function load() {
    api
      .listSegments()
      .then((list) => {
        setSegments(list)
        setError(null)
      })
      .catch(() => setError('Could not load segments.'))
  }

  useEffect(load, [])

  async function remove(id: number) {
    setConfirmingId(null)
    try {
      await api.deleteSegment(id)
      load()
    } catch {
      setError('Could not delete that segment.')
    }
  }

  if (error) return <p className="errors">{error}</p>
  if (segments === null) return <p className="muted">Loading…</p>

  if (segments.length === 0) {
    return (
      <div className="empty">
        <p>No saved segments yet.</p>
        <button className="primary" onClick={onNew}>Build your first segment</button>
      </div>
    )
  }

  return (
    <table className="segments">
      <thead>
        <tr>
          <th>Name</th>
          <th className="right">Guests</th>
          <th>Last saved</th>
          <th />
        </tr>
      </thead>
      <tbody>
        {segments.map((segment) => (
          <tr key={segment.id}>
            <td>{segment.name}</td>
            <td className="right">{segment.last_count?.toLocaleString() ?? '—'}</td>
            <td>{new Date(segment.updated_at).toLocaleString()}</td>
            <td className="actions">
              {confirmingId === segment.id ? (
                <>
                  Delete?{' '}
                  <button className="link danger" onClick={() => remove(segment.id)}>Yes</button>
                  <button className="link" onClick={() => setConfirmingId(null)}>No</button>
                </>
              ) : (
                <>
                  <button className="link" onClick={() => onLaunch(segment)}>Launch</button>
                  <button className="link" onClick={() => onEdit(segment)}>Edit</button>
                  <button className="link" onClick={() => setConfirmingId(segment.id)}>Delete</button>
                </>
              )}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}
