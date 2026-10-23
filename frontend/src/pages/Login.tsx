import { useState, type FormEvent } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { Store, UserRound } from 'lucide-react'
import { toast } from 'sonner'
import { useLogin } from '../lib/session'
import './Auth.css'

type Kind = 'customer' | 'staff'

const DEMO: Record<Kind, { email: string; who: string }[]> = {
  customer: [
    { email: 'aarav@example.com', who: 'Aarav, verified' },
    { email: 'meera@example.com', who: 'Meera, not verified yet' },
  ],
  staff: [
    { email: 'reception@spiceroute.example.com', who: 'Spice Route, receptionist' },
    { email: 'waiter@spiceroute.example.com', who: 'Spice Route, waiter' },
    { email: 'reception@cafelumiere.example.com', who: 'Café Lumière, receptionist' },
  ],
}

/** Only follow ?next= to our own pages. */
function safeNext(next: string | null) {
  return next && next.startsWith('/') && !next.startsWith('//') ? next : null
}

export default function Login() {
  const [params, setParams] = useSearchParams()
  const navigate = useNavigate()
  const kind: Kind = params.get('as') === 'business' ? 'staff' : 'customer'
  const next = safeNext(params.get('next'))

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const login = useLogin(kind)

  function switchTo(k: Kind) {
    const p = new URLSearchParams(params)
    if (k === 'staff') p.set('as', 'business')
    else p.delete('as')
    setParams(p, { replace: true })
    login.reset()
  }

  function submit(e: FormEvent) {
    e.preventDefault()
    login.mutate(
      { email, password },
      {
        onSuccess: () => {
          if (kind === 'staff') {
            navigate('/business')
          } else {
            toast.success('Welcome back!')
            navigate(next ?? '/')
          }
        },
      },
    )
  }

  return (
    <div className="auth page">
      <div className="auth-card enter">
        <div className="segmented" role="tablist" aria-label="Who is logging in">
          <button role="tab" aria-selected={kind === 'customer'} onClick={() => switchTo('customer')}>
            <UserRound size={18} aria-hidden="true" /> Guest
          </button>
          <button role="tab" aria-selected={kind === 'staff'} onClick={() => switchTo('staff')}>
            <Store size={18} aria-hidden="true" /> Restaurant team
          </button>
        </div>

        <h1>{kind === 'customer' ? 'Welcome back' : 'Log in as a business'}</h1>
        <p className="lede">
          {kind === 'customer'
            ? next
              ? 'Log in to finish your booking. Your table choice is kept.'
              : 'Log in to book tables and see your bookings.'
            : 'Use the staff account your restaurant gave you (receptionist or waiter).'}
        </p>

        <form className="auth-form" onSubmit={submit}>
          <div className="field">
            <label htmlFor="email">Email</label>
            <input
              id="email"
              className="input"
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </div>
          <div className="field">
            <label htmlFor="password">Password</label>
            <input
              id="password"
              className="input"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </div>
          {login.error && (
            <p className="error-text" role="alert">
              {login.error.message}
            </p>
          )}
          <button className="btn" type="submit" disabled={login.isPending}>
            {login.isPending ? 'Logging in…' : 'Log in'}
          </button>
        </form>

        {kind === 'customer' && (
          <p className="auth-alt">
            New here? <Link to={`/signup${next ? `?next=${encodeURIComponent(next)}` : ''}`}>Create an account</Link>
          </p>
        )}
      </div>

      <aside className="auth-side enter" style={{ animationDelay: '80ms' }}>
        <h2>{kind === 'customer' ? 'Your table, your choice.' : 'Your floor, at a glance.'}</h2>
        <p className="muted">
          {kind === 'customer'
            ? 'Pick the exact table you want on the floor plan, by the pond, on the terrace or near the fire.'
            : 'See every table’s state live, seat arrivals, free tables, extend sittings and move bookings.'}
        </p>
        <div className="demo">
          <p className="demo-title hand">Demo accounts</p>
          <ul>
            {DEMO[kind].map((d) => (
              <li key={d.email}>
                <button
                  type="button"
                  onClick={() => {
                    setEmail(d.email)
                    setPassword('password123')
                  }}
                >
                  <span>{d.email}</span>
                  <small>{d.who}</small>
                </button>
              </li>
            ))}
          </ul>
          <p className="demo-foot">Tap one to fill it in. Every demo password is password123.</p>
        </div>
      </aside>
    </div>
  )
}
