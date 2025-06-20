import React, { useState, useEffect } from 'react';
// Application Insights instrumentation
import { ApplicationInsights } from '@microsoft/applicationinsights-web';
import { ReactPlugin } from '@microsoft/applicationinsights-react-js';

const aiConnStr = process.env.REACT_APP_APPLICATIONINSIGHTS_CONNECTION_STRING || window.APPLICATIONINSIGHTS_CONNECTION_STRING;
let appInsights, reactPlugin;
if (aiConnStr) {
  reactPlugin = new ReactPlugin();
  appInsights = new ApplicationInsights({
    config: {
      connectionString: aiConnStr,
      enableAutoRouteTracking: true,
      extensions: [reactPlugin],
      extensionConfig: {
        [reactPlugin.identifier]: { history: window.history }
      }
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
      // Set user/session context for analytics
      const userId = localStorage.getItem('userId') || (Math.random().toString(36).substring(2));
      localStorage.setItem('userId', userId);
      appInsights.setAuthenticatedUserContext(userId);
    }
  }, []);

  // Intentional flaw: does not validate input, can trigger backend error
  const fetchLoan = async () => {
    setError('');
    setResult(null);
    if (appInsights) {
      appInsights.trackEvent({ name: 'LoanLookupRequested', properties: { loanId } });
    }
    try {
      // Propagate correlation ID for full transaction diagnostics
      let headers = {};
      if (appInsights) {
        const traceId = appInsights.context.telemetryTrace.traceID || appInsights.context.telemetryTrace.traceId;
        if (traceId) {
          headers['Request-Id'] = traceId;
        }
      }
      const res = await fetch(`/api/loans/${loanId}`, { headers });
      if (!res.ok) throw new Error('Loan not found');
      const data = await res.json();
      setResult(data);
      if (appInsights) {
        appInsights.trackEvent({ name: 'LoanLookupSuccess', properties: { loanId } });
        appInsights.trackMetric({ name: 'LoanLookupSuccess', average: 1 });
      }
    } catch (err) {
      setError(err.message);
      if (appInsights) {
        appInsights.trackEvent({ name: 'LoanLookupError', properties: { loanId, error: err.message } });
        appInsights.trackMetric({ name: 'LoanLookupError', average: 1 });
      }
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
