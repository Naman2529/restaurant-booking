import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { QRCodeSVG } from 'qrcode.react'
import { CalendarPlus, ListChecks } from 'lucide-react'
import { useEffect } from 'react'
import { api, ApiError, type Reservation, type Restaurant } from '../lib/api'
import { dateOf, friendlyTime, longDate, timeOf } from '../lib/time'
import { useCustomer } from '../lib/session'
import './Confirmed.css'

export function ticketNumber(id: number) {
  return String(id).padStart(4, '0')
}

const STATUS_WORDS: Record<Reservation['status'], string> = {
  booked: 'Confirmed',
  seated: 'Seated',
  completed: 'Completed',
  no_show: 'Missed',
  cancelled: 'Cancelled',
}

/** A calendar file in IST, so phones add it at the right local time. */
function downloadIcs(r: Reservation, address: string | null) {
  const stamp = (s: string) => s.replace(/[-:]/g, '') + '00'
  const ics = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Terrasse//Booking//EN',
    'BEGIN:VEVENT',
    `UID:terrasse-${r.reservation_id}@terrasse.local`,
    `DTSTART;TZID=Asia/Kolkata:${stamp(r.starts_at)}`,
    `DTEND;TZID=Asia/Kolkata:${stamp(r.ends_at)}`,
    `SUMMARY:Table ${r.table_number} at ${r.restaurant_name}`,
    `DESCRIPTION:Booking no. ${ticketNumber(r.reservation_id)} for ${r.party_size}. Show it at the door.`,
    address ? `LOCATION:${address.replace(/,/g, '\\,')}` : '',
    'END:VEVENT',
    'END:VCALENDAR',
  ]
    .filter(Boolean)
    .join('\r\n')
  const url = URL.createObjectURL(new Blob([ics], { type: 'text/calendar' }))
  const a = document.createElement('a')
  a.href = url
  a.download = `terrasse-booking-${r.reservation_id}.ics`
  a.click()
  URL.revokeObjectURL(url)
}

export default function Confirmed() {
  const { id } = useParams()
  const location = useLocation()
  const navigate = useNavigate()
  const fresh = (location.state as { fresh?: boolean } | null)?.fresh
  const { data: me, isLoading: meLoading } = useCustomer()

  const res = useQuery({
    queryKey: ['reservations', id],
    queryFn: () => api.get<Reservation>(`/reservations/${id}`),
    enabled: !!me,
    retry: false,
  })
  const restaurants = useQuery({ queryKey: ['restaurants'], queryFn: () => api.get<Restaurant[]>('/restaurants') })

  useEffect(() => {
    if (!meLoading && !me) navigate(`/login?next=${encodeURIComponent(location.pathname)}`, { replace: true })
  }, [me, meLoading, navigate, location.pathname])

  if (meLoading || res.isLoading) {
    return (
      <div className="page" style={{ paddingBlock: 48 }}>
        <div className="skeleton" style={{ height: 420, maxWidth: 760, margin: '0 auto' }} />
      </div>
    )
  }

  if (res.error || !res.data) {
    const notFound = res.error instanceof ApiError && res.error.status === 404
    return (
      <div className="page empty-state">
        <h1>{notFound ? 'We couldn’t find that booking.' : 'Something went wrong.'}</h1>
        <Link to="/my-bookings" className="btn">
          See my bookings
        </Link>
      </div>
    )
  }

  const r = res.data
  const place = restaurants.data?.find((x) => x.restaurant_id === r.restaurant_id)
  const active = r.status === 'booked' || r.status === 'seated'

  return (
    <div className="confirmed page">
      <header className="confirmed-head enter">
        {fresh ? (
          <>
            <svg className="flourish" viewBox="0 0 120 60" aria-hidden="true">
              <path d="M10 34c10 6 18 14 26 20C52 34 74 14 110 6" />
            </svg>
            <h1>
              You’re booked, <em>{me?.full_name.split(' ')[0]}!</em>
            </h1>
            <p className="muted">Show this ticket when you arrive. We’ve saved it in My bookings too.</p>
          </>
        ) : (
          <h1>Your table</h1>
        )}
      </header>

      <article className="ticket enter" style={{ animationDelay: '80ms' }} aria-label={`Booking number ${ticketNumber(r.reservation_id)}`}>
        <div className="ticket-main">
          <p className="ticket-place hand">{r.restaurant_name}</p>
          <dl className="ticket-grid">
            <div>
              <dt>Date</dt>
              <dd>{longDate(dateOf(r.starts_at))}</dd>
            </div>
            <div>
              <dt>Time</dt>
              <dd>
                {friendlyTime(timeOf(r.starts_at))} – {friendlyTime(timeOf(r.ends_at))}
              </dd>
            </div>
            <div>
              <dt>Table</dt>
              <dd>{r.table_number}</dd>
            </div>
            <div>
              <dt>Guests</dt>
              <dd>{r.party_size}</dd>
            </div>
            <div>
              <dt>Name</dt>
              <dd>{me?.full_name}</dd>
            </div>
            <div>
              <dt>Status</dt>
              <dd>
                <span className={`status status-${r.status}`}>{STATUS_WORDS[r.status]}</span>
              </dd>
            </div>
          </dl>
          {place?.address && <p className="ticket-address muted">{place.address}</p>}
        </div>

        <div className="ticket-stub">
          <p className="stub-label">Booking no.</p>
          <p className="stub-number">{ticketNumber(r.reservation_id)}</p>
          <div className="qr">
            <QRCodeSVG value={`TERRASSE-${r.reservation_id}`} size={116} bgColor="transparent" fgColor="#2b1d14" level="M" />
          </div>
          <p className="stub-note hand">show this at the door</p>
        </div>
      </article>

      <div className="confirmed-actions enter" style={{ animationDelay: '140ms' }}>
        {active && (
          <button className="btn" onClick={() => downloadIcs(r, place?.address ?? null)}>
            <CalendarPlus size={18} aria-hidden="true" /> Add to calendar
          </button>
        )}
        <Link to="/my-bookings" className="btn btn-ghost">
          <ListChecks size={18} aria-hidden="true" /> My bookings
        </Link>
        <Link to="/" className="btn btn-ghost">
          Book somewhere else
        </Link>
      </div>
    </div>
  )
}
