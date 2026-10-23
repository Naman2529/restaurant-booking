import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Ticket, X } from 'lucide-react'
import { toast } from 'sonner'
import { api, type Reservation } from '../lib/api'
import { dateOf, friendlyTime, timeOf, todayIST } from '../lib/time'
import { useCustomer } from '../lib/session'
import { ticketNumber } from './Confirmed'
import './MyBookings.css'

const STATUS_WORDS: Record<Reservation['status'], string> = {
  booked: 'Confirmed',
  seated: 'Seated',
  completed: 'Completed',
  no_show: 'Missed',
  cancelled: 'Cancelled',
}

function DateBlock({ stamp }: { stamp: string }) {
  const d = new Date(`${dateOf(stamp)}T12:00:00Z`)
  return (
    <div className="date-block" aria-hidden="true">
      <span className="db-month">{d.toLocaleDateString('en-GB', { month: 'short', timeZone: 'UTC' })}</span>
      <span className="db-day">{d.getUTCDate()}</span>
      <span className="db-week">{d.toLocaleDateString('en-GB', { weekday: 'short', timeZone: 'UTC' })}</span>
    </div>
  )
}

function Row({ r }: { r: Reservation }) {
  const qc = useQueryClient()
  const [confirming, setConfirming] = useState(false)
  const cancel = useMutation({
    mutationFn: () => api.post(`/reservations/${r.reservation_id}/cancel`),
    onSuccess: () => {
      toast.success(`Booking ${ticketNumber(r.reservation_id)} cancelled. The table is free again.`)
      qc.invalidateQueries({ queryKey: ['reservations'] })
      qc.invalidateQueries({ queryKey: ['tables'] })
      qc.invalidateQueries({ queryKey: ['slots'] })
    },
    onError: (e) => {
      toast.error(e.message)
      setConfirming(false)
      qc.invalidateQueries({ queryKey: ['reservations'] })
    },
  })

  return (
    <li className={`booking-row status-row-${r.status}`}>
      <DateBlock stamp={r.starts_at} />
      <div className="br-main">
        <p className="br-place">{r.restaurant_name}</p>
        <p className="br-detail">
          {friendlyTime(timeOf(r.starts_at))} · table {r.table_number} · {r.party_size} {r.party_size === 1 ? 'guest' : 'guests'}
        </p>
        <span className={`status status-${r.status}`}>{STATUS_WORDS[r.status]}</span>
      </div>
      <div className="br-actions">
        {confirming ? (
          <div className="confirm-cancel" role="group" aria-label="Confirm cancellation">
            <span>Cancel this booking?</span>
            <button className="btn btn-small btn-danger" onClick={() => cancel.mutate()} disabled={cancel.isPending}>
              {cancel.isPending ? 'Cancelling…' : 'Yes, cancel'}
            </button>
            <button className="btn btn-small btn-ghost" onClick={() => setConfirming(false)} disabled={cancel.isPending}>
              Keep it
            </button>
          </div>
        ) : (
          <>
            <Link to={`/booking/${r.reservation_id}`} className="btn btn-small btn-ghost">
              <Ticket size={16} aria-hidden="true" /> Ticket
            </Link>
            {r.status === 'booked' &&
              (r.can_cancel ? (
                <button className="btn btn-small btn-quiet" onClick={() => setConfirming(true)}>
                  <X size={16} aria-hidden="true" /> Cancel
                </button>
              ) : (
                <span className="too-late muted">Too close to cancel</span>
              ))}
          </>
        )}
      </div>
    </li>
  )
}

export default function MyBookings() {
  const navigate = useNavigate()
  const { data: me, isLoading: meLoading } = useCustomer()
  const list = useQuery({
    queryKey: ['reservations'],
    queryFn: () => api.get<Reservation[]>('/reservations'),
    enabled: !!me,
  })

  useEffect(() => {
    if (!meLoading && !me) navigate('/login?next=/my-bookings', { replace: true })
  }, [me, meLoading, navigate])

  const today = todayIST()
  const all = list.data ?? []
  const upcoming = all
    .filter((r) => (r.status === 'booked' || r.status === 'seated') && dateOf(r.starts_at) >= today)
    .sort((a, b) => a.starts_at.localeCompare(b.starts_at))
  const past = all.filter((r) => !upcoming.includes(r))

  return (
    <div className="my-bookings page">
      <h1 className="enter">My bookings</h1>

      {(meLoading || list.isLoading) && <div className="skeleton" style={{ height: 240, marginTop: 24 }} />}
      {list.error && <div className="notice danger">{(list.error as Error).message}</div>}

      {list.data && (
        <>
          <section className="enter" style={{ animationDelay: '60ms' }} aria-labelledby="upcoming">
            <h2 id="upcoming">Coming up</h2>
            {upcoming.length === 0 ? (
              <div className="empty-card">
                <p className="hand">No tables booked yet.</p>
                <Link to="/" className="btn">
                  Find a table
                </Link>
              </div>
            ) : (
              <ul className="booking-list">
                {upcoming.map((r) => (
                  <Row key={r.reservation_id} r={r} />
                ))}
              </ul>
            )}
          </section>

          {past.length > 0 && (
            <section className="enter" style={{ animationDelay: '100ms' }} aria-labelledby="past">
              <h2 id="past">Past &amp; cancelled</h2>
              <ul className="booking-list is-past">
                {past.map((r) => (
                  <Row key={r.reservation_id} r={r} />
                ))}
              </ul>
            </section>
          )}
        </>
      )}
    </div>
  )
}
