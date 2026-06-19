import { useEffect, useState } from 'react';
import { useAppStore } from './store/appStore';
import { OnboardingGate } from './ui/OnboardingGate';
import { ConnectScreen } from './ui/Connect';
import { DashboardScreen } from './ui/Dashboard';
import { RecorderScreen } from './ui/Recorder';
import { CalibrationScreen } from './ui/Calibration';
import { GatingScreen } from './ui/Gating';
import { ReviewScreen } from './ui/Review';
import { SettingsScreen } from './ui/Settings';
import { AboutScreen } from './ui/About';

type Tab = 'connect' | 'dashboard' | 'recorder' | 'calibration' | 'gating' | 'review' | 'settings' | 'about';
const TABS: { id: Tab; label: string }[] = [
  { id: 'connect', label: 'Connect' },
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
  const [tab, setTab] = useState<Tab>('connect');

  useEffect(() => {
    const root = document.documentElement;
    const resolve = () =>
      settings.theme === 'system'
        ? window.matchMedia('(prefers-color-scheme: light)').matches
          ? 'light'
          : 'dark'
        : settings.theme;
    const apply = () => {
      const t = resolve();
      if (t === 'light') root.setAttribute('data-theme', 'light');
      else root.removeAttribute('data-theme');
    };
    apply();
    const mq = window.matchMedia('(prefers-color-scheme: light)');
    mq.addEventListener('change', apply);
    return () => mq.removeEventListener('change', apply);
  }, [settings.theme]);

  useEffect(() => {
    void refreshSubjects();
  }, [refreshSubjects]);

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
        {tab === 'connect' && <ConnectScreen />}
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
  const state = useAppStore((s) => s.connectionState);
  const battery = useAppStore((s) => s.batteryPct);
  const deviceName = useAppStore((s) => s.deviceName);
  const isMock = useAppStore((s) => s.isMock);
  const dropped = useAppStore((s) => s.dropped);
  const totalDropped = dropped.ecg + dropped.bioz + dropped.ppg;

  const connected = state === 'connected';
  return (
    <header className="topbar">
      <span className="brand">VitalView</span>
      <span className="disclaimer-chip">Not a medical device</span>
      <span className="spacer" />
      <span className="status">
        {deviceName && <span>{deviceName}{isMock ? ' (mock)' : ''}</span>}
        <span className={`badge ${connected ? 'good' : state === 'reconnecting' ? 'warn' : ''}`}>{state}</span>
        {totalDropped > 0 && <span className="badge warn">dropped {totalDropped}</span>}
        {battery != null && <span>{battery}%</span>}
      </span>
    </header>
  );
}
