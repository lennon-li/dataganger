/* ============ App shell with click-through navigation ============ */

const {useState} = React;

function App() {
  const [step, setStep] = useState(1); // start on profile (most-used view)
  const [spec, setSpec] = useState({
    purpose: 'ai_programming',
    level: 'marginal',
    n: 200,
    seed: 42,
    rareN: 5,
  });

  function go(delta) { setStep(s => Math.max(0, Math.min(5, s + delta))); }

  const screens = [
    <UploadScreen onNext={() => go(1)} key="up"/>,
    <ProfileScreen key="pr"/>,
    <RolesScreen key="ro"/>,
    <SpecScreen spec={spec} setSpec={setSpec} key="sp"/>,
    <SynthesiseScreen spec={spec} key="sy"/>,
    <CompareScreen onExport={() => alert('Mock: download bundle')} key="co"/>,
  ];

  const labels = ['Upload', 'Profile', 'Roles', 'Spec', 'Synthesise', 'Compare'];

  return (
    <div className="app">
      <Sidebar step={step} setStep={setStep}/>
      <main className="main">
        {screens[step]}
        <div className="action-bar">
          <div className="summary">
            <span><span className="k">file</span> health_survey_q4.csv</span>
            <span><span className="k">step</span> 0{step + 1}/06 — {labels[step]}</span>
            <span><span className="k">purpose</span> {spec.purpose}</span>
          </div>
          <div className="actions">
            <Btn variant="secondary" onClick={() => go(-1)}>← back</Btn>
            {step === 4 ? (
              <Btn variant="primary" onClick={() => go(1)}>Synthesise →</Btn>
            ) : step === 5 ? (
              <Btn variant="primary">Export bundle</Btn>
            ) : (
              <Btn variant="primary" onClick={() => go(1)}>Next →</Btn>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}

/* ============ Placeholder screens ============ */

function RolesScreen() {
  const cols = [
    {n: 'record_id', type: 'character', role: 'id', flag: true},
    {n: 'age', type: 'numeric', role: '—'},
    {n: 'sex', type: 'factor', role: '—'},
    {n: 'bmi', type: 'numeric', role: '—'},
    {n: 'smoking_status', type: 'haven_labelled', role: '—'},
    {n: 'systolic_bp', type: 'numeric', role: '—'},
    {n: 'survey_date', type: 'Date', role: 'date'},
    {n: 'province', type: 'factor', role: 'geography'},
    {n: 'comments', type: 'character', role: 'free_text', flag: true},
  ];
  return (
    <>
      <MainHeader eyebrow="Step 03 · column roles" title="Tell us what each column is."/>
      <Banner kind="info" title="Auto-detected. Edit anything that's wrong.">
        Role assignments influence how columns are coarsened, redacted, or dropped.
      </Banner>
      <Card title="9 of 10 columns assigned" sub="1 unassigned">
        <table className="data">
          <thead><tr><th>variable</th><th>type</th><th>role</th><th></th></tr></thead>
          <tbody>
            {cols.map(c => (
              <tr key={c.n}>
                <td className="name">{c.flag && <span style={{color: 'var(--risk-500)', marginRight: 6}}>●</span>}{c.n}</td>
                <td><Chip kind="neutral" dot={false}>{c.type}</Chip></td>
                <td>
                  {c.role === '—' ? (
                    <span style={{color: 'var(--fg-subtle)', fontFamily: 'var(--font-mono)', fontSize: 12}}>—</span>
                  ) : <RoleTag>{c.role}</RoleTag>}
                </td>
                <td style={{textAlign: 'right'}}><Btn variant="tertiary" size="sm">edit</Btn></td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>
    </>
  );
}

function SynthesiseScreen({spec}) {
  return (
    <>
      <MainHeader eyebrow="Step 05 · synthesise" title="Ready when you are."/>
      <Card>
        <div style={{display: 'flex', gap: 24, alignItems: 'center'}}>
          <div style={{flex: 1}}>
            <div style={{fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--fg-muted)', textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: 6}}>preview command</div>
            <div className="console" style={{padding: '12px 14px'}}>
              <span className="c">synthesize_data(</span>{'\n'}
              {'  '}<span className="k">data</span> = health_survey_q4,{'\n'}
              {'  '}<span className="k">spec</span> = synth_spec(purpose = <span className="v">"{spec.purpose}"</span>, n = <span className="v">{spec.n}</span>, seed = <span className="v">{spec.seed}</span>),{'\n'}
              {'  '}<span className="k">roles</span> = detect_roles(health_survey_q4){'\n'}
              <span className="c">)</span>
            </div>
          </div>
          <div style={{display: 'flex', flexDirection: 'column', gap: 8, minWidth: 200}}>
            <Btn variant="primary">▶ Run synthesise</Btn>
            <Btn variant="secondary" size="sm">Copy as R code</Btn>
            <span style={{fontFamily: 'var(--font-sans)', fontSize: 11, color: 'var(--fg-muted)', textAlign: 'center', marginTop: 4}}>est. 0.4 s</span>
          </div>
        </div>
      </Card>

      <Card title="Pre-synthesis checks" sub="all green">
        <div style={{display: 'flex', flexDirection: 'column', gap: 8}}>
          {[
            ['Spec valid', 'purpose = ai_programming, level = marginal'],
            ['Roles assigned', '9 of 10 columns; 1 unassigned will be treated as nominal'],
            ['Privacy pre-flags handled', 'remove_ids = TRUE · free_text_strategy = "drop"'],
            ['Engine available', 'internal'],
          ].map(([k, v]) => (
            <div key={k} style={{display: 'flex', gap: 10, alignItems: 'center', padding: '6px 0'}}>
              <span style={{color: 'var(--real-500)', fontSize: 16}}>✓</span>
              <span style={{fontFamily: 'var(--font-sans)', fontSize: 13, fontWeight: 500, color: 'var(--ink-900)'}}>{k}</span>
              <span style={{fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--fg-muted)', marginLeft: 'auto'}}>{v}</span>
            </div>
          ))}
        </div>
      </Card>
    </>
  );
}

window.App = App;
window.RolesScreen = RolesScreen;
window.SynthesiseScreen = SynthesiseScreen;

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
