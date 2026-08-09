//
//  OnboardingView.swift
//  MoniVitals
//
//  First-run gate: a single, clear "NOT a medical device" acknowledgement. Acceptance is
//  persisted (via AppModel/AppSettings) so this is shown only once. MoniVitals runs
//  entirely on-device by replaying a bundled sample recording — no hardware, nothing
//  measured from the user, no data leaves the phone.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var acknowledged = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MV.s24) {
                    header

                    VStack(alignment: .leading, spacing: MV.s12) {
                        HStack(spacing: MV.s8) {
                            IconBadge(systemName: "exclamationmark.shield", tint: MV.magenta, size: 30)
                            Text("Not a medical device")
                                .font(.headline)
                                .foregroundStyle(MV.navy)
                        }
                        Text("""
                        MoniVitals is a science-fair demo that shows how heart rate, SpO₂, \
                        pulse arrival time, and blood pressure can be estimated from ECG, \
                        PPG, and bioimpedance signals. It replays a bundled sample recording \
                        on-device — nothing is measured from your body and nothing leaves \
                        your phone. It is not a medical device and must never be used for \
                        diagnosis or any health decision.
                        """)
                        .font(.callout)
                        .foregroundStyle(MV.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mvCard()

                    Toggle(isOn: $acknowledged) {
                        Text("I understand this is a demo, not a medical device.")
                            .font(.callout)
                            .foregroundStyle(MV.ink)
                    }
                    .toggleStyle(.switch)
                    .tint(MV.accent)
                    .mvCard()
                }
                .padding(MV.s16)
            }
            .background(MV.bg)

            // Pinned action bar — always visible, no scrolling required.
            VStack(spacing: MV.s8) {
                Button {
                    model.acceptOnboarding()
                } label: {
                    Text("Get started")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!acknowledged)
                .opacity(acknowledged ? 1 : 0.5)

                if !acknowledged {
                    Text("Turn on the switch above to continue.")
                        .font(.caption)
                        .foregroundStyle(MV.inkMuted)
                }
            }
            .padding(MV.s16)
            .background(MV.bg)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MV.s12) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 110)
            Text("Welcome to MoniVitals")
                .font(.largeTitle.bold())
                .foregroundStyle(MV.navy)
            Text("An on-device demo of ECG, PPG & bioimpedance vitals — powered by a bundled sample recording.")
                .font(.callout)
                .foregroundStyle(MV.inkMuted)
        }
    }
}
