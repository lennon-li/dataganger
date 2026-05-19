/* ============ Compare screen — side-by-side original / synthetic ============ */

const COMPARE_ROWS = [
  {var: 'age',           type: 'numeric', oMean: '54.2',  sMean: '54.4',  delta: '+0.2',   ok: true},
  {var: 'bmi',           type: 'numeric', oMean: '26.3',  sMean: '26.1',  delta: '−0.2',   ok: true},
  {var: 'systolic_bp',   type: 'numeric', oMean: '128.7', sMean: '130.1', delta: '+1.4',   ok: true},
  {var: 'diastolic_bp',  type: 'numeric', oMean: '78.4',  sMean: '79.0',  delta: '+0.6',   ok: true},
  {var: 'smoking_status (Current)', type: 'factor', oMean: '18.0%', sMean: '21.5%', delta: '+3.5pp', ok: false},
  {var: 'province (ON)', type: 'factor', oMean: '38.5%', sMean: '37.0%', delta: '−1.5pp', ok: true},
  {var: 'sex (F)',       type: 'factor', oMean: '52.5%', sMean: '53.0%', delta: '+0.5pp', ok: true},
];

// Tiny histograms — just shapes, no real data
const HISTO_ORIG = [3, 5, 8, 12, 18, 24, 22, 17, 11, 6, 3, 1];
const HISTO_SYNTH = [2, 4, 9, 13, 19, 23, 21, 16, 12, 7, 4, 2];

function ComparePane({kind, label, rows, total, histo}) {
  return (
    <div className={'compare-pane ' + kind}>
      <div className="header"><span className="dot"></span>{label}</div>
      <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 12}}>
        <div style={{fontFamily: 'var(--font-mono)', fontWeight: 500, fontSize: 32, color: 'var(--ink-900)', lineHeight: 1, letterSpacing: '-0.02em', fontFeatureSettings: '"tnum"'}}>{rows}</div>
        <div style={{fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--fg-muted)'}}>rows · 10 cols</div>
      </div>
      <div style={{fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--fg-muted)', textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: 6}}>age — distribution</div>
      <Histo values={histo} accent={kind === 'synth' ? 'synth' : 'real'}/>
    </div>
  );
}

function CompareScreen({onExport}) {
  return (
    <>
      <MainHeader eyebrow="Step 06 · compare & export" title="Read your doppelgänger." meta={<><div>compare_synthetic()</div><div className="v" style={{marginTop: 4}}>seed = 42</div></>}/>

      <Banner kind="success" title="Synthesis complete.">
        200 rows written. <code style={{fontFamily: 'var(--font-mono)'}}>record_id</code> dropped per privacy pre-flag.
        <code style={{fontFamily: 'var(--font-mono)', marginLeft: 6}}>comments</code> dropped per <code style={{fontFamily: 'var(--font-mono)'}}>free_text_strategy = "drop"</code>.
      </Banner>

      <div className="compare-grid" style={{marginBottom: 16}}>
        <ComparePane kind="real" label="Original" rows="200" histo={HISTO_ORIG}/>
        <ComparePane kind="synth" label="Synthetic" rows="200" histo={HISTO_SYNTH}/>
      </div>

      <DoubleRule />

      <Card title="Distribution comparison" sub="per-variable means &amp; modes">
        <table className="data">
          <thead>
            <tr>
              <th>variable</th>
              <th>type</th>
              <th className="real" style={{textAlign: 'right'}}>original</th>
              <th className="synth" style={{textAlign: 'right'}}>synthetic</th>
              <th style={{textAlign: 'right'}}>Δ</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {COMPARE_ROWS.map(r => (
              <tr key={r.var}>
                <td className="name">{r.var}</td>
                <td><Chip kind="neutral" dot={false}>{r.type}</Chip></td>
                <td className="num">{r.oMean}</td>
                <td className="num">{r.sMean}</td>
                <td className="num" style={{color: r.ok ? 'var(--real-700)' : 'var(--risk-500)'}}>{r.delta}</td>
                <td style={{textAlign: 'right'}}><Btn variant="tertiary" size="sm">view →</Btn></td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>

      <Card title="Export bundle">
        <div className="double-rule"></div>
        <div style={{display: 'flex', gap: 18, marginTop: 16, alignItems: 'flex-start'}}>
          <div style={{flex: 1}}>
            <div style={{fontFamily: 'var(--font-mono)', fontSize: 13, color: 'var(--ink-900)', marginBottom: 4}}>health_survey_q4_synth.zip</div>
            <div style={{fontFamily: 'var(--font-sans)', fontSize: 12, color: 'var(--fg-muted)', lineHeight: 1.6}}>
              Includes <code style={{fontFamily: 'var(--font-mono)'}}>synthetic.csv</code>, the comparison report, the synthesis spec as JSON, and an <code style={{fontFamily: 'var(--font-mono)'}}>ai-readme.md</code> the receiver can drop next to the data when prompting an AI.
            </div>
          </div>
          <Btn variant="primary" onClick={onExport}>Download bundle</Btn>
        </div>
      </Card>
    </>
  );
}

window.CompareScreen = CompareScreen;
