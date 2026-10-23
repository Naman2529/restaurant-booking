import { Link } from 'react-router-dom'

export default function NotFound() {
  return (
    <div className="page empty-state">
      <p className="hand" style={{ fontSize: '2rem', color: 'var(--ink-soft)' }}>
        this street doesn’t go anywhere
      </p>
      <h1>Page not found</h1>
      <Link to="/" className="btn">
        Back to the restaurants
      </Link>
    </div>
  )
}
