/** Reusable disclaimer + consent copy. No diagnostic/clinical language anywhere (§2.1). */

export function DisclaimerText() {
  return (
    <div className="small">
      <p>
        <strong>MoniVitals is a research / educational tool, not a medical device.</strong> It does
        not diagnose, treat, or monitor any medical condition and must not be used for clinical
        decisions. The heart-rate, SpO₂, pulse-arrival-time and blood-pressure values are
        uncalibrated <em>estimates</em> derived from experimental signal processing.
      </p>
      <p>
        The ECG is a single-arm bipolar lead that only <em>approximates</em> Lead I. SpO₂ and the
        cuffless blood-pressure estimate require per-subject calibration and are shown for
        demonstration only.
      </p>
    </div>
  );
}

export function ConsentText() {
  return (
    <div className="small">
      <p>
        This app records biosignals for a validation study. Subjects are identified only by a
        non-identifying <strong>subject code</strong> — never by name, date of birth, or contact
        information. Data is stored <strong>locally on this device</strong> and is exported only
        when you explicitly choose to.
      </p>
      <p>
        By continuing you confirm that any person whose data you record has given informed consent
        to participate, and that you will not enter personally identifying information.
      </p>
    </div>
  );
}
