import { useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowRight } from 'lucide-react'
import type { Restaurant } from '../lib/api'
import './Postcard.css'

// Each restaurant gets its own warm colour, used for its stamp and for the
// illustrated cover when no photo is available.
const HUES = ['#c8553d', '#2f5d8a', '#5f8a3c', '#d9902a', '#8a4f7d', '#3f7f78']

export function hueFor(id: number) {
  return HUES[(id - 1) % HUES.length]
}

export function cityOf(address: string | null) {
  if (!address) return ''
  const parts = address.split(',')
  return parts[parts.length - 1].trim()
}

export function Cover({ r, className = '' }: { r: Restaurant; className?: string }) {
  const [failed, setFailed] = useState(false)
  if (r.photo && !failed) {
    return (
      <img
        className={`cover ${className}`}
        src={r.photo}
        alt=""
        loading="lazy"
        onError={() => setFailed(true)}
      />
    )
  }
  return (
    <div className={`cover cover-drawn ${className}`} style={{ '--hue': hueFor(r.restaurant_id) } as React.CSSProperties} aria-hidden="true">
      <span>{r.name.replace(/^The /, '').charAt(0)}</span>
    </div>
  )
}

export default function Postcard({ r, index }: { r: Restaurant; index: number }) {
  return (
    <Link
      to={`/r/${r.restaurant_id}`}
      className="postcard enter"
      style={{ animationDelay: `${Math.min(index, 8) * 55}ms`, '--hue': hueFor(r.restaurant_id) } as React.CSSProperties}
    >
      <div className="postcard-photo">
        <Cover r={r} />
        <span className="stamp hand" aria-hidden="true">
          {cityOf(r.address)}
        </span>
      </div>
      <div className="postcard-body">
        <h3>{r.name}</h3>
        <p className="postcard-meta hand">{r.cuisine}</p>
        {r.tagline && <p className="postcard-tagline">{r.tagline}</p>}
        <span className="postcard-cta">
          Book a table <ArrowRight size={18} aria-hidden="true" />
        </span>
      </div>
    </Link>
  )
}
