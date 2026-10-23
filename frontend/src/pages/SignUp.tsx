import { useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { useMutation } from '@tanstack/react-query'
import { MailCheck } from 'lucide-react'
import { toast } from 'sonner'
import { api } from '../lib/api'
import './Auth.css'

export default function SignUp() {
  const [form, setForm] = useState({ full_name: '', email: '', phone: '', password: '' })
  const signUp = useMutation({ mutationFn: () => api.post('/auth/signup', form) })
  const resend = useMutation({
    mutationFn: () => api.post('/auth/resend', { email: form.email }),
    onSuccess: () => toast.success('Sent again. Check your inbox (and spam).'),
  })

  function update(key: keyof typeof form) {
    return (e: React.ChangeEvent<HTMLInputElement>) => setForm({ ...form, [key]: e.target.value })
  }

  function submit(e: FormEvent) {
    e.preventDefault()
    signUp.mutate()
  }

  return (
    <div className="auth page">
      <div className="auth-card enter">
        {signUp.isSuccess ? (
          <div className="done">
            <MailCheck size={40} color="var(--olive)" aria-hidden="true" />
            <h1>Check your inbox</h1>
            <p className="lede">
              We sent a link to <strong>{form.email}</strong>. Click it to verify your email, then you can book.
            </p>
            <p className="hand">the link works for 24 hours</p>
            <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
              <Link to="/login" className="btn">
                Go to log in
              </Link>
              <button className="btn btn-ghost" onClick={() => resend.mutate()} disabled={resend.isPending}>
                Send it again
              </button>
            </div>
          </div>
        ) : (
          <>
            <h1>Join Terrasse</h1>
            <p className="lede">One account for every restaurant here.</p>
            <form className="auth-form" onSubmit={submit}>
              <div className="field">
                <label htmlFor="name">Your name</label>
                <input id="name" className="input" autoComplete="name" required value={form.full_name} onChange={update('full_name')} />
              </div>
              <div className="field">
                <label htmlFor="email">Email</label>
                <input id="email" className="input" type="email" autoComplete="email" required value={form.email} onChange={update('email')} />
              </div>
              <div className="field">
                <label htmlFor="phone">
                  Phone <span className="muted">(optional, so the restaurant can reach you)</span>
                </label>
                <input id="phone" className="input" type="tel" autoComplete="tel" value={form.phone} onChange={update('phone')} />
              </div>
              <div className="field">
                <label htmlFor="password">Password</label>
                <input
                  id="password"
                  className="input"
                  type="password"
                  autoComplete="new-password"
                  required
                  minLength={8}
                  maxLength={72}
                  value={form.password}
                  onChange={update('password')}
                  aria-describedby="pw-hint"
                />
                <small id="pw-hint" className="muted">
                  8 to 72 characters.
                </small>
              </div>
              {signUp.error && (
                <p className="error-text" role="alert">
                  {signUp.error.message}
                </p>
              )}
              <button className="btn" type="submit" disabled={signUp.isPending}>
                {signUp.isPending ? 'Creating your account…' : 'Create account'}
              </button>
            </form>
            <p className="auth-alt">
              Already have one? <Link to="/login">Log in</Link>
            </p>
          </>
        )}
      </div>
      <aside className="auth-side enter" style={{ animationDelay: '80ms' }}>
        <h2>Why verify?</h2>
        <p className="muted">
          Only verified emails can book, so every table on the floor plan is held by a real person. The link in your inbox works
          once and lasts a day.
        </p>
      </aside>
    </div>
  )
}
