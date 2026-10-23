import { Component, type ReactNode } from 'react'

// A crash in one page shows this instead of a blank screen.
export default class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null }

  static getDerivedStateFromError(error: Error) {
    return { error }
  }

  render() {
    if (!this.state.error) return this.props.children
    return (
      <div className="page empty-state">
        <p className="hand" style={{ fontSize: '2rem', color: 'var(--ink-soft)' }}>
          oops, we dropped a cup
        </p>
        <h1>Something went wrong on this page.</h1>
        <p className="muted">{this.state.error.message}</p>
        <button className="btn" onClick={() => window.location.reload()}>
          Reload the page
        </button>
      </div>
    )
  }
}
