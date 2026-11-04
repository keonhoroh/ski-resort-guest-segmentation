import type { Options, Rule } from './api'

// A fresh rule of each type, used when a rule is added or its type changes.
export function defaultRule(type: Rule['type'], options: Options): Rule {
  switch (type) {
    case 'attribute':
      return { type, field: 'pass_type', operator: 'eq', value: options.attributes.pass_type[0] }
    case 'event_count':
      return { type, event: 'lift_scan', operator: 'gte', value: 10, window_days: 30 }
    case 'last_event':
      return { type, operator: 'older_than', days: 30 }
  }
}
