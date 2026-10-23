import { useEffect, useState, type FormEvent } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CircleCheck, CircleX } from 'lucide-react'
import { toast } from 'sonner'
import { api } from '../lib/api'
import './Auth.css'

// The email links here, not to the API. This page makes the call from
// JavaScript, so a mail scanner that pre-opens links can't use up the token.
export default function VerifyEmail() {
  const [params] = useSearchParams()
  const token = params.get('token') ?? ''
  const qc = useQueryClient()
  const [email, setEmail] = useState('')

  // useQuery runs it once per token, even under React's double-mount in dev.
  const verify = useQuery({
    queryKey: ['verify', token],
    queryFn: () => api.get<{ message: string }>(`/auth/verify?token=${encodeURIComponent(token)}`),
    enabled: !!token,
    retry: false,
    staleTime: Infinity,
    gcTime: Infinity,
    refetchOnWindowFocus: false,
  })

  useEffect(() => {
    if (verify.isSuccess) qc.invalidateQueries({ queryKey: ['me', 'customer'] })
  }, [verify.isSuccess, qc])

  const resend = useMutation({
    mutationFn: () => api.post('/auth/resend', { email }),
    onSuccess: () => toast.success('If that email needs verifying, a new link is on its way.'),
  })

  function submit(e: FormEvent) {
    e.preventDefault()
    resend.mutate()
  }

  return (
    <div className="page" style={{ maxWidth: 620, paddingBlock: 'clamp(32px, 6vw, 72px) 80px' }}>
      <div className="auth-card enter">
        {!token || verify.isError ? (
          <div className="done">
            <CircleX size={40} color="var(--danger)" aria-hidden="true" />
            <h1>That link didn’t work</h1>
            <p className="lede">
              {verify.error?.message ?? 'The link is missing its code.'} Ask for a fresh one below; the newest link is the one that
              works.
            </p>
            <form className="auth-form" onSubmit={submit} style={{ width: '100%' }}>
              <div className="field">
                <label htmlFor="email">Your email</label>
                <input id="email" className="input" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
              </div>
              <button className="btn" type="submit" disabled={resend.isPending}>
                Send a new link
              </button>
            </form>
          </div>
        ) : verify.isSuccess ? (
          <div className="done">
            <CircleCheck size={40} color="var(--olive)" aria-hidden="true" />
            <h1>You’re verified!</h1>
            <p className="lede">Your email is confirmed. Time to find a table in the sun.</p>
            <Link to="/" className="btn">
              Find a table
            </Link>
          </div>
        ) : (
          <div className="done">
            <h1>Checking your link…</h1>
            <div className="skeleton" style={{ height: 18, width: '60%' }} />
          </div>
        )}
      </div>
    </div>
  )
}
