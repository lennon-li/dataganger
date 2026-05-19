/* ============ Spec screen — the synthesis specification form ============ */

function SpecScreen({spec, setSpec, onNext}) {
  const purposes = [
    {value: 'ai_programming',  label: 'AI programming',  blurb: 'Share with an AI assistant. Marginal · coarsened dates · rare merge.'},
    {value: 'shiny_prototype', label: 'Shiny prototype', blurb: 'Drop into a dev app. Same defaults as ai_programming.'},
    {value: 'teaching',        label: 'Teaching',        blurb: 'Classroom safe. Stripped of inter-variable relationships.'},
    {value: 'model_prototype', label: 'Model prototype', blurb: 'Keeps moderate correlations. v0.1 still marginal — flagged.'},
    {value: 'internal_hifi',   label: 'Internal hi-fi',  blurb: 'High fidelity. Requires acknowledge_risk = TRUE.'},
    {value: 'safer_external',  label: 'Safer external',  blurb: 'Schema only. Generic names, aggregated geography, n=10 rare merge.'},
  ];
  return (
    <>
      <MainHeader eyebrow="Step 04 · synthesis spec" title="Dial in the doppelgänger."/>

      <Card title="Purpose" sub="presets the synthesis defaults">
        <div style={{display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10}}>
          {purposes.map(p => (
            <label key={p.value} style={{display: 'flex', gap: 12, padding: 12, background: spec.purpose === p.value ? 'var(--synth-50)' : 'var(--paper-50)', border: '1px solid ' + (spec.purpose === p.value ? 'var(--synth-300)' : 'var(--paper-300)'), borderRadius: 4, cursor: 'pointer'}}>
              <input type="radio" name="purpose" checked={spec.purpose === p.value} onChange={() => setSpec({...spec, purpose: p.value})} style={{accentColor: 'var(--synth-500)', marginTop: 3}}/>
              <div>
                <div style={{fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--ink-900)', fontWeight: 500}}>{p.value}</div>
                <div style={{fontFamily: 'var(--font-sans)', fontSize: 12, color: 'var(--fg-muted)', marginTop: 2, lineHeight: 1.4}}>{p.blurb}</div>
              </div>
            </label>
          ))}
        </div>
      </Card>

      <Card title="Synthesis level">
        <div className="field">
          <Seg
            value={spec.level}
            onChange={v => setSpec({...spec, level: v})}
            options={[{value: 'schema', label: 'Schema only'}, {value: 'marginal', label: 'Marginal'}, {value: 'hifi', label: 'Hi-fi (engine req.)'}]}
          />
          <span className="help">Marginal: per-column distributions, drawn independently. Inter-variable correlations are not preserved in v0.1.</span>
        </div>

        <div style={{display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16}}>
          <div className="field">
            <label>Rows to synthesise (n)</label>
            <input className="input" defaultValue={spec.n}/>
            <span className="help">Defaults to nrow(original). Set higher to over-sample.</span>
          </div>
          <div className="field">
            <label>Seed</label>
            <input className="input" defaultValue={spec.seed}/>
            <span className="help">For reproducibility.</span>
          </div>
          <div className="field">
            <label>Rare level merge — min n</label>
            <input className="input" defaultValue={spec.rareN}/>
            <span className="help">Levels under this count get folded into "Other".</span>
          </div>
          <div className="field">
            <label>Free text strategy</label>
            <select className="select" defaultValue="drop"><option>drop</option><option>redact</option></select>
            <span className="help">Pre-flagged as drop because of <code style={{fontFamily: 'var(--font-mono)'}}>comments</code>.</span>
          </div>
        </div>
      </Card>

      <Card title="Spec preview" sub="will write to disk on synthesise">
        <div className="console">
          <span className="h">── DataGangeR Synthesis Spec ──────────────────────</span>{'\n\n'}
          <span className="c">── Purpose</span>{'\n'}
          <span className="v">"{spec.purpose}"</span>{'\n\n'}
          <span className="c">── Level</span>{'\n'}
          <span className="v">"{spec.level}"</span>{'\n\n'}
          <span className="c">── Key settings</span>{'\n'}
          • Name strategy:       <span className="v">"preserve"</span>{'\n'}
          • Coarsen dates:       <span className="v">TRUE</span>{'\n'}
          • Merge rare levels:   <span className="v">TRUE</span>  <span className="c">(min_n = {spec.rareN})</span>{'\n'}
          • Free text strategy:  <span className="v">"drop"</span>{'\n'}
          • Geography strategy:  <span className="v">"coarsen"</span>{'\n'}
          • Preserve correls:    <span className="v">"low"</span>{'\n'}
          • Engine required:     <span className="v">"internal"</span>{'\n\n'}
          <span className="c">── Seed</span>{'\n'}
          <span className="v">{spec.seed}</span>
        </div>
      </Card>
    </>
  );
}

window.SpecScreen = SpecScreen;
