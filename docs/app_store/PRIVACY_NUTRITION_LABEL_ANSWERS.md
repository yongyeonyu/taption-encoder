# Taption Encoder App Privacy Nutrition Label Answers

Status date: 2026-07-03

## Sources Checked

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Google Mobile Ads SDK iOS app-store data disclosure: https://developers.google.com/admob/ios/privacy/data-disclosure
- Google UMP SDK iOS setup/privacy entry-point guidance: https://developers.google.com/admob/ios/privacy
- Local archive manifest evidence:
  - `build/TestFlight-01.00.02-28/TaptionEncoder.xcarchive/Products/Applications/Taption Encoder.app/Frameworks/GoogleMobileAds.framework/PrivacyInfo.xcprivacy`
  - `build/TestFlight-01.00.02-28/TaptionEncoder.xcarchive/Products/Applications/Taption Encoder.app/Frameworks/UserMessagingPlatform.framework/PrivacyInfo.xcprivacy`

Apple requires App Store Connect answers for data collected by the app and by integrated third-party partners. Google states that Google Mobile Ads SDK may collect ad, device, coarse location, usage, performance, crash, and diagnostic data, and that developers remain responsible for keeping App Store disclosures current.

## Current App Data Policy

- Account system: none in this app.
- Custom backend upload: none in this app.
- Video files/photos: selected by the user for local inspection, preview, encoding, and saving. The app does not upload user media to Taption servers in the current build.
- Ads: Google Mobile Ads SDK 13.5.0 and Google User Messaging Platform SDK 3.1.0 are integrated.
- Ad mode: current code requests non-personalized ads by adding `npa=1` to Google ad requests.
- Consent: UMP consent refresh is requested before ad startup; a Privacy & Ads menu entry exposes privacy options when UMP reports that they are available.
- Analytics SDK: no Firebase Analytics, Google Analytics, or custom analytics SDK is integrated in this repository.
- Crash reporting SDK: no Firebase Crashlytics, Sentry, or custom remote crash reporting SDK is integrated in this repository.
- Local diagnostics: `TaptionEncoderLogs/taption-encoder.log` is written inside the app container for local support/debugging. It is not uploaded automatically.

## App Store Connect Answer Set

### Data Used To Track You

| Data Type | Answer | Purpose | Linked To User | Tracking | Evidence |
| --- | --- | --- | --- | --- | --- |
| Identifiers - Device ID | Disclose | Third-Party Advertising, Analytics, Developer Advertising or Marketing | Yes | Yes | GoogleMobileAds `PrivacyInfo.xcprivacy` declares `NSPrivacyCollectedDataTypeDeviceID` with `NSPrivacyCollectedDataTypeTracking=true`. |

Decision note: this is the conservative App Store Connect answer for the current archive because the submitted GoogleMobileAds privacy manifest marks Device ID as tracking. If the product decision remains "non-personalized ads only and no cross-app tracking," verify with App Store Connect/Google whether the current non-personalized configuration changes the required nutrition-label answer before submitting "No tracking." Do not add an ATT purpose string unless the product explicitly introduces personalized ads/cross-app tracking or App Review requires ATT for the active ad configuration.

### Data Linked To You

| Data Type | Answer | Purpose | Tracking |
| --- | --- | --- | --- |
| Location - Coarse Location | Disclose | Third-Party Advertising, Analytics, Developer Advertising or Marketing | No |
| Usage Data - Advertising Data | Disclose | Third-Party Advertising, Analytics, Developer Advertising or Marketing | No |
| Usage Data - Product Interaction | Disclose | Third-Party Advertising, Analytics, Developer Advertising or Marketing | No |
| Identifiers - Device ID | Disclose | Third-Party Advertising, Analytics, Developer Advertising or Marketing | Yes, per current GoogleMobileAds manifest |

Evidence: GoogleMobileAds `PrivacyInfo.xcprivacy` marks Coarse Location, Advertising Data, Product Interaction, and Device ID as linked. UMP also declares Coarse Location/Product Interaction/Performance Data for app functionality, but not linked.

### Data Not Linked To You

| Data Type | Answer | Purpose | Tracking |
| --- | --- | --- | --- |
| Diagnostics - Crash Data | Disclose | Analytics | No |
| Diagnostics - Performance Data | Disclose | Third-Party Advertising, Developer Advertising or Marketing, Analytics; UMP also uses Performance Data for App Functionality | No |
| Diagnostics - Other Diagnostic Data | Disclose | Third-Party Advertising, Developer Advertising or Marketing, Analytics | No |
| Location - Coarse Location | Disclose if App Store Connect asks for the UMP not-linked row separately | App Functionality | No |
| Usage Data - Product Interaction | Disclose if App Store Connect asks for the UMP not-linked row separately | App Functionality | No |

### Data Not Collected By Taption Encoder Itself

Use `No` unless a later feature changes the implementation:

- Contact Info
- Health & Fitness
- Financial Info
- Sensitive Info
- Contacts
- Browsing History
- Search History
- Purchases
- Precise Location
- User ID
- User Content uploaded to Taption servers
- Audio Data uploaded to Taption servers
- Photos or Videos uploaded to Taption servers

Important nuance: user-selected photos/videos are processed locally for encoding. If App Store Connect asks whether media is collected by the app or third-party partners, answer based on current local-only processing: the app accesses user-selected media for app functionality but does not transmit or retain it off device beyond user-controlled local saves.

## App Review / Submission Notes

- Privacy Policy URL: still must be published before final App Review submission.
- Privacy Choices URL: optional, but the app now has an in-app `Privacy & Ads` entry using UMP privacy options.
- ATT purpose string: keep absent while the product policy is non-personalized ads only and no app-side cross-app tracking. Revisit if App Store Connect flags the GoogleMobileAds Device ID tracking manifest during upload/review.
- Advanced Google/AdMob features: if mediation, advanced reporting, impression-level revenue, Firebase Analytics, Crashlytics, or other optional features are added later, update this document and App Store Connect answers before submitting.
