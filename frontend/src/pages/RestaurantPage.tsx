import { useMemo } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ArrowLeft, MapPin, Minus, Phone, Plus, Users } from 'lucide-react'
import { api, type FloorPlan, type Restaurant, type Slot } from '../lib/api'
import { addDays, friendlyTime, shortDate, timeOf, todayIST } from '../lib/time'
import { Cover, hueFor } from '../components/Postcard'
import './RestaurantPage.css'

const DAYS = 14

function dayLabel(date: string, today: string) {
  if (date === today) return 'Today'
  if (date === addDays(today, 1)) return 'Tomorrow'
  return shortDate(date)
}

const PARTS = [
  { name: 'Morning', from: '07:00', to: '11:30' },
  { name: 'Afternoon', from: '12:00', to: '16:30' },
  { name: 'Evening', from: '17:00', to: '21:00' },
]

export default function RestaurantPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [params, setParams] = useSearchParams()
  const today = todayIST()
  const date = params.get('date') ?? today
  const party = Math.min(20, Math.max(1, Number(params.get('party')) || 2))

  const restaurants = useQuery({ queryKey: ['restaurants'], queryFn: () => api.get<Restaurant[]>('/restaurants') })
  const r = restaurants.data?.find((x) => String(x.restaurant_id) === id)

  const plan = useQuery({
    queryKey: ['floor-plan', id],
    queryFn: () => api.get<FloorPlan>(`/restaurants/${id}/floor-plan`),
  })
  const largest = useMemo(() => Math.max(0, ...(plan.data?.tables.map((t) => t.capacity) ?? [0])), [plan.data])

  const slots = useQuery({
    queryKey: ['slots', id, date, party],
    queryFn: () => api.get<Slot[]>(`/restaurants/${id}/slots?date=${date}&party=${party}`),
    refetchInterval: 30_000,
  })

  function set(next: { date?: string; party?: number }) {
    const p = new URLSearchParams(params)
    if (next.date) p.set('date', next.date)
    if (next.party) p.set('party', String(next.party))
    setParams(p, { replace: true })
  }

  if (restaurants.isLoading) {
    return (
      <div className="page" style={{ paddingBlock: 40 }}>
        <div className="skeleton" style={{ height: 320 }} />
      </div>
    )
  }
  if (!r) {
    return (
      <div className="page empty-state">
        <h1>We couldn’t find that place.</h1>
        <Link to="/" className="btn">
          See all restaurants
        </Link>
      </div>
    )
  }

  const days = Array.from({ length: DAYS }, (_, i) => addDays(today, i))
  const tooBig = plan.data && party > largest

  return (
    <div className="restaurant page" style={{ '--hue': hueFor(r.restaurant_id) } as React.CSSProperties}>
      <Link to="/" className="back-link">
        <ArrowLeft size={18} aria-hidden="true" /> All restaurants
      </Link>

      <header className="r-head enter">
        <div className="r-cover">
          <Cover r={r} />
        </div>
        <div className="r-intro">
          <p className="r-cuisine hand">{r.cuisine}</p>
          <h1>{r.name}</h1>
          {r.tagline && <p className="r-tagline">{r.tagline}</p>}
          <ul className="r-facts">
            {r.address && (
              <li>
                <MapPin size={18} aria-hidden="true" /> {r.address}
              </li>
            )}
            {r.phone && (
              <li>
                <Phone size={18} aria-hidden="true" /> {r.phone}
              </li>
            )}
          </ul>
        </div>
      </header>

      <section className="booker enter" style={{ animationDelay: '60ms' }} aria-labelledby="booker-title">
        <h2 id="booker-title">When are you coming?</h2>

        <div className="booker-row">
          <div className="days" role="radiogroup" aria-label="Date">
            {days.map((d) => (
              <button
                key={d}
                role="radio"
                aria-checked={d === date}
                className={`day${d === date ? ' is-on' : ''}`}
                onClick={() => set({ date: d })}
              >
                <span className="day-name">{dayLabel(d, today).split(' ')[0]}</span>
                {d !== today && d !== addDays(today, 1) && <span className="day-num">{dayLabel(d, today).split(' ').slice(1).join(' ')}</span>}
              </button>
            ))}
          </div>

          <div className="party" aria-label="Party size">
            <Users size={20} aria-hidden="true" />
            <button className="step" aria-label="One guest fewer" disabled={party <= 1} onClick={() => set({ party: party - 1 })}>
              <Minus size={18} aria-hidden="true" />
            </button>
            <output className="party-n" aria-live="polite">
              {party} <span>{party === 1 ? 'guest' : 'guests'}</span>
            </output>
            <button className="step" aria-label="One more guest" disabled={party >= 20} onClick={() => set({ party: party + 1 })}>
              <Plus size={18} aria-hidden="true" />
            </button>
          </div>
        </div>
        {party >= 11 && !tooBig && <p className="hall-note hand">Parties of 11 or more get a private hall.</p>}

        <div className="chalkboard">
          <p className="chalk-title hand">
            {dayLabel(date, today) === 'Today' || dayLabel(date, today) === 'Tomorrow'
              ? dayLabel(date, today)
              : shortDate(date)}
            ’s free tables
          </p>

          {slots.isLoading && <p className="chalk-line hand">checking the book…</p>}
          {slots.error && <p className="chalk-line hand">{(slots.error as Error).message}</p>}

          {tooBig && (
            <p className="chalk-line hand">
              Sorry, our largest table seats {largest}. Try fewer guests or another place.
            </p>
          )}
          {!tooBig && slots.data && slots.data.length === 0 && (
            <p className="chalk-line hand">All booked up. Try another day?</p>
          )}

          {!tooBig &&
            slots.data &&
            slots.data.length > 0 &&
            PARTS.map((part) => {
              const inPart = slots.data.filter((s) => timeOf(s.start) >= part.from && timeOf(s.start) <= part.to)
              if (inPart.length === 0) return null
              return (
                <div key={part.name} className="chalk-part">
                  <p className="chalk-part-name hand">{part.name}</p>
                  <div className="chalk-times">
                    {inPart.map((s) => (
                      <button
                        key={s.start}
                        className="chalk-time"
                        onClick={() => navigate(`/r/${r.restaurant_id}/book?date=${date}&time=${timeOf(s.start)}&party=${party}`)}
                        aria-label={`${friendlyTime(timeOf(s.start))}, ${s.free_tables} ${s.free_tables === 1 ? 'table' : 'tables'} free`}
                      >
                        <span className="hand">{friendlyTime(timeOf(s.start))}</span>
                        <small>{s.free_tables} free</small>
                      </button>
                    ))}
                  </div>
                </div>
              )
            })}
        </div>
        <p className="muted booker-foot">A sitting is 2 hours. Next you’ll choose your table on the floor plan.</p>
      </section>
    </div>
  )
}
