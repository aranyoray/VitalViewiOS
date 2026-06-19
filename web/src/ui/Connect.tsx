import { useAppStore } from '../store/appStore';
import { BleSource } from '../source/BleSource';
import { ErrorFlag } from '../ble/protocol';

export function ConnectScreen() {
  const state = useAppStore((s) => s.connectionState);
  const isMock = useAppStore((s) => s.isMock);
  const streaming = useAppStore((s) => s.streaming);
  const deviceName = useAppStore((s) => s.deviceName);
  const battery = useAppStore((s) => s.batteryPct);
  const errorFlags = useAppStore((s) => s.errorFlags);
  const clockOffsetUs = useAppStore((s) => s.clockOffsetUs);
  const dropped = useAppStore((s) => s.dropped);

  const connectMock = useAppStore((s) => s.connectMock);
  const connectBle = useAppStore((s) => s.connectBle);
  const disconnect = useAppStore((s) => s.disconnect);
  const startStreaming = useAppStore((s) => s.startStreaming);
  const stopStreaming = useAppStore((s) => s.stopStreaming);

  const connected = state === 'connected';
  const bleSupported = BleSource.isSupported();

  return (
    <>
      <div className="card">
        <h2>Connection</h2>
        <p className="muted small">
          The wearable streams over Bluetooth Low Energy. Develop and demo with no hardware using
          Mock mode — every screen works against synthetic data with known ground truth.
        </p>
        <div className="row" style={{ marginTop: 8 }}>
          <button className="btn" disabled={connected} onClick={() => void connectMock()}>
            Connect mock device
          </button>
          <button
            className="btn secondary"
            disabled={connected || !bleSupported}
            onClick={() => void connectBle()}
          >
            Scan &amp; connect (BLE)
          </button>
          <button className="btn secondary" disabled={!connected && state !== 'reconnecting'} onClick={() => void disconnect()}>
            Disconnect
          </button>
          <span className="grow" />
          {connected && !streaming && (
            <button className="btn" onClick={() => void startStreaming()}>
              Start streaming
            </button>
          )}
          {connected && streaming && (
            <button className="btn secondary" onClick={() => void stopStreaming()}>
              Stop streaming
            </button>
          )}
        </div>

        {!bleSupported && (
          <p className="small" style={{ marginTop: 12, color: 'var(--warn)' }}>
            Web Bluetooth is not available in this browser. It works in Chrome / Edge on desktop and
            Chrome on Android, but <strong>not in Safari or on iOS</strong> — that is exactly why a
            native iOS app exists. You can still use Mock mode here.
          </p>
        )}
      </div>

      <div className="card">
        <h3>Status</h3>
        <table>
          <tbody>
            <tr><th>State</th><td>{state}</td></tr>
            <tr><th>Device</th><td>{deviceName ?? '—'}{isMock ? ' (mock)' : ''}</td></tr>
            <tr><th>Battery</th><td>{battery != null ? `${battery}%` : '—'}</td></tr>
            <tr><th>Streaming</th><td>{streaming ? 'yes' : 'no'}</td></tr>
            <tr>
              <th>Clock offset</th>
              <td>{clockOffsetUs != null ? `${(clockOffsetUs / 1000).toFixed(0)} ms (synced)` : 'not synced'}</td>
            </tr>
            <tr>
              <th>Dropped packets</th>
              <td>ECG {dropped.ecg} · BioZ {dropped.bioz} · PPG {dropped.ppg}</td>
            </tr>
            <tr>
              <th>Device flags</th>
              <td>
                {errorFlags === 0 ? 'none' : (
                  <>
                    {errorFlags & ErrorFlag.LEAD_OFF ? <span className="badge bad">lead-off </span> : null}
                    {errorFlags & ErrorFlag.PPG_SATURATION ? <span className="badge warn">PPG saturation </span> : null}
                    {errorFlags & ErrorFlag.BUFFER_OVERFLOW ? <span className="badge bad">buffer overflow</span> : null}
                  </>
                )}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </>
  );
}
