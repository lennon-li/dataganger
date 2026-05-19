/* ============ Profile screen — the signature data table ============ */

const PROFILE_ROWS = [
  {name: 'record_id',      type: 'character', miss: '0.0%',  distinct: 200, mean: '—',     range: '—',         role: 'id',         flag: true},
  {name: 'age',            type: 'numeric',   miss: '0.0%',  distinct: 41,  mean: '54.2',  range: '18 – 92',   role: '—',          flag: false},
  {name: 'sex',            type: 'factor',    miss: '0.0%',  distinct: 2,   mean: '—',     range: 'F · M',     role: '—',          flag: false},
  {name: 'bmi',            type: 'numeric',   miss: '7.0%',  distinct: 178, mean: '26.3',  range: '17.4 – 41.8', role: '—',        flag: false},
  {name: 'smoking_status', type: 'haven_labelled', miss: '2.5%', distinct: 3, mean: '—',   range: 'Current · Former · Never', role: '—', flag: false},
  {name: 'systolic_bp',    type: 'numeric',   miss: '3.5%',  distinct: 86,  mean: '128.7', range: '92 – 188',  role: '—',          flag: false},
  {name: 'survey_date',    type: 'Date',      miss: '0.0%',  distinct: 96,  mean: '—',     range: '2024-01-04 → 2024-04-12', role: 'date', flag: false},
  {name: 'province',       type: 'factor',    miss: '0.0%',  distinct: 10,  mean: '—',     range: 'ON · QC · BC · …', role: 'geography', flag: false},
  {name: 'comments',       type: 'character', miss: '64.0%', distinct: 71,  mean: '—',     range: 'free text · μ̄ 42 chars', role: 'free_text', flag: true},
];

function ProfileScreen({onNext}) {
  return (
    <>
      <MainHeader
        eyebrow="Step 02 · profile"
        title="Read the shape of your data."
        meta={<>
          <div>generated 14:22:08</div>
          <div className="v" style={{marginTop: 4}}>profile_data(health_survey_q4)</div>
        </>}
      />

      <div className="stats">
        <div className="stat">
          <div className="label">Rows</div>
          <div className="v">200</div>
          <div className="sub">no all-NA rows</div>
        </div>
        <div className="stat">
          <div className="label">Columns</div>
          <div className="v">10</div>
          <div className="sub">9 typed · 1 free-text</div>
        </div>
        <div className="stat">
          <div className="label">Total missing</div>
          <div className="v">7.7<span style={{fontSize: 18}}>%</span></div>
          <div className="sub">154 / 2,000 cells</div>
        </div>
        <div className="stat">
          <div className="label">Privacy flags</div>
          <div className="v" style={{color: 'var(--risk-500)'}}>2</div>
          <div className="sub">1 ID · 1 free text</div>
        </div>
      </div>

      <Banner kind="risk" title="2 pre-flags detected.">
        DataGangeR will harden the spec defaults: <code style={{fontFamily: 'var(--font-mono)'}}>remove_ids = TRUE</code>, <code style={{fontFamily: 'var(--font-mono)'}}>free_text_strategy = "drop"</code>. You can override on the next step.
      </Banner>

      <Card title="Column-by-column profile" sub="10 columns">
        <table className="data">
          <thead>
            <tr>
              <th>variable</th>
              <th>type</th>
              <th style={{textAlign: 'right'}}>missing</th>
              <th style={{textAlign: 'right'}}>distinct</th>
              <th style={{textAlign: 'right'}}>mean / mode</th>
              <th>range</th>
              <th>role</th>
            </tr>
          </thead>
          <tbody>
            {PROFILE_ROWS.map(r => (
              <tr key={r.name}>
                <td className="name">
                  {r.flag && <span style={{color: 'var(--risk-500)', marginRight: 6}}>●</span>}
                  {r.name}
                </td>
                <td><Chip kind="neutral" dot={false}>{r.type}</Chip></td>
                <td className="num">{r.miss}</td>
                <td className="num">{r.distinct}</td>
                <td className="num">{r.mean}</td>
                <td>{r.range}</td>
                <td>{r.role === '—' ? <span style={{color: 'var(--fg-subtle)'}}>—</span> : <RoleTag>{r.role}</RoleTag>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>
    </>
  );
}

window.ProfileScreen = ProfileScreen;
