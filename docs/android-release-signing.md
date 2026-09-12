# Android release signing

Tracking: GitHub issue #2 and Linear DEN-2843.

Android release builds are intentionally fail-closed. `android/app/build.gradle.kts` configures a release signing identity only when a Gradle task containing `release` is requested, and then requires all of the following runtime values:

| Name | Boundary | Purpose |
| --- | --- | --- |
| `FIDUCIA_ANDROID_KEYSTORE_PATH` | Ephemeral absolute path | Decoded keystore used by Gradle |
| `FIDUCIA_ANDROID_KEYSTORE_PASSWORD` | Protected environment secret | Keystore password |
| `FIDUCIA_ANDROID_KEY_ALIAS` | Protected environment secret | Approved private-key alias |
| `FIDUCIA_ANDROID_KEY_PASSWORD` | Protected environment secret | Private-key password |
| `FIDUCIA_ANDROID_CERT_SHA256` | Protected environment variable | Approved signing-certificate SHA-256 fingerprint |

The Gradle gate rejects missing or blank values, relative or unreadable paths, the standard debug-keystore path or filename, the `androiddebugkey` alias, and any certificate whose fingerprint differs from the approved fingerprint. Debug builds and Android Studio project synchronization do not require these values.

## Repository environment

Before running the production workflow, create or audit the GitHub environment named `android-production` and require human reviewers. Store these values only on that protected environment:

- secret `FIDUCIA_ANDROID_KEYSTORE_BASE64`
- secret `FIDUCIA_ANDROID_KEYSTORE_PASSWORD`
- secret `FIDUCIA_ANDROID_KEY_ALIAS`
- secret `FIDUCIA_ANDROID_KEY_PASSWORD`
- non-secret variable `FIDUCIA_ANDROID_EXPECTED_SHA256`

Do not commit a keystore, `key.properties`, passwords, decrypted environment files, or workflow logs containing secret values. The repository already ignores Android keystore formats and `key.properties`; the workflow decodes the keystore only into the ephemeral runner directory and removes it in an `always()` cleanup step.

`FIDUCIA_ANDROID_EXPECTED_SHA256` must be the independently verified Google developer-verification certificate fingerprint. It may contain colons and mixed case; both Gradle and the workflow normalize it to 64 uppercase hexadecimal digits before comparison.

## Verification workflows

`.github/workflows/android-release-signing.yml` runs on relevant pull requests and main-branch changes. It:

1. runs the dependency-free static contract tests;
2. proves an ordinary debug APK builds without release credentials;
3. proves a release AAB fails when signing values are absent;
4. creates an ephemeral CI-only key, builds a signed test AAB, verifies its JAR signature, and proves the embedded certificate fingerprint matches the supplied value.

`.github/workflows/android-production-aab.yml` is manual-only and bound to the `android-production` environment. It has read-only repository permissions, uses actions pinned to full commit SHAs, builds no store upload, retains the signed AAB and non-secret provenance for 30 days, and records:

- exact commit SHA;
- exact workflow-run URL;
- AAB SHA-256 digest;
- signing-certificate SHA-256 fingerprint;
- `jarsigner` verification output.

Android application signing certificates are commonly self-signed, so `jarsigner` is used to prove archive integrity while `keytool -printcert -jarfile` and the explicit fingerprint comparison establish signing identity. Trust is anchored in the reviewed `FIDUCIA_ANDROID_EXPECTED_SHA256` value rather than the runner's generic Java trust store.

## Production-readiness boundary

Merging the repository changes does not by itself establish production readiness. The issue remains open until a credentialed maintainer has:

1. confirmed the intended Google developer-verification fingerprint through an independent authenticated channel;
2. configured protected-environment reviewers and values;
3. run the manual production workflow and retained its provenance;
4. uploaded the resulting artifact to an internal test track through an attended release process;
5. completed provider read-back and confirmed the observed package and certificate fingerprint.

The workflow deliberately performs no Google Play upload and does not create, rotate, or publish a production signing key.
