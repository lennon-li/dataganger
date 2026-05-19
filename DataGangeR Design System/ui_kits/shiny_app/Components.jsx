/* ==========================================================
   DataGangeR Shiny app — primitive components
   ========================================================== */

function Brand() {
  return (
    <div className="brand">
      <img src="../../assets/logomark.svg" alt="" />
      <div style={{display: 'flex', flexDirection: 'column', gap: 2}}>
        <span className="name">DataGange<span className="r">R</span></span>
        <span className="tag">v0.1 · beta</span>
      </div>
    </div>
  );
}

function Sidebar({step, setStep}) {
  const steps = [
    {n: '01', label: 'Upload data'},
    {n: '02', label: 'Profile'},
    {n: '03', label: 'Column roles'},
    {n: '04', label: 'Synthesis spec'},
    {n: '05', label: 'Synthesise'},
    {n: '06', label: 'Compare & export'},
  ];
  return (
    <aside className="sidebar">
      <Brand />
      <div>
        <div className="section-label">Workflow</div>
        <ul className="steps">
          {steps.map((s, i) => {
            const done = i < step;
            const active = i === step;
            return (
              <li key={s.n} className={'step ' + (active ? 'active' : '') + (done ? ' done' : '')} onClick={() => setStep(i)}>
                <span className="num">{done ? '✓' : s.n}</span>
                <span className="label">{s.label}</span>
              </li>
            );
          })}
        </ul>
      </div>
      <div className="ds-card">
        <div className="ds-name">health_survey_q4.csv</div>
        <div className="ds-meta">200 rows · 10 columns · 14.2 KB</div>
        <div className="ds-meta" style={{marginTop: 6}}>uploaded 2 min ago</div>
      </div>
    </aside>
  );
}

function MainHeader({eyebrow, title, meta}) {
  return (
    <header className="main-header">
      <div>
        <span className="eyebrow">{eyebrow}</span>
        <h1>{title}</h1>
      </div>
      {meta && <div className="meta">{meta}</div>}
    </header>
  );
}

function Card({title, sub, children, style}) {
  return (
    <section className="card" style={style}>
      {(title || sub) && (
        <div className="card-header">
          {title && <div className="title">{title}</div>}
          {sub && <div className="sub">{sub}</div>}
        </div>
      )}
      {children}
    </section>
  );
}

function Banner({kind = 'info', icon, title, children}) {
  const defaultIcon = {risk: '!', info: 'i', success: '✓'}[kind];
  return (
    <div className={'banner ' + kind}>
      <span className="icon">{icon || defaultIcon}</span>
      <div><b>{title}</b>{children}</div>
    </div>
  );
}

function Chip({kind = 'neutral', dot = true, children}) {
  return (
    <span className={'chip chip-' + kind}>
      {dot && kind !== 'neutral' && <span className="dot"></span>}
      {children}
    </span>
  );
}

function RoleTag({children}) { return <span className="role-tag">{children}</span>; }

function Btn({variant = 'secondary', size, children, onClick}) {
  return <button className={'btn btn-' + variant + (size === 'sm' ? ' btn-sm' : '')} onClick={onClick}>{children}</button>;
}

function Seg({options, value, onChange}) {
  return (
    <div className="seg">
      {options.map(o => (
        <button key={o.value} className={value === o.value ? 'active' : ''} onClick={() => onChange(o.value)}>{o.label}</button>
      ))}
    </div>
  );
}

function DoubleRule() { return <div className="double-rule"></div>; }

function Histo({values, accent = 'real'}) {
  const max = Math.max(...values);
  return (
    <div className="histo">
      {values.map((v, i) => (
        <div key={i} className={'b' + (accent === 'synth' ? ' s' : '')} style={{height: (v / max * 100) + '%'}}></div>
      ))}
    </div>
  );
}

Object.assign(window, {Brand, Sidebar, MainHeader, Card, Banner, Chip, RoleTag, Btn, Seg, DoubleRule, Histo});
