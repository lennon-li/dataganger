/* ============ Upload screen ============ */

function UploadScreen({onNext}) {
  return (
    <>
      <MainHeader eyebrow="Step 01 · upload" title="Bring in a dataset." meta={<><div>4 supported formats</div><div className="v" style={{marginTop: 4}}>csv · xlsx · sas7bdat · xpt</div></>}/>

      <Banner kind="info" title="Sharing original data?">
        Synthetic data <b>reduces</b> direct disclosure risk. It is not a substitute for a formal privacy assessment. Review the comparison and privacy warnings before sharing externally.
      </Banner>

      <div className="upload" onClick={onNext}>
        <div className="icon">+</div>
        <div className="primary">Drop a file to begin</div>
        <div className="secondary">or <a style={{color: 'var(--synth-700)', textDecoration: 'underline'}}>choose from your computer</a></div>
        <div className="formats">CSV · XLSX · SAS7BDAT · XPT  ·  up to 200 MB</div>
      </div>

      <Card title="Recent" sub="last 7 days">
        <table className="data">
          <thead><tr><th>filename</th><th>rows × cols</th><th>last opened</th><th></th></tr></thead>
          <tbody>
            <tr><td className="name">health_survey_q4.csv</td><td>200 × 10</td><td>2 min ago</td><td style={{textAlign: 'right'}}><Btn variant="tertiary" size="sm">Open →</Btn></td></tr>
            <tr><td className="name">claims_2026_apr.xlsx</td><td>300 × 9</td><td>yesterday</td><td style={{textAlign: 'right'}}><Btn variant="tertiary" size="sm">Open →</Btn></td></tr>
            <tr><td className="name">registry_baseline.sas7bdat</td><td>150 × 10</td><td>3 days ago</td><td style={{textAlign: 'right'}}><Btn variant="tertiary" size="sm">Open →</Btn></td></tr>
          </tbody>
        </table>
      </Card>
    </>
  );
}

window.UploadScreen = UploadScreen;
