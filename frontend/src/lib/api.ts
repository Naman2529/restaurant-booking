// Thin client for the Go API. Every error the server sends is JSON
// {"message": "..."} with a meaningful status, written for people, so the
// UI shows err.message as-is.

export class ApiError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  let res: Response
  try {
    res = await fetch(path, {
      method,
      headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
      credentials: 'same-origin',
    })
  } catch {
    throw new ApiError(0, 'Could not reach the server. Is it running?')
  }

  const text = await res.text()
  const data = text ? safeJson(text) : null
  if (!res.ok) {
    const fromServer =
      data !== null && typeof data === 'object' && 'message' in data ? String((data as { message: unknown }).message) : ''
    const message =
      fromServer ||
      (res.status === 502 || res.status === 504
        ? 'Could not reach the server. Is it running?'
        : `Something went wrong (${res.status})`)
    throw new ApiError(res.status, capitalise(message))
  }
  return data as T
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text)
  } catch {
    return null
  }
}

function capitalise(s: string) {
  return s.charAt(0).toUpperCase() + s.slice(1)
}

export const api = {
  get: <T>(path: string) => request<T>('GET', path),
  post: <T>(path: string, body?: unknown) => request<T>('POST', path, body ?? {}),
}

/* ---------- Types (match the Go handlers) ---------- */

export interface Restaurant {
  restaurant_id: number
  name: string
  cuisine: string | null
  tagline: string | null
  photo: string | null
  address: string | null
  phone: string | null
}

export interface Slot {
  start: string // "2026-10-30T19:00", IST wall clock
  free_tables: number
}

export interface PlanFeature {
  kind: string
  label: string
  x: number
  y: number
  width: number
  height: number
}

export interface PlanTable {
  table_number: number
  capacity: number
  x: number
  y: number
}

export interface FloorPlan {
  restaurant_id: number
  name: string
  width: number
  height: number
  features: PlanFeature[]
  tables: PlanTable[]
}

export interface TableAvailability {
  table_number: number
  capacity: number
  fits_party: boolean
  is_free: boolean
}

export interface Reservation {
  reservation_id: number
  restaurant_id: number
  restaurant_name: string
  table_number: number
  party_size: number
  starts_at: string
  ends_at: string
  status: 'booked' | 'seated' | 'completed' | 'no_show' | 'cancelled'
  can_cancel: boolean
}

export interface CustomerMe {
  kind: 'customer'
  id: number
  full_name: string
  email: string
  phone: string | null
  email_verified: boolean
}

export type SeatColour = 'green' | 'transparent' | 'gray' | 'red' | 'orange'

export interface SeatMapTable {
  table_number: number
  capacity: number
  colour: SeatColour
  reservation_id: number | null
  starts_at: string | null
  ends_at: string | null
}

export interface StaffReservation {
  reservation_id: number
  table_number: number
  capacity: number
  party_size: number
  customer_name: string
  customer_phone: string | null
  starts_at: string
  ends_at: string
  status: Reservation['status']
}

/** Same rule as util.allowed_capacities: the snug size, or one size up; halls 11+. */
export function allowedCapacities(party: number): number[] {
  if (party <= 2) return [2, 4]
  if (party <= 4) return [4, 6]
  if (party <= 6) return [6, 8]
  if (party <= 8) return [8, 10]
  if (party <= 10) return [10]
  if (party <= 20) return [20]
  return []
}

export interface StaffMe {
  kind: 'staff'
  id: number
  full_name: string
  email: string
  role: 'receptionist' | 'waiter'
  restaurant_id: number
  restaurant_name: string
}
