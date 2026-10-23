import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Search, X } from 'lucide-react'
import { api, type Restaurant } from '../lib/api'
import Postcard, { cityOf } from '../components/Postcard'
import Bistro from '../components/Bistro'
import './Home.css'

function matches(r: Restaurant, q: string) {
  const hay = [r.name, r.cuisine, r.tagline, r.address].filter(Boolean).join(' ').toLowerCase()
  return q
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean)
    .every((word) => hay.includes(word))
}

export default function Home() {
  const [q, setQ] = useState('')
  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ['restaurants'],
    queryFn: () => api.get<Restaurant[]>('/restaurants'),
  })

  const shown = useMemo(() => (data ?? []).filter((r) => matches(r, q)), [data, q])
  const cities = useMemo(() => [...new Set((data ?? []).map((r) => cityOf(r.address)))], [data])

  return (
    <div className="home">
      <section className="hero page">
        <div className="hero-copy enter">
          <h1>
            A table in the sun, <em>saved just for you.</em>
          </h1>
          <p className="hero-lede">
            Neighbourhood places from {cities.length > 1 ? `${cities.slice(0, -1).join(', ')} and ${cities.at(-1)}` : 'all over'}.
            Pick a spot, pick a time, then pick the very table you want.
          </p>
          <label className="search" htmlFor="search">
            <Search size={20} aria-hidden="true" />
            <span className="visually-hidden">Search restaurants</span>
            <input
              id="search"
              type="search"
              placeholder="Search by name, food or city"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              autoComplete="off"
            />
            {q && (
              <button type="button" className="icon-btn" aria-label="Clear search" onClick={() => setQ('')}>
                <X size={18} aria-hidden="true" />
              </button>
            )}
          </label>
        </div>
        <div className="hero-art enter" style={{ animationDelay: '80ms' }}>
          <Bistro />
          <p className="hero-note hand">open today, 7 am till 11 pm</p>
        </div>
      </section>

      <section className="page listing" aria-labelledby="listing-title">
        <div className="listing-head">
          <h2 id="listing-title">{q ? `Places matching “${q}”` : 'Where to today?'}</h2>
          {data && <p className="muted">{shown.length} of {data.length}</p>}
        </div>

        {isLoading && (
          <div className="postcards">
            {[0, 1, 2].map((i) => (
              <div key={i} className="skeleton" style={{ height: 380 }} />
            ))}
          </div>
        )}

        {error && (
          <div className="notice danger">
            <p>{(error as Error).message}</p>
            <button className="btn btn-small btn-quiet" onClick={() => refetch()}>
              Try again
            </button>
          </div>
        )}

        {data && shown.length === 0 && (
          <div className="empty">
            <p className="hand">Nothing by that name yet.</p>
            <p className="muted">Try “tea”, “pizza” or “Kochi”.</p>
          </div>
        )}

        <div className="postcards">
          {shown.map((r, i) => (
            <Postcard key={r.restaurant_id} r={r} index={i} />
          ))}
        </div>
      </section>
    </div>
  )
}
