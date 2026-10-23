import { useMemo, useState } from 'react'
import { useOutletContext } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowRightLeft, BrushCleaning, Clock, Phone, UserCheck, UserX, Users, X } from 'lucide-react'
import { toast } from 'sonner'
import {
  allowedCapacities,
  api,
  type FloorPlan as Plan,
  type PlanTable,
  type SeatColour,
  type SeatMapTable,
  type StaffMe,
  type StaffReservation,
} from '../lib/api'
import { friendlyTime, greeting, longDate, timeOf, todayIST } from '../lib/time'
import FloorPlan from '../components/FloorPlan'
import { ticketNumber } from '../pages/Confirmed'

const COLOUR_INFO: Record<SeatColour, { name: string; hint: string }> = {
  green: { name: 'Free', hint: 'Nobody is due for at least 30 minutes.' },
  transparent: { name: 'Arriving soon', hint: 'A booking starts within 30 minutes. Don’t give it away.' },
  gray: { name: 'Waiting', hint: 'The booking has started but the guests aren’t here. Mark a no-show after 15 minutes.' },
  red: { name: 'Seated', hint: 'Guests are inside their sitting.' },
  orange: { name: 'Over time', hint: 'The sitting has ended. Free the table or extend it.' },
}
const ORDER: SeatColour[] = ['green', 'transparent', 'gray', 'red', 'orange']

const STATUS_WORDS: Record<StaffReservation['status'], string> = {
  booked: 'Booked',
  seated: 'Seated',
  completed: 'Done',
  no_show: 'No-show',
  cancelled: 'Cancelled',
}

type Filter = 'all' | 'booked' | 'seated' | 'done'

interface Reassigning {
  reservationId: number
  party: number
  from: number
}

export default function Dashboard() {
  const me = useOutletContext<StaffMe>()
  const qc = useQueryClient()
  const isReceptionist = me.role === 'receptionist'

  const [selected, setSelected] = useState<number | null>(null)
  const [focusId, setFocusId] = useState<number | null>(null)
  const [moving, setMoving] = useState<Reassigning | null>(null)
  const [filter, setFilter] = useState<Filter>('all')

  const plan = useQuery({
    queryKey: ['floor-plan', String(me.restaurant_id)],
    queryFn: () => api.get<Plan>(`/restaurants/${me.restaurant_id}/floor-plan`),
  })
  // Colours depend on the clock, so they're refreshed even when nothing is clicked.
  const seat = useQuery({
    queryKey: ['staff', 'seat-map'],
    queryFn: () => api.get<SeatMapTable[]>('/staff/seat-map'),
    refetchInterval: 30_000,
  })
  const day = useQuery({
    queryKey: ['staff', 'reservations'],
    queryFn: () => api.get<StaffReservation[]>('/staff/reservations'),
    refetchInterval: 30_000,
  })

  const seatBy = useMemo(() => new Map((seat.data ?? []).map((s) => [s.table_number, s])), [seat.data])
  const resBy = useMemo(() => new Map((day.data ?? []).map((r) => [r.reservation_id, r])), [day.data])

  const counts = useMemo(() => {
    const c: Record<SeatColour, number> = { green: 0, transparent: 0, gray: 0, red: 0, orange: 0 }
    for (const s of seat.data ?? []) c[s.colour]++
    return c
  }, [seat.data])

  const act = useMutation({
    mutationFn: ({ path, body }: { path: string; body?: unknown; done?: string }) => api.post<{ message?: string }>(path, body),
    onSuccess: (res, vars) => {
      toast.success(vars.done ?? res.message ?? 'Done')
      qc.invalidateQueries({ queryKey: ['staff'] })
    },
    onError: (e) => {
      toast.error(e.message)
      qc.invalidateQueries({ queryKey: ['staff'] })
    },
  })

  function selectTable(t: PlanTable) {
    if (moving) {
      if (t.table_number === moving.from) return
      act.mutate(
        {
          path: `/staff/reservations/${moving.reservationId}/reassign`,
          body: { table_number: t.table_number },
          done: `Booking ${ticketNumber(moving.reservationId)} moved to table ${t.table_number}`,
        },
        {
          onSuccess: () => {
            setMoving(null)
            setSelected(t.table_number)
            setFocusId(moving.reservationId)
          },
        },
      )
      return
    }
    if (selected === t.table_number) {
      setSelected(null)
      setFocusId(null)
    } else {
      setSelected(t.table_number)
      setFocusId(null)
    }
  }

  const moveTargets = useMemo(() => {
    if (!moving || !plan.data) return undefined
    const ok = allowedCapacities(moving.party)
    return new Set(plan.data.tables.filter((t) => t.table_number !== moving.from && ok.includes(t.capacity)).map((t) => t.table_number))
  }, [moving, plan.data])

  const tableSeat = selected !== null ? seatBy.get(selected) : undefined
  const tableBookings = (day.data ?? []).filter((r) => r.table_number === selected)
  // Which booking the panel acts on: the one tapped in a list, else the one
  // the seat map is showing, else this table's next active booking today.
  const focus: StaffReservation | undefined =
    (focusId !== null ? resBy.get(focusId) : undefined) ??
    (tableSeat?.reservation_id ? resBy.get(tableSeat.reservation_id) : undefined) ??
    tableBookings.find((r) => r.status === 'booked' || r.status === 'seated')
  const focusIsLater = !!focus && focus.reservation_id !== tableSeat?.reservation_id && focusId === null

  const list = (day.data ?? []).filter((r) =>
    filter === 'all'
      ? true
      : filter === 'booked'
        ? r.status === 'booked'
        : filter === 'seated'
          ? r.status === 'seated'
          : r.status === 'completed' || r.status === 'no_show' || r.status === 'cancelled',
  )

  return (
    <main className="dash">
      <section className="dash-hello">
        <div>
          <h1>
            {greeting()}, <em>{me.full_name.split(' ')[0]}</em>
          </h1>
          <p className="muted">
            {longDate(todayIST())} · {day.data ? `${day.data.filter((r) => r.status === 'booked' || r.status === 'seated').length} bookings still to look after today` : 'loading today…'}
          </p>
        </div>
        <ul className="counts" aria-label="Tables right now">
          {ORDER.map((c) => (
            <li key={c} className="count" title={COLOUR_INFO[c].hint}>
              <i className={`sw-staff sw-${c}`} aria-hidden="true" />
              <span className="count-n">{seat.data ? counts[c] : '–'}</span>
              <span className="count-name">{COLOUR_INFO[c].name}</span>
            </li>
          ))}
        </ul>
      </section>

      <div className="dash-grid">
        <section className="dash-plan" aria-label="Floor plan">
          {moving && (
            <div className="move-banner" role="status">
              <ArrowRightLeft size={18} aria-hidden="true" />
              <span>
                Moving booking {ticketNumber(moving.reservationId)} (party of {moving.party}). Tap a highlighted table.
              </span>
              <button className="btn btn-small btn-quiet" onClick={() => setMoving(null)}>
                Cancel
              </button>
            </div>
          )}
          {plan.isLoading || seat.isLoading ? (
            <div className="skeleton" style={{ aspectRatio: '1000 / 640' }} />
          ) : plan.data ? (
            <div className="plan-scroll">
              <FloorPlan
                plan={plan.data}
                toneOf={(t) => seatBy.get(t.table_number)?.colour ?? 'green'}
                isSelectable={(t) => (moving ? !!moveTargets?.has(t.table_number) : true)}
                selected={selected}
                onSelect={selectTable}
                selectionStyle="ring"
                highlight={moveTargets}
                describe={(t) => COLOUR_INFO[seatBy.get(t.table_number)?.colour ?? 'green'].name}
              />
            </div>
          ) : (
            <div className="notice danger">{(plan.error as Error)?.message}</div>
          )}
          <p className="plan-foot muted">Colours update on their own every 30 seconds. Tap a table to see its bookings.</p>
        </section>

        <aside className="dash-side">
          {selected !== null ? (
            <div className="panel" key={selected}>
              <div className="panel-head">
                <div>
                  <h2>Table {selected}</h2>
                  <p className="muted">
                    {tableSeat?.capacity === 20 ? 'Private hall, up to 20' : `${tableSeat?.capacity} seats`}
                  </p>
                </div>
                <button className="icon-btn" aria-label="Close" onClick={() => setSelected(null)}>
                  <X size={20} aria-hidden="true" />
                </button>
              </div>

              {tableSeat && (
                <p className={`state state-${tableSeat.colour}`}>
                  <i className={`sw-staff sw-${tableSeat.colour}`} aria-hidden="true" />
                  <span>
                    <strong>{COLOUR_INFO[tableSeat.colour].name}.</strong> {COLOUR_INFO[tableSeat.colour].hint}
                  </span>
                </p>
              )}

              {focus ? (
                <div className="booking-card">
                  {focusIsLater && <p className="bc-later hand">next booking here</p>}
                  <p className="bc-top">
                    <span className="bc-no">No. {ticketNumber(focus.reservation_id)}</span>
                    <span className={`pill pill-${focus.status}`}>{STATUS_WORDS[focus.status]}</span>
                  </p>
                  <p className="bc-name">{focus.customer_name}</p>
                  <ul className="bc-facts">
                    <li>
                      <Clock size={16} aria-hidden="true" /> {friendlyTime(timeOf(focus.starts_at))} – {friendlyTime(timeOf(focus.ends_at))}
                    </li>
                    <li>
                      <Users size={16} aria-hidden="true" /> party of {focus.party_size}
                    </li>
                    {focus.customer_phone && (
                      <li>
                        <Phone size={16} aria-hidden="true" /> <a href={`tel:${focus.customer_phone}`}>{focus.customer_phone}</a>
                      </li>
                    )}
                  </ul>

                  <div className="bc-actions">
                    {focus.status === 'booked' && (
                      <>
                        {isReceptionist && (
                          <button
                            className="btn"
                            disabled={act.isPending}
                            onClick={() => act.mutate({ path: `/staff/reservations/${focus.reservation_id}/seat`, done: `${focus.customer_name.split(' ')[0]}’s party is seated` })}
                          >
                            <UserCheck size={18} aria-hidden="true" /> Seat guests
                          </button>
                        )}
                        <button
                          className="btn btn-ghost"
                          disabled={act.isPending}
                          onClick={() => act.mutate({ path: `/staff/reservations/${focus.reservation_id}/no-show`, done: 'Marked as no-show, table freed' })}
                        >
                          <UserX size={18} aria-hidden="true" /> No-show
                        </button>
                        {isReceptionist && (
                          <button
                            className="btn btn-ghost"
                            disabled={act.isPending}
                            onClick={() => setMoving({ reservationId: focus.reservation_id, party: focus.party_size, from: focus.table_number })}
                          >
                            <ArrowRightLeft size={18} aria-hidden="true" /> Move table
                          </button>
                        )}
                      </>
                    )}
                    {focus.status === 'seated' && (
                      <>
                        <button
                          className="btn"
                          disabled={act.isPending}
                          onClick={() => act.mutate({ path: `/staff/reservations/${focus.reservation_id}/complete`, done: `Table ${focus.table_number} is free again` })}
                        >
                          <BrushCleaning size={18} aria-hidden="true" /> Free table
                        </button>
                        <div className="extend" role="group" aria-label="Extend the sitting">
                          <span className="muted">Extend</span>
                          {[15, 30, 60].map((m) => (
                            <button
                              key={m}
                              className="btn btn-small btn-quiet"
                              disabled={act.isPending}
                              onClick={() =>
                                act.mutate({
                                  path: `/staff/reservations/${focus.reservation_id}/extend`,
                                  body: { minutes: m },
                                  done: `Sitting extended by ${m} minutes`,
                                })
                              }
                            >
                              +{m} min
                            </button>
                          ))}
                        </div>
                      </>
                    )}
                  </div>
                  {!isReceptionist && focus.status === 'booked' && (
                    <p className="role-note muted">Seating and moving tables is for the receptionist.</p>
                  )}
                </div>
              ) : (
                <p className="muted panel-empty">Nothing booked on this table right now.</p>
              )}

              <h3 className="panel-sub">Today at this table</h3>
              {tableBookings.length === 0 ? (
                <p className="muted">No bookings today.</p>
              ) : (
                <ul className="mini-list">
                  {tableBookings.map((r) => (
                    <li key={r.reservation_id}>
                      <button className={`mini${focus?.reservation_id === r.reservation_id ? ' is-on' : ''}`} onClick={() => setFocusId(r.reservation_id)}>
                        <span className="mini-time">{friendlyTime(timeOf(r.starts_at))}</span>
                        <span className="mini-name">{r.customer_name}</span>
                        <span className={`pill pill-${r.status}`}>{STATUS_WORDS[r.status]}</span>
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          ) : (
            <div className="panel">
              <div className="panel-head">
                <h2>Today’s bookings</h2>
              </div>
              <div className="filters" role="tablist" aria-label="Filter bookings">
                {(['all', 'booked', 'seated', 'done'] as Filter[]).map((f) => (
                  <button key={f} role="tab" aria-selected={filter === f} onClick={() => setFilter(f)}>
                    {f === 'all' ? 'All' : f === 'booked' ? 'Coming' : f === 'seated' ? 'Seated' : 'Done'}
                  </button>
                ))}
              </div>
              {day.isLoading && <div className="skeleton" style={{ height: 160 }} />}
              {day.data && list.length === 0 && (
                <p className="muted panel-empty">{day.data.length === 0 ? 'No bookings today yet.' : 'Nothing in this list.'}</p>
              )}
              <ul className="mini-list">
                {list.map((r) => (
                  <li key={r.reservation_id}>
                    <button
                      className="mini"
                      onClick={() => {
                        setSelected(r.table_number)
                        setFocusId(r.reservation_id)
                      }}
                    >
                      <span className="mini-time">{friendlyTime(timeOf(r.starts_at))}</span>
                      <span className="mini-name">
                        {r.customer_name}
                        <small>
                          table {r.table_number} · {r.party_size} {r.party_size === 1 ? 'guest' : 'guests'}
                        </small>
                      </span>
                      <span className={`pill pill-${r.status}`}>{STATUS_WORDS[r.status]}</span>
                    </button>
                  </li>
                ))}
              </ul>

              <div className="sweep">
                <div>
                  <p className="sweep-title">Running late?</p>
                  <p className="muted">Mark every booking that is 15+ minutes late as a no-show and free its table.</p>
                </div>
                <button
                  className="btn btn-ghost"
                  disabled={act.isPending}
                  onClick={() =>
                    api
                      .post<{ marked: number; skipped: number }>('/staff/no-show-sweep')
                      .then((r) => {
                        toast.success(
                          r.marked === 0 ? 'Nobody is late. All good!' : `Marked ${r.marked} ${r.marked === 1 ? 'booking' : 'bookings'} as no-show`,
                        )
                        qc.invalidateQueries({ queryKey: ['staff'] })
                      })
                      .catch((e: Error) => toast.error(e.message))
                  }
                >
                  <UserX size={18} aria-hidden="true" /> Sweep no-shows
                </button>
              </div>
            </div>
          )}
        </aside>
      </div>
    </main>
  )
}
