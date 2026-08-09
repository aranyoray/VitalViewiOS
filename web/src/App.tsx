import { useEffect, useState } from 'react';
import { useAppStore } from './store/appStore';
import { OnboardingGate } from './ui/OnboardingGate';
import { DashboardScreen } from './ui/Dashboard';
import { RecorderScreen } from './ui/Recorder';
import { CalibrationScreen } from './ui/Calibration';
import { GatingScreen } from './ui/Gating';
import { ReviewScreen } from './ui/Review';
import { SettingsScreen } from './ui/Settings';
import { AboutScreen } from './ui/About';

type Tab = 'dashboard' | 'recorder' | 'calibration' | 'gating' | 'review' | 'settings' | 'about';
const TABS: { id: Tab; label: string }[] = [
  { id: 'dashboard', label: 'Dashboard' },
  { id: 'recorder', label: 'Record' },
  { id: 'calibration', label: 'Calibration' },
  { id: 'gating', label: 'Gating' },
  { id: 'review', label: 'Review' },
  { id: 'settings', label: 'Settings' },
  { id: 'about', label: 'About' },
];

export default function App() {
  const settings = useAppStore((s) => s.settings);
  const refreshSubjects = useAppStore((s) => s.refreshSubjects);
  const autoStart = useAppStore((s) => s.autoStart);
  const [tab, setTab] = useState<Tab>('dashboard');

  useEffect(() => {
    void refreshSubjects();
  }, [refreshSubjects]);

  // Standalone: connect the synthetic source and start streaming once on mount.
  useEffect(() => {
    void autoStart();
  }, [autoStart]);

  const onboarded = settings.disclaimerAcknowledged && settings.consentAccepted;

  return (
    <div className="app">
      <TopBar />
      <nav className="tabs" aria-label="Sections">
        {TABS.map((t) => (
          <button key={t.id} aria-current={tab === t.id} onClick={() => setTab(t.id)}>
            {t.label}
          </button>
        ))}
      </nav>
      <main className="content">
        {tab === 'dashboard' && <DashboardScreen />}
        {tab === 'recorder' && <RecorderScreen />}
        {tab === 'calibration' && <CalibrationScreen />}
        {tab === 'gating' && <GatingScreen />}
        {tab === 'review' && <ReviewScreen />}
        {tab === 'settings' && <SettingsScreen />}
        {tab === 'about' && <AboutScreen />}
      </main>
      {!onboarded && <OnboardingGate />}
    </div>
  );
}

function TopBar() {
  const streaming = useAppStore((s) => s.streaming);
  const battery = useAppStore((s) => s.batteryPct);
  const deviceName = useAppStore((s) => s.deviceName);
  const isTunableSignal = useAppStore((s) => s.isTunableSignal);
  const dropped = useAppStore((s) => s.dropped);
  const totalDropped = dropped.ecg + dropped.bioz + dropped.ppg;

  return (
    <header className="topbar">
      <span className="brand-lockup">
        <img src="/logo.png" alt="MoniVitals" className="brand-logo" />
        <span className="brand">MoniVitals</span>
      </span>
      <span className="disclaimer-chip">Not a medical device</span>
      <span className="spacer" />
      <span className="status">
        {deviceName && <span>{deviceName}{isTunableSignal ? ' (demo)' : ''}</span>}
        <span className={`badge ${streaming ? 'good' : ''}`}>{streaming ? 'Live' : 'Paused'}</span>
        {totalDropped > 0 && <span className="badge warn">dropped {totalDropped}</span>}
        {battery != null && <span>{battery}%</span>}
      </span>
    </header>
  );
}
