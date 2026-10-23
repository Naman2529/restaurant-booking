import { useEffect, useMemo, type CSSProperties } from 'react'
import { Link, useLocation, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, Check, MailWarning, Sparkles } from 'lucide-react'
import { toast } from 'sonner'
import { api, ApiError, type FloorPlan as Plan, type PlanFeature, type PlanTable, type Restaurant, type TableAvailability } from '../lib/api'
import { friendlyTime, shortDate } from '../lib/time'
import { useCustomer } from '../lib/session'
import FloorPlan, { type Tone } from '../components/FloorPlan'
import { hueFor } from '../components/Postcard'
import './PickTable.css'

/** "by the Lily pond" when a feature is close to the table. */
function nearby(t: PlanTable, features: PlanFeature[]) {
  let best: { label: string; d: number } | null = null
  for (const f of features) {
    if (f.kind === 'entrance') continue
    const dx = Math.max(f.x - t.x, 0, t.x - (f.x + f.width))
    const dy = Math.max(f.y - t.y, 0, t.y - (f.y + f.height))
    const d = Math.hypot(dx, dy)
    if (!best || d < best.d) best = { label: f.label, d }
  }
  if (!best || best.d > 130) return null
  const label = best.label.split(',')[0]
  return `by the ${label.charAt(0).toLowerCase()}${label.slice(1)}`
}

function seats(capacity: number) {
  return capacity === 20 ? 'private hall' : `${capacity} seats`
}

export default function PickTable() {
  const { id } = useParams()
  const [params, setParams] = useSearchParams()
  const location = useLocation()
  const navigate = useNavigate()
  const qc = useQueryClient()

  const date = params.get('date') ?? ''
  const time = params.get('time') ?? ''
  const party = Number(params.get('party')) || 2
  const picked = params.get('table') ? Number(params.get('table')) : null
  const start = `${date}T${time}`

  const { data: me } = useCustomer()
  const restaurants = useQuery({ queryKey: ['restaurants'], queryFn: () => api.get<Restaurant[]>('/restaurants') })
  const r = restaurants.data?.find((x) => String(x.restaurant_id) === id)

  const plan = useQuery({
    queryKey: ['floor-plan', id],
    queryFn: () => api.get<Plan>(`/restaurants/${id}/floor-plan`),
  })
  const tables = useQuery({
    queryKey: ['tables', id, start, party],
    queryFn: () => api.get<TableAvailability[]>(`/restaurants/${id}/tables?start=${start}&party=${party}`),
    refetchInterval: 20_000,
  })

  const byNumber = useMemo(() => new Map((tables.data ?? []).map((t) => [t.table_number, t])), [tables.data])
  const bookable = (t: PlanTable) => {
    const a = byNumber.get(t.table_number)
    return !!a && a.fits_party && a.is_free
  }
  const toneOf = (t: PlanTable): Tone => {
    const a = byNumber.get(t.table_number)
    if (!a || !a.fits_party) return 'unfit'
    return a.is_free ? 'free' : 'taken'
  }
  const describe = (t: PlanTable) => {
    const a = byNumber.get(t.table_number)
    if (!a || !a.fits_party) return 'not for your party size'
    return a.is_free ? 'available' : 'already booked'
  }
  const freeCount = (tables.data ?? []).filter((t) => t.fits_party && t.is_free).length

  function setPicked(n: number | null) {
    const p = new URLSearchParams(params)
    if (n === null) p.delete('table')
    else p.set('table', String(n))
    setParams(p, { replace: true })
  }

  // Someone else may take the picked table while this page is open.
  useEffect(() => {
    if (picked !== null && tables.data && !tables.data.some((t) => t.table_number === picked && t.fits_party && t.is_free)) {
      toast('That table was just taken. Please pick another.')
      setPicked(null)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tables.data])

  const book = useMutation({
    mutationFn: (tableNumber: number | null) =>
      api.post<{ reservation_id: number }>('/reservations', {
        restaurant_id: Number(id),
        start,
        party_size: party,
        ...(tableNumber !== null ? { table_number: tableNumber } : {}),
      }),
    onSuccess: (res) => {
      qc.invalidateQueries({ queryKey: ['reservations'] })
      qc.invalidateQueries({ queryKey: ['slots', id] })
      qc.invalidateQueries({ queryKey: ['tables', id] })
      navigate(`/booking/${res.reservation_id}`, { state: { fresh: true } })
    },
    onError: (e) => {
      if (e instanceof ApiError && e.status === 401) {
        goToLogin()
        return
      }
      toast.error(e.message)
      if (e instanceof ApiError && e.status === 409) {
        setPicked(null)
        tables.refetch()
      }
    },
  })

  const resend = useMutation({
    mutationFn: () => api.post('/auth/resend', { email: me?.email }),
    onSuccess: () => toast.success('A new link is on its way to your inbox.'),
  })

  function goToLogin() {
    navigate(`/login?next=${encodeURIComponent(location.pathname + location.search)}`)
  }

  function submit(tableNumber: number | null) {
    if (!me) {
      goToLogin()
      return
    }
    book.mutate(tableNumber)
  }

  if (!date || !time) {
    return (
      <div className="page empty-state">
        <h1>Pick a time first.</h1>
        <Link to={`/r/${id}`} className="btn">
          Choose a time
        </Link>
      </div>
    )
  }

  const pickedTable = plan.data?.tables.find((t) => t.table_number === picked) ?? null
  const near = pickedTable && plan.data ? nearby(pickedTable, plan.data.features) : null
  const unverified = me && !me.email_verified

  return (
    <div className="pick" style={{ '--hue': r ? hueFor(r.restaurant_id) : 'var(--terracotta)' } as CSSProperties}>
      <div className="page">
        <Link to={`/r/${id}?date=${date}&party=${party}`} className="back-link">
          <ArrowLeft size={18} aria-hidden="true" /> Change time
        </Link>

        <header className="pick-head enter">
          <div>
            <h1>{r ? r.name : 'Choose your table'}</h1>
            <p className="pick-when">
              <span>{shortDate(date)}</span>
              <span aria-hidden="true">·</span>
              <span>{friendlyTime(time)}</span>
              <span aria-hidden="true">·</span>
              <span>
                {party} {party === 1 ? 'guest' : 'guests'}
              </span>
            </p>
          </div>
          <ul className="legend" aria-label="Legend">
            <li>
              <i className="sw sw-free" /> Free for you
            </li>
            <li>
              <i className="sw sw-unfit" /> Not your size
            </li>
            <li>
              <i className="sw sw-taken" /> Booked
            </li>
            <li>
              <i className="sw sw-picked" /> Your pick
            </li>
          </ul>
        </header>

        <div className="plan-card enter" style={{ animationDelay: '60ms' }}>
          {plan.isLoading || tables.isLoading ? (
            <div className="skeleton" style={{ aspectRatio: '1000 / 640' }} />
          ) : plan.error || tables.error ? (
            <div className="notice danger">
              <p>{((plan.error || tables.error) as Error).message}</p>
            </div>
          ) : (
            plan.data && (
              <div className="plan-scroll">
                <p className="swipe-hint hand" aria-hidden="true">
                  swipe to see the whole room →
                </p>
                <FloorPlan
                  plan={plan.data}
                  toneOf={toneOf}
                  isSelectable={bookable}
                  selected={picked}
                  onSelect={(t) => setPicked(picked === t.table_number ? null : t.table_number)}
                  describe={describe}
                />
              </div>
            )
          )}
          {tables.data && freeCount === 0 && (
            <p className="plan-empty hand">Every table for {party} is booked at this time. Try another time?</p>
          )}
        </div>

        <p className="plan-hint muted">
          Only tables that suit your party can be picked: the snug size, or one size up. Bigger tables are kept for bigger groups.
        </p>
      </div>

      {/* The booking bar, like a cinema seat picker */}
      <div className="book-bar" role="region" aria-label="Your booking">
        <div className="page book-bar-row">
          <div className="book-bar-info" aria-live="polite">
            {pickedTable ? (
              <>
                <span className="picked-badge">
                  <Check size={16} aria-hidden="true" /> Table {pickedTable.table_number}
                </span>
                <span className="picked-detail">
                  {seats(pickedTable.capacity)}
                  {near && <span className="hand near"> {near}</span>}
                </span>
              </>
            ) : (
              <span className="hand pick-prompt">
                {freeCount > 0 ? 'Tap a green table to make it yours' : 'No free tables at this time'}
              </span>
            )}
          </div>

          {unverified ? (
            <div className="verify-nudge">
              <MailWarning size={20} aria-hidden="true" />
              <span>Verify your email to book.</span>
              <button className="btn btn-small btn-quiet" onClick={() => resend.mutate()} disabled={resend.isPending}>
                Resend link
              </button>
            </div>
          ) : (
            <div className="book-bar-actions">
              <button
                className="btn btn-ghost"
                onClick={() => submit(null)}
                disabled={book.isPending || freeCount === 0}
                title="We’ll give you the snuggest free table"
              >
                <Sparkles size={18} aria-hidden="true" /> Pick for me
              </button>
              <button className="btn" onClick={() => submit(picked)} disabled={book.isPending || picked === null}>
                {book.isPending ? 'Booking…' : picked !== null ? `Book table ${picked}` : 'Book table'}
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
