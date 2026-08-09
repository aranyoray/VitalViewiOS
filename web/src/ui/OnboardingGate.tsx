import { useState } from 'react';
import { useAppStore } from '../store/appStore';
import { ConsentText, DisclaimerText } from './Disclaimer';

/** Unavoidable first-run gate: disclaimer, then human-subjects consent (§5.1, §2). */
export function OnboardingGate() {
  const settings = useAppStore((s) => s.settings);
  const updateSettings = useAppStore((s) => s.updateSettings);
  const [step, setStep] = useState<'disclaimer' | 'consent'>(
    settings.disclaimerAcknowledged ? 'consent' : 'disclaimer',
  );

  return (
    <div className="overlay">
      <div className="modal">
        <h2>MoniVitals</h2>
        {step === 'disclaimer' ? (
          <>
            <h3>Before you begin</h3>
            <DisclaimerText />
            <div className="row" style={{ marginTop: 16, justifyContent: 'flex-end' }}>
              <button
                className="btn"
                onClick={() => {
                  updateSettings({ disclaimerAcknowledged: true });
                  setStep('consent');
                }}
              >
                I understand — this is not a medical device
              </button>
            </div>
          </>
        ) : (
          <>
            <h3>Consent &amp; data handling</h3>
            <ConsentText />
            <div className="row" style={{ marginTop: 16, justifyContent: 'space-between' }}>
              <button className="btn secondary" onClick={() => setStep('disclaimer')}>
                Back
              </button>
              <button className="btn" onClick={() => updateSettings({ consentAccepted: true })}>
                I agree &amp; will use non-identifying codes
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
