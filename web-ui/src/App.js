import React, { useState, useEffect } from 'react';
// Application Insights instrumentation
import { ApplicationInsights } from '@microsoft/applicationinsights-web';

const aiConnStr = process.env.REACT_APP_APPLICATIONINSIGHTS_CONNECTION_STRING || window.APPLICATIONINSIGHTS_CONNECTION_STRING;
let appInsights;
if (aiConnStr) {
  appInsights = new ApplicationInsights({
    config: {
      connectionString: aiConnStr,
      enableAutoRouteTracking: true,
    },
  });
  appInsights.loadAppInsights();
}

function App() {
  const [loanId, setLoanId] = useState('');
  const [error, setError] = useState('');
  const [result, setResult] = useState(null);

  useEffect(() => {
    if (appInsights) {
      appInsights.trackPageView();
    }
  }, []);

  // Intentional flaw: does not validate input, can trigger backend error
  const fetchLoan = async () => {
    setError('');
    setResult(null);
    try {
      const res = await fetch(`/api/loans/${loanId}`);
      if (!res.ok) throw new Error('Loan not found');
      const data = await res.json();
      setResult(data);
    } catch (err) {
      setError(err.message);
    }
  };

  return (
    <div style={{ padding: 40 }}>
      <h1>Mortgage Loan Lookup</h1>
      <input value={loanId} onChange={e => setLoanId(e.target.value)} placeholder="Enter Loan ID" />
      <button onClick={fetchLoan}>Fetch Loan</button>
      {error && <div style={{ color: 'red' }}>{error}</div>}
      {result && <pre>{JSON.stringify(result, null, 2)}</pre>}
    </div>
  );
}

export default App;
