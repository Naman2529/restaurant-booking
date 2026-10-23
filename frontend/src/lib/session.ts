import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api, ApiError, type CustomerMe, type StaffMe } from './api'

// The auth cookie is HttpOnly, so the page can't read it. "Who am I" comes
// from GET /auth/<kind>/me: 401 means not logged in (null, not an error).

async function whoAmI<T>(kind: 'customer' | 'staff'): Promise<T | null> {
  try {
    return await api.get<T>(`/auth/${kind}/me`)
  } catch (e) {
    if (e instanceof ApiError && (e.status === 401 || e.status === 403)) return null
    throw e
  }
}

export function useCustomer() {
  return useQuery({
    queryKey: ['me', 'customer'],
    queryFn: () => whoAmI<CustomerMe>('customer'),
    staleTime: 60_000,
    retry: false,
  })
}

export function useStaff() {
  return useQuery({
    queryKey: ['me', 'staff'],
    queryFn: () => whoAmI<StaffMe>('staff'),
    staleTime: 60_000,
    retry: false,
  })
}

export function useLogin(kind: 'customer' | 'staff') {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (body: { email: string; password: string }) => api.post(`/auth/${kind}/login`, body),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['me', kind] }),
  })
}

export function useLogout(kind: 'customer' | 'staff') {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => api.post(`/auth/${kind}/logout`),
    onSettled: () => {
      qc.setQueryData(['me', kind], null)
      qc.removeQueries({ queryKey: kind === 'customer' ? ['reservations'] : ['staff'] })
    },
  })
}
