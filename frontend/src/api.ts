// Types that mirror the JSON the Rails API sends and receives,
// plus one small function per API address.

export type AttributeValue = string | boolean

export type AttributeRule = {
  type: 'attribute'
  field: string
  operator: string
  value: AttributeValue | AttributeValue[]
}

export type EventCountRule = {
  type: 'event_count'
  event: string
  difficulty?: string
  operator: string
  value: number | null
  window_days?: number | null
}

export type LastEventRule = {
  type: 'last_event'
  operator: string
  days: number | null
}

export type Rule = AttributeRule | EventCountRule | LastEventRule

export type Definition = {
  match: string
  rules: Rule[]
}

export type Segment = {
  id: number
  name: string
  rules: Definition
  last_count: number | null
  created_at: string
  updated_at: string
}

export type Options = {
  matches: string[]
  attributes: Record<string, AttributeValue[]>
  attribute_operators: string[]
  event_types: string[]
  difficulties: string[]
  count_operators: string[]
  last_event_operators: string[]
  max_rules: number
}

export type CampaignStatus = 'queued' | 'running' | 'completed' | 'failed'

export type Campaign = {
  id: number
  segment_id: number
  segment_name: string
  name: string
  message: string
  status: CampaignStatus
  audience_count: number | null
  sent_count: number
  started_at: string | null
  finished_at: string | null
  created_at: string
}

export type Preview = {
  count: number
  query_ms: number
}

// Thrown when the API answers with an error status.
export class ApiError extends Error {
  status: number
  errors: string[]

  constructor(status: number, errors: string[]) {
    super(errors.join('; '))
    this.status = status
    this.errors = errors
  }
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(`/api${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json' },
  })
  if (response.status === 204) return undefined as T

  const body = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new ApiError(response.status, body.errors ?? [body.error ?? `Request failed (${response.status})`])
  }
  return body as T
}

export const api = {
  options: () => request<Options>('/segments/options'),
  listSegments: () => request<Segment[]>('/segments'),
  createSegment: (name: string, rules: Definition) =>
    request<Segment>('/segments', { method: 'POST', body: JSON.stringify({ name, rules }) }),
  updateSegment: (id: number, name: string, rules: Definition) =>
    request<Segment>(`/segments/${id}`, { method: 'PATCH', body: JSON.stringify({ name, rules }) }),
  deleteSegment: (id: number) => request<void>(`/segments/${id}`, { method: 'DELETE' }),
  // `signal` lets the caller cancel the request if the rules change again.
  preview: (rules: Definition, signal: AbortSignal) =>
    request<Preview>('/segments/preview', { method: 'POST', body: JSON.stringify({ rules }), signal }),
  launchCampaign: (segmentId: number, name: string, message: string) =>
    request<Campaign>(`/segments/${segmentId}/campaigns`, { method: 'POST', body: JSON.stringify({ name, message }) }),
  listCampaigns: () => request<Campaign[]>('/campaigns'),
}
