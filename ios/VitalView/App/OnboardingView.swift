//
//  OnboardingView.swift
//  VitalView
//
//  First-run gate: the "NOT a medical device" disclaimer and a human-subjects consent
//  acknowledgement. Acceptance is persisted in UserDefaults (via AppModel/AppSettings),
//  so this screen is shown only once. It is unavoidable on first launch.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var disclaimerChecked = false
    @State private var consentChecked = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    section(title: "Not a medical device") {
                        Text("""
                        VitalView is a research, science-fair, and educational tool. It is \
                        NOT a medical device and must not be used for diagnosis or any \
                        clinical decision. Heart rate, SpO₂, pulse arrival time, and blood \
                        pressure are uncalibrated estimates derived from a prototype \
                        wearable and experimental algorithms.
                        """)
                        Toggle(isOn: $disclaimerChecked) {
                            Text("I understand this is not a medical device.")
                                .font(.callout)
                        }
                    }

                    section(title: "Human-subjects research consent") {
                        Text("""
                        If you record sessions involving people, you are responsible for \
                        obtaining appropriate consent and following any applicable study \
                        protocol or institutional guidance. Subjects are identified only by \
                        a non-identifying code; data is stored locally on this device and is \
                        not uploaded anywhere.
                        """)
                        Toggle(isOn: $consentChecked) {
                            Text("I will obtain consent and handle data responsibly.")
                                .font(.callout)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Welcome")
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.acceptOnboarding()
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!(disclaimerChecked && consentChecked))
                .padding()
                .background(.bar)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("VitalView")
                .font(.largeTitle.bold())
            Text("Companion app for an experimental ECG / BioZ / PPG wearable.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}
