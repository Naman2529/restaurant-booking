import { useQuery } from '@tanstack/react-query'

interface Credit {
  credit: string
  page: string
}

// The restaurant photos are openly licensed; CC BY / BY-SA ask for this credit.
export default function Credits() {
  const { data } = useQuery({
    queryKey: ['photo-credits'],
    queryFn: () => fetch('/photos/credits.json').then((r) => (r.ok ? (r.json() as Promise<Credit[]>) : [])),
    staleTime: Infinity,
  })
  if (!data?.length) return null
  return (
    <details className="credits">
      <summary>Photo credits</summary>
      <ul>
        {data.map((c) => (
          <li key={c.page}>
            <a href={c.page} target="_blank" rel="noreferrer">
              {c.credit}
            </a>
          </li>
        ))}
      </ul>
    </details>
  )
}
