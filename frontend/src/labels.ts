// Human-friendly names for the values the API uses.

const LABELS: Record<string, string> = {
  // rule types
  attribute: 'Guest detail',
  event_count: 'Activity count',
  last_event: 'Last visit',
  // attribute fields
  pass_type: 'Pass type',
  skill_level: 'Skill level',
  home_region: 'Home region',
  email_opt_in: 'Email opt-in',
  // attribute operators
  eq: 'is',
  neq: 'is not',
  in: 'is any of',
  // events
  lift_scan: 'lift scans',
  lesson: 'lessons',
  rental: 'rentals',
  // count operators
  gt: 'more than',
  gte: 'at least',
  lt: 'fewer than',
  lte: 'at most',
  // last_event operators
  older_than: 'was more than',
  within: 'was within the last',
  // match
  all: 'all',
  any: 'any',
}

// Count operators read differently from attribute ones ("exactly 5" vs "is season").
const COUNT_LABELS: Record<string, string> = { eq: 'exactly', neq: 'not exactly' }

export function label(value: string): string {
  return LABELS[value] ?? value.replaceAll('_', ' ')
}

export function countLabel(operator: string): string {
  return COUNT_LABELS[operator] ?? label(operator)
}

export function valueLabel(value: string | boolean): string {
  if (value === true) return 'yes'
  if (value === false) return 'no'
  return label(value)
}
