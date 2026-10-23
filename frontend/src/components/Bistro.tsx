// Hand-drawn bistro set in the sun: the home page's one illustration.
export default function Bistro() {
  return (
    <svg className="bistro" viewBox="0 0 420 360" role="img" aria-label="A bistro table with two chairs and coffee in the sun">
      <circle cx="318" cy="86" r="54" fill="var(--sun)" />
      <g stroke="var(--sun)" strokeWidth="6" strokeLinecap="round" opacity="0.55">
        <path d="M318 10v-2M386 40l2-2M396 86h2M386 132l2 2M250 40l-2-2M240 86h-2" />
      </g>
      {/* cobbles */}
      <g fill="var(--cream-deep)">
        <rect x="30" y="318" width="54" height="16" rx="8" />
        <rect x="96" y="322" width="70" height="16" rx="8" />
        <rect x="180" y="318" width="60" height="16" rx="8" />
        <rect x="254" y="322" width="72" height="16" rx="8" />
        <rect x="340" y="318" width="50" height="16" rx="8" />
      </g>
      <g fill="none" stroke="var(--ink)" strokeWidth="5" strokeLinecap="round" strokeLinejoin="round">
        {/* table */}
        <ellipse cx="210" cy="200" rx="78" ry="16" fill="var(--paper)" />
        <path d="M210 216v82M176 304h68" />
        {/* left chair */}
        <path d="M62 150c-4 40 2 70 10 92M72 242h64M84 242l-10 62M126 242l8 62M62 150c10-6 22-6 30 4" />
        {/* right chair */}
        <path d="M358 150c4 40-2 70-10 92M348 242h-64M336 242l10 62M294 242l-8 62M358 150c-10-6-22-6-30 4" />
        {/* cups */}
        <path d="M168 170h26v14c0 8-6 12-13 12s-13-4-13-12z" fill="var(--paper)" />
        <path d="M194 176c8 0 8 10 0 10" />
        <path d="M232 158v28M244 162v24" stroke="var(--olive)" />
      </g>
      <circle cx="232" cy="152" r="9" fill="var(--rose)" />
      <circle cx="245" cy="157" r="7" fill="var(--sun)" />
      <path d="M176 160c0-6 6-8 4-14M186 160c0-6 6-8 4-14" stroke="var(--ink-faint)" strokeWidth="3" fill="none" strokeLinecap="round" />
    </svg>
  )
}
