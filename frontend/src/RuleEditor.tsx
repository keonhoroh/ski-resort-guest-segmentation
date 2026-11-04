import type { AttributeRule, AttributeValue, EventCountRule, LastEventRule, Options, Rule } from './api'
import { defaultRule } from './defaultRule'
import { countLabel, label, valueLabel } from './labels'

type Props = {
  rule: Rule
  options: Options
  onChange: (rule: Rule) => void
}

// Turns a number box's text into a number, or null when it is empty.
function toNumber(text: string): number | null {
  return text === '' ? null : Number(text)
}

export function RuleEditor({ rule, options, onChange }: Props) {
  return (
    <div className="rule-fields">
      <select
        value={rule.type}
        onChange={(e) => onChange(defaultRule(e.target.value as Rule['type'], options))}
        aria-label="Rule type"
      >
        {(['attribute', 'event_count', 'last_event'] as const).map((type) => (
          <option key={type} value={type}>{label(type)}</option>
        ))}
      </select>

      {rule.type === 'attribute' && <AttributeFields rule={rule} options={options} onChange={onChange} />}
      {rule.type === 'event_count' && <EventCountFields rule={rule} options={options} onChange={onChange} />}
      {rule.type === 'last_event' && <LastEventFields rule={rule} options={options} onChange={onChange} />}
    </div>
  )
}

type FieldProps<R> = { rule: R; options: Options; onChange: (rule: Rule) => void }

function AttributeFields({ rule, options, onChange }: FieldProps<AttributeRule>) {
  const allowed = options.attributes[rule.field]
  const selected: AttributeValue[] = Array.isArray(rule.value) ? rule.value : [rule.value]

  function changeOperator(operator: string) {
    // "is any of" holds a list; "is" and "is not" hold one value.
    const value = operator === 'in' ? selected : selected[0] ?? allowed[0]
    onChange({ ...rule, operator, value })
  }

  function toggle(value: AttributeValue) {
    const next = selected.includes(value) ? selected.filter((v) => v !== value) : [...selected, value]
    onChange({ ...rule, value: next })
  }

  return (
    <>
      <select
        value={rule.field}
        onChange={(e) => {
          const field = e.target.value
          const first = options.attributes[field][0]
          onChange({ ...rule, field, value: rule.operator === 'in' ? [first] : first })
        }}
        aria-label="Field"
      >
        {Object.keys(options.attributes).map((field) => (
          <option key={field} value={field}>{label(field)}</option>
        ))}
      </select>

      <select value={rule.operator} onChange={(e) => changeOperator(e.target.value)} aria-label="Operator">
        {options.attribute_operators.map((op) => (
          <option key={op} value={op}>{label(op)}</option>
        ))}
      </select>

      {rule.operator === 'in' ? (
        <span className="checkboxes">
          {allowed.map((value) => (
            <label key={String(value)}>
              <input type="checkbox" checked={selected.includes(value)} onChange={() => toggle(value)} />
              {valueLabel(value)}
            </label>
          ))}
        </span>
      ) : (
        // Option values are list positions, so true/false work as well as text.
        <select
          value={allowed.indexOf(selected[0])}
          onChange={(e) => onChange({ ...rule, value: allowed[Number(e.target.value)] })}
          aria-label="Value"
        >
          {allowed.map((value, i) => (
            <option key={String(value)} value={i}>{valueLabel(value)}</option>
          ))}
        </select>
      )}
    </>
  )
}

function EventCountFields({ rule, options, onChange }: FieldProps<EventCountRule>) {
  return (
    <>
      <select value={rule.operator} onChange={(e) => onChange({ ...rule, operator: e.target.value })} aria-label="Operator">
        {options.count_operators.map((op) => (
          <option key={op} value={op}>{countLabel(op)}</option>
        ))}
      </select>

      <input
        type="number"
        min={0}
        value={rule.value ?? ''}
        onChange={(e) => onChange({ ...rule, value: toNumber(e.target.value) })}
        aria-label="Count"
        className="number"
      />

      {rule.event === 'lift_scan' && (
        <select
          value={rule.difficulty ?? ''}
          onChange={(e) => onChange({ ...rule, difficulty: e.target.value || undefined })}
          aria-label="Difficulty"
        >
          <option value="">any</option>
          {options.difficulties.map((d) => (
            <option key={d} value={d}>{d}</option>
          ))}
        </select>
      )}

      <select
        value={rule.event}
        onChange={(e) => {
          const event = e.target.value
          // Only lift scans have a run difficulty.
          onChange({ ...rule, event, difficulty: event === 'lift_scan' ? rule.difficulty : undefined })
        }}
        aria-label="Event"
      >
        {options.event_types.map((event) => (
          <option key={event} value={event}>{label(event)}</option>
        ))}
      </select>

      <span>in the last</span>
      <input
        type="number"
        min={1}
        placeholder="all"
        value={rule.window_days ?? ''}
        onChange={(e) => onChange({ ...rule, window_days: toNumber(e.target.value) ?? undefined })}
        aria-label="Window in days"
        className="number"
      />
      <span>days</span>
    </>
  )
}

function LastEventFields({ rule, options, onChange }: FieldProps<LastEventRule>) {
  return (
    <>
      <select value={rule.operator} onChange={(e) => onChange({ ...rule, operator: e.target.value })} aria-label="Operator">
        {options.last_event_operators.map((op) => (
          <option key={op} value={op}>{label(op)}</option>
        ))}
      </select>
      <input
        type="number"
        min={1}
        value={rule.days ?? ''}
        onChange={(e) => onChange({ ...rule, days: toNumber(e.target.value) })}
        aria-label="Days"
        className="number"
      />
      <span>{rule.operator === 'older_than' ? 'days ago' : 'days'}</span>
    </>
  )
}
