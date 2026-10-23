import { Navigate, Outlet, useNavigate } from 'react-router-dom'
import { LogOut } from 'lucide-react'
import { toast } from 'sonner'
import { useLogout, useStaff } from '../lib/session'
import './staff.css'

export default function StaffLayout() {
  const { data: me, isLoading } = useStaff()
  const logout = useLogout('staff')
  const navigate = useNavigate()

  if (isLoading) {
    return (
      <div className="staff-shell">
        <div className="skeleton" style={{ height: 480, margin: 24 }} />
      </div>
    )
  }
  if (!me) return <Navigate to="/login?as=business" replace />

  return (
    <div className="staff-shell">
      <div className="staff-awning" aria-hidden="true" />
      <header className="staff-top">
        <div className="staff-brand">
          <span className="staff-logo">Terrasse</span>
          <span className="staff-for hand">for {me.restaurant_name}</span>
        </div>
        <div className="staff-who">
          <span className="staff-name">{me.full_name}</span>
          <span className={`role role-${me.role}`}>{me.role}</span>
          <button
            className="icon-btn"
            aria-label="Log out"
            title="Log out"
            onClick={() =>
              logout.mutate(undefined, {
                onSuccess: () => {
                  toast('Logged out. Have a good shift!')
                  navigate('/login?as=business')
                },
              })
            }
          >
            <LogOut size={18} aria-hidden="true" />
          </button>
        </div>
      </header>
      <Outlet context={me} />
    </div>
  )
}
