import { useId, type KeyboardEvent } from 'react'
import type { FloorPlan as Plan, PlanFeature, PlanTable } from '../lib/api'
import './FloorPlan.css'

// The restaurant drawn from above, on the 1000 x 640 plan the database
// stores. Customers and staff share it; only the colours (tones) differ.

export type Tone =
  // customer view of one time slot
  | 'free'
  | 'unfit'
  | 'taken'
  // staff seat-map colours, derived in the database
  | 'green'
  | 'transparent'
  | 'gray'
  | 'red'
  | 'orange'

interface Props {
  plan: Plan
  toneOf: (t: PlanTable) => Tone
  /** Which tables respond to clicks. Defaults to none. */
  isSelectable?: (t: PlanTable) => boolean
  selected?: number | null
  onSelect?: (t: PlanTable) => void
  /** Extra words for screen readers, e.g. "available" or "seated until 21:30". */
  describe?: (t: PlanTable) => string
  /** Customer view marks the pick in terracotta; staff view uses a ring. */
  selectionStyle?: 'fill' | 'ring'
  /** Tables to pulse gently, e.g. valid targets while reassigning. */
  highlight?: Set<number>
}

/* ---------- Table geometry (plan units) ---------- */

interface Shape {
  kind: 'round' | 'rect' | 'hall'
  w: number
  h: number
  top: number // chairs along the top (and the same along the bottom)
  ends: boolean
}

const SHAPES: Record<number, Shape> = {
  2: { kind: 'round', w: 34, h: 34, top: 0, ends: true },
  4: { kind: 'rect', w: 40, h: 40, top: 1, ends: true },
  6: { kind: 'rect', w: 74, h: 38, top: 2, ends: true },
  8: { kind: 'rect', w: 104, h: 38, top: 3, ends: true },
  10: { kind: 'rect', w: 134, h: 42, top: 4, ends: true },
  20: { kind: 'hall', w: 196, h: 126, top: 0, ends: false },
}

const CHAIR_LONG = 15
const CHAIR_SHORT = 9
const GAP = 4

function Chairs({ s }: { s: Shape }) {
  const chairs: { x: number; y: number; w: number; h: number }[] = []
  for (let i = 0; i < s.top; i++) {
    const x = -s.w / 2 + (s.w * (i + 0.5)) / s.top
    chairs.push({ x, y: -s.h / 2 - GAP - CHAIR_SHORT / 2, w: CHAIR_LONG, h: CHAIR_SHORT })
    chairs.push({ x, y: s.h / 2 + GAP + CHAIR_SHORT / 2, w: CHAIR_LONG, h: CHAIR_SHORT })
  }
  if (s.ends) {
    const dx = s.w / 2 + GAP + CHAIR_SHORT / 2
    chairs.push({ x: -dx, y: 0, w: CHAIR_SHORT, h: CHAIR_LONG })
    chairs.push({ x: dx, y: 0, w: CHAIR_SHORT, h: CHAIR_LONG })
  }
  return (
    <>
      {chairs.map((c, i) => (
        <rect key={i} className="chair" x={c.x - c.w / 2} y={c.y - c.h / 2} width={c.w} height={c.h} rx={3.5} />
      ))}
    </>
  )
}

function TableShape({ t, s, hatchId }: { t: PlanTable; s: Shape; hatchId: string }) {
  if (s.kind === 'hall') {
    return (
      <>
        <rect className="hall-room" x={-s.w / 2} y={-s.h / 2} width={s.w} height={s.h} rx={16} />
        <rect className="hall-hatch" x={-s.w / 2} y={-s.h / 2} width={s.w} height={s.h} rx={16} fill={`url(#${hatchId})`} />
        <rect className="hall-table" x={-62} y={-9} width={124} height={22} rx={6} />
        <text className="hall-label hand" y={-30}>
          Private hall
        </text>
        <text className="tbl-num" y={42}>
          {t.table_number}
        </text>
      </>
    )
  }
  return (
    <>
      <Chairs s={s} />
      {s.kind === 'round' ? (
        <>
          <circle className="tbl-top" r={s.w / 2} />
          <circle className="tbl-hatch" r={s.w / 2} fill={`url(#${hatchId})`} />
        </>
      ) : (
        <>
          <rect className="tbl-top" x={-s.w / 2} y={-s.h / 2} width={s.w} height={s.h} rx={7} />
          <rect className="tbl-hatch" x={-s.w / 2} y={-s.h / 2} width={s.w} height={s.h} rx={7} fill={`url(#${hatchId})`} />
        </>
      )}
      <text className="tbl-num" y={1}>
        {t.table_number}
      </text>
    </>
  )
}

/* ---------- Features ---------- */

function Feature({ f, ids }: { f: PlanFeature; ids: Record<string, string> }) {
  const cx = f.x + f.width / 2
  const cy = f.y + f.height / 2
  const vertical = f.height > f.width * 1.6
  const small = Math.min(f.width, f.height) < 50

  let body: React.ReactNode
  switch (f.kind) {
    case 'pond': {
      const pads = [
        [0.22, 0.32, 0.09],
        [0.72, 0.28, 0.07],
        [0.62, 0.72, 0.1],
        [0.3, 0.74, 0.06],
      ]
      body = (
        <>
          <rect className="ft-pond" x={f.x} y={f.y} width={f.width} height={f.height} rx={Math.min(f.width, f.height) / 2} />
          <ellipse className="ft-ripple" cx={cx} cy={cy} rx={f.width * 0.3} ry={f.height * 0.18} />
          <ellipse className="ft-ripple" cx={cx} cy={cy} rx={f.width * 0.18} ry={f.height * 0.1} />
          {pads.map(([px, py, pr], i) => (
            <circle key={i} className="ft-pad" cx={f.x + f.width * px} cy={f.y + f.height * py} r={Math.min(f.width, f.height) * pr} />
          ))}
        </>
      )
      break
    }
    case 'bar': {
      const stools = []
      const n = Math.max(3, Math.floor((vertical ? f.height : f.width) / 48))
      for (let i = 0; i < n; i++) {
        const along = (i + 0.5) / n
        if (vertical) {
          const sx = f.x < 500 ? f.x + f.width + 13 : f.x - 13
          stools.push(<circle key={i} className="ft-stool" cx={sx} cy={f.y + f.height * along} r={7} />)
        } else {
          stools.push(<circle key={i} className="ft-stool" cx={f.x + f.width * along} cy={f.y + f.height + 13} r={7} />)
        }
      }
      body = (
        <>
          {stools}
          <rect className="ft-bar" x={f.x} y={f.y} width={f.width} height={f.height} rx={10} />
          <rect
            className="ft-bar-top"
            x={f.x + 8}
            y={f.y + 8}
            width={Math.max(0, f.width - 16)}
            height={Math.max(0, f.height - 16)}
            rx={6}
          />
        </>
      )
      break
    }
    case 'entrance': {
      const atBottom = f.y + f.height >= 600
      body = (
        <>
          <rect className="ft-entrance" x={f.x} y={f.y} width={f.width} height={f.height} rx={8} />
          <path
            className="ft-arrow"
            d={
              atBottom
                ? `M${cx} ${f.y + f.height - 8} V${f.y + 10} m-7 8 l7 -8 l7 8`
                : `M${cx} ${f.y + 8} V${f.y + f.height - 10} m-7 -8 l7 8 l7 -8`
            }
          />
        </>
      )
      break
    }
    case 'shelf': {
      const books = []
      const colours = ['#c8553d', '#2f5d8a', '#f2b33d', '#5f8a3c', '#a8744b', '#e8a598']
      for (let x = f.x + 6, i = 0; x < f.x + f.width - 10; i++) {
        const w = 8 + ((i * 7) % 6)
        books.push(<rect key={i} x={x} y={f.y + 6 + ((i * 5) % 7)} width={w} height={f.height - 12 - ((i * 5) % 7)} rx={2} fill={colours[i % colours.length]} />)
        x += w + 3
      }
      body = (
        <>
          <rect className="ft-shelf" x={f.x} y={f.y} width={f.width} height={f.height} rx={6} />
          {books}
        </>
      )
      break
    }
    default: {
      const fill = ids[f.kind] ? `url(#${ids[f.kind]})` : undefined
      body = (
        <>
          <rect className={`ft-base ft-${f.kind}`} x={f.x} y={f.y} width={f.width} height={f.height} rx={12} />
          {fill && <rect x={f.x} y={f.y} width={f.width} height={f.height} rx={12} fill={fill} className="ft-pattern" />}
          {f.kind === 'fireplace' && (
            <path
              className="ft-flame"
              d={`M${cx} ${cy + 18} c-14 -6 -12 -22 0 -34 c2 10 12 12 8 24 c4 -3 5 -7 4 -11 c6 8 2 19 -12 21z`}
            />
          )}
        </>
      )
    }
  }

  // Labels sit on the feature; a shelf or entrance is too thin, so its label goes just outside.
  const labelOutside = f.kind === 'shelf' || f.kind === 'entrance'
  const labelY = labelOutside ? (f.y > 320 ? f.y - 10 : f.y + f.height + 24) : cy + 7
  const labelX = f.kind === 'entrance' ? cx : cx
  return (
    <g className={`feature feature-${f.kind}`}>
      {body}
      <text
        className={`ft-label hand${small && !labelOutside ? ' ft-label-small' : ''}`}
        x={labelX}
        y={labelY}
        transform={vertical && !labelOutside ? `rotate(-90 ${cx} ${cy})` : undefined}
      >
        {f.label}
      </text>
    </g>
  )
}

/* ---------- The plan ---------- */

export default function FloorPlan({
  plan,
  toneOf,
  isSelectable = () => false,
  selected = null,
  onSelect,
  describe,
  selectionStyle = 'fill',
  highlight,
}: Props) {
  const uid = useId().replace(/:/g, '')
  const ids: Record<string, string> = {
    terrace: `cobble-${uid}`,
    deck: `planks-${uid}`,
    kitchen: `tiles-${uid}`,
    garden: `leaves-${uid}`,
    fireplace: `bricks-${uid}`,
    window: `glass-${uid}`,
    counter: `marble-${uid}`,
  }
  const hatchId = `hatch-${uid}`

  function onKey(e: KeyboardEvent, t: PlanTable) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault()
      onSelect?.(t)
    }
  }

  return (
    <svg
      className="floor-plan"
      viewBox={`0 0 ${plan.width} ${plan.height}`}
      role="group"
      aria-label={`Floor plan of ${plan.name}`}
    >
      <defs>
        <pattern id={ids.terrace} width="26" height="20" patternUnits="userSpaceOnUse">
          <rect x="1.5" y="1.5" width="10" height="7" rx="3" className="pt-cobble" />
          <rect x="14.5" y="1.5" width="10" height="7" rx="3" className="pt-cobble" />
          <rect x="8" y="11.5" width="10" height="7" rx="3" className="pt-cobble" />
          <rect x="-5" y="11.5" width="10" height="7" rx="3" className="pt-cobble" />
          <rect x="21" y="11.5" width="10" height="7" rx="3" className="pt-cobble" />
        </pattern>
        <pattern id={ids.deck} width="40" height="14" patternUnits="userSpaceOnUse">
          <path d="M0 13.5H40M20 0V13.5" className="pt-line" />
        </pattern>
        <pattern id={ids.kitchen} width="20" height="20" patternUnits="userSpaceOnUse">
          <rect width="10" height="10" className="pt-tile" />
          <rect x="10" y="10" width="10" height="10" className="pt-tile" />
        </pattern>
        <pattern id={ids.garden} width="28" height="24" patternUnits="userSpaceOnUse">
          <path d="M6 12c3-7 9-7 12 0-3 7-9 7-12 0z" className="pt-leaf" />
          <circle cx="22" cy="4" r="2.5" className="pt-flower" />
        </pattern>
        <pattern id={ids.fireplace} width="24" height="12" patternUnits="userSpaceOnUse">
          <path d="M0 11.5H24M0 5.5H24M6 0V5.5M18 5.5V11.5" className="pt-mortar" />
        </pattern>
        <pattern id={ids.window} width="60" height="60" patternUnits="userSpaceOnUse">
          <path d="M30 0V60" className="pt-mullion" />
        </pattern>
        <pattern id={ids.counter} width="70" height="40" patternUnits="userSpaceOnUse">
          <path d="M0 30c18-10 30 6 46-6s20-4 24-8" className="pt-vein" />
        </pattern>
        <pattern id={hatchId} width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
          <path d="M0 0V8" className="pt-hatch" />
        </pattern>
      </defs>

      <rect className="plan-floor" x={6} y={6} width={plan.width - 12} height={plan.height - 12} rx={22} />

      {plan.features.map((f, i) => (
        <Feature key={i} f={f} ids={ids} />
      ))}

      {plan.tables.map((t) => {
        const s = SHAPES[t.capacity] ?? SHAPES[4]
        const tone = toneOf(t)
        const selectable = isSelectable(t)
        const isSel = selected === t.table_number
        const label = `Table ${t.table_number}, ${t.capacity === 20 ? 'private hall for up to 20' : `${t.capacity} seats`}${describe ? `, ${describe(t)}` : ''}`
        const classes = [
          'tbl',
          `tone-${tone}`,
          selectable && 'is-selectable',
          isSel && (selectionStyle === 'fill' ? 'is-picked' : 'is-ringed'),
          highlight?.has(t.table_number) && 'is-highlight',
        ]
          .filter(Boolean)
          .join(' ')
        return (
          <g key={t.table_number} transform={`translate(${t.x} ${t.y})`}>
            <g
              className={classes}
              role={selectable ? 'button' : 'img'}
              tabIndex={selectable ? 0 : undefined}
              aria-label={label}
              aria-pressed={selectable ? isSel : undefined}
              onClick={selectable ? () => onSelect?.(t) : undefined}
              onKeyDown={selectable ? (e) => onKey(e, t) : undefined}
            >
              <TableShape t={t} s={s} hatchId={hatchId} />
              {isSel && selectionStyle === 'ring' && (
                <rect
                  className="sel-ring"
                  x={-s.w / 2 - 22}
                  y={-s.h / 2 - 22}
                  width={s.w + 44}
                  height={s.h + 44}
                  rx={s.kind === 'round' ? (s.w + 44) / 2 : 20}
                />
              )}
            </g>
          </g>
        )
      })}
    </svg>
  )
}
