import { Link, NavLink, useNavigate } from 'react-router-dom'
import { CalendarHeart, LogOut, Store } from 'lucide-react'
import { toast } from 'sonner'
import { useCustomer, useLogout } from '../lib/session'
import './Header.css'

export function Awning() {
  return <div className="awning" aria-hidden="true" />
}

export function Logo() {
  return (
    <Link to="/" className="logo" aria-label="Terrasse, home">
      Terrasse
    </Link>
  )
}

export default function Header() {
  const { data: me } = useCustomer()
  const logout = useLogout('customer')
  const navigate = useNavigate()

  return (
    <header className="site-header">
      <Awning />
      <div className="page header-row">
        <Logo />
        <nav className="header-nav" aria-label="Main">
          <NavLink to="/" end className="nav-link">
            Restaurants
          </NavLink>
          {me && (
            <NavLink to="/my-bookings" className="nav-link">
              <CalendarHeart size={18} aria-hidden="true" />
              My bookings
            </NavLink>
          )}
          {me ? (
            <div className="user-chip">
              <span className="user-initial" aria-hidden="true">
                {me.full_name.charAt(0)}
              </span>
              <span className="user-name">{me.full_name.split(' ')[0]}</span>
              <button
                className="icon-btn"
                aria-label="Log out"
                title="Log out"
                onClick={() =>
                  logout.mutate(undefined, {
                    onSuccess: () => {
                      toast('See you soon!')
                      navigate('/')
                    },
                  })
                }
              >
                <LogOut size={18} aria-hidden="true" />
              </button>
            </div>
          ) : (
            <>
              <Link to="/login?as=business" className="nav-link business-link">
                <Store size={18} aria-hidden="true" />
                For restaurants
              </Link>
              <Link to="/login" className="btn btn-small">
                Log in
              </Link>
            </>
          )}
        </nav>
      </div>
    </header>
  )
}
