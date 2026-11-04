import { useState } from 'react'
import { api, ApiError, type Definition, type Options, type Rule, type Segment } from './api'
import { label } from './labels'
import { defaultRule } from './defaultRule'
import { RuleEditor } from './RuleEditor'
import { usePreview } from './usePreview'

type Props = {
  options: Options
  segment?: Segment // present when editing a saved segment
  onSaved: () => void
}

export function SegmentBuilder({ options, segment, onSaved }: Props) {
  const [name, setName] = useState(segment?.name ?? '')
  const [definition, setDefinition] = useState<Definition>(
    segment?.rules ?? { match: 'all', rules: [defaultRule('attribute', options)] },
  )
  const [saving, setSaving] = useState(false)
  const [saveErrors, setSaveErrors] = useState<string[]>([])
  const { result, loading } = usePreview(definition)

  function updateRule(index: number, rule: Rule) {
    setDefinition({ ...definition, rules: definition.rules.map((r, i) => (i === index ? rule : r)) })
  }

  function removeRule(index: number) {
    setDefinition({ ...definition, rules: definition.rules.filter((_, i) => i !== index) })
  }

  function addRule() {
    setDefinition({ ...definition, rules: [...definition.rules, defaultRule('attribute', options)] })
  }

  async function save(event: React.FormEvent) {
    event.preventDefault()
    setSaving(true)
    setSaveErrors([])
    try {
      if (segment) await api.updateSegment(segment.id, name, definition)
      else await api.createSegment(name, definition)
      onSaved()
    } catch (error) {
      setSaveErrors(error instanceof ApiError ? error.errors : ['Could not reach the server.'])
      setSaving(false)
    }
  }

  return (
    <form className="builder" onSubmit={save}>
      <h2>{segment ? 'Edit segment' : 'New segment'}</h2>

      <label className="name">
        Name
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Lapsed season pass holders" />
      </label>

      <p className="match">
        Guests who match{' '}
        <select value={definition.match} onChange={(e) => setDefinition({ ...definition, match: e.target.value })}>
          {options.matches.map((m) => (
            <option key={m} value={m}>{label(m)}</option>
          ))}
        </select>{' '}
        of these rules:
      </p>

      <ol className="rules">
        {definition.rules.map((rule, i) => (
          <li key={i}>
            <RuleEditor rule={rule} options={options} onChange={(r) => updateRule(i, r)} />
            <button type="button" className="link" onClick={() => removeRule(i)} disabled={definition.rules.length === 1}>
              Remove
            </button>
          </li>
        ))}
      </ol>

      <button type="button" onClick={addRule} disabled={definition.rules.length >= options.max_rules}>
        + Add rule
      </button>

      <PreviewPanel result={result} loading={loading} />

      {saveErrors.length > 0 && (
        <ul className="errors">
          {saveErrors.map((e) => <li key={e}>{e}</li>)}
        </ul>
      )}

      <button type="submit" className="primary" disabled={saving}>
        {saving ? 'Saving…' : 'Save segment'}
      </button>
    </form>
  )
}

function PreviewPanel({ result, loading }: ReturnType<typeof usePreview>) {
  return (
    <section className="preview" aria-live="polite">
      <div className="label">Matching guests {loading && <span className="muted">· counting…</span>}</div>

      {result === null && <div className="count muted">…</div>}

      {result?.kind === 'ok' && (
        <>
          <div className={loading ? 'count muted' : 'count'}>{result.count.toLocaleString()}</div>
          {result.count === 0 && <div className="muted">No guests match these rules.</div>}
          <div className="muted small">Query took {result.query_ms} ms</div>
        </>
      )}

      {result?.kind === 'invalid' && (
        <ul className="errors">
          {result.errors.map((e) => <li key={e}>{e}</li>)}
        </ul>
      )}

      {result?.kind === 'error' && <p className="errors">{result.message}</p>}
    </section>
  )
}
