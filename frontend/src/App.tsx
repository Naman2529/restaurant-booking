import { Outlet, Route, Routes, useLocation } from 'react-router-dom'
import { useEffect } from 'react'
import Header from './components/Header'
import Credits from './components/Credits'
import Home from './pages/Home'
import RestaurantPage from './pages/RestaurantPage'
import PickTable from './pages/PickTable'
import Confirmed from './pages/Confirmed'
import MyBookings from './pages/MyBookings'
import Login from './pages/Login'
import SignUp from './pages/SignUp'
import VerifyEmail from './pages/VerifyEmail'
import NotFound from './pages/NotFound'
import StaffLayout from './staff/StaffLayout'
import Dashboard from './staff/Dashboard'

function CustomerLayout() {
  const { pathname } = useLocation()
  useEffect(() => {
    window.scrollTo(0, 0)
  }, [pathname])
  return (
    <>
      <Header />
      <main>
        <Outlet />
      </main>
      <footer className="site-footer page">
        <p className="hand">Terrasse</p>
        <p className="muted">Every booking rule lives in the database: no table is ever booked twice.</p>
        <Credits />
      </footer>
    </>
  )
}

export default function App() {
  return (
    <Routes>
      <Route path="business" element={<StaffLayout />}>
        <Route index element={<Dashboard />} />
      </Route>
      <Route element={<CustomerLayout />}>
        <Route index element={<Home />} />
        <Route path="r/:id" element={<RestaurantPage />} />
        <Route path="r/:id/book" element={<PickTable />} />
        <Route path="booking/:id" element={<Confirmed />} />
        <Route path="my-bookings" element={<MyBookings />} />
        <Route path="login" element={<Login />} />
        <Route path="signup" element={<SignUp />} />
        <Route path="verify-email" element={<VerifyEmail />} />
        <Route path="*" element={<NotFound />} />
      </Route>
    </Routes>
  )
}
