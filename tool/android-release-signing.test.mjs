import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

function repositoryFile(path) {
  return readFile(new URL(`../${path}`, import.meta.url), 'utf8');
}

function assertPinnedActions(workflow) {
  const usesLines = workflow
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.startsWith('uses:'));
  assert.ok(usesLines.length >= 3, 'workflow should use pinned reusable actions');
  for (const line of usesLines) {
    assert.match(
      line,
      /^uses:\s+[^@\s]+@[0-9a-f]{40}(?:\s+#.*)?$/,
      `action must be pinned to a full commit SHA: ${line}`,
    );
  }
}

test('Gradle release signing is fail-closed and never falls back to debug keys', async () => {
  const gradle = await repositoryFile('android/app/build.gradle.kts');

  assert.doesNotMatch(gradle, /signingConfigs\.getByName\("debug"\)/);
  assert.doesNotMatch(gradle, /key\.properties/);
  assert.match(gradle, /releaseTaskRequested/);
  assert.match(gradle, /taskName\.contains\("release", ignoreCase = true\)/);

  for (const variable of [
    'FIDUCIA_ANDROID_KEYSTORE_PATH',
    'FIDUCIA_ANDROID_KEYSTORE_PASSWORD',
    'FIDUCIA_ANDROID_KEY_ALIAS',
    'FIDUCIA_ANDROID_KEY_PASSWORD',
    'FIDUCIA_ANDROID_CERT_SHA256',
  ]) {
    assert.match(gradle, new RegExp(variable));
  }

  assert.match(gradle, /requestedFile\.isAbsolute/);
  assert.match(gradle, /keystore\.isFile/);
  assert.match(gradle, /keystore\.canRead\(\)/);
  assert.match(gradle, /debug\.keystore/);
  assert.match(gradle, /androiddebugkey/);
  assert.match(gradle, /actualFingerprint != expectedFingerprint/);
  assert.match(gradle, /signingConfig = signingConfigs\.getByName\("release"\)/);
});

test('PR verification proves both the missing-secret failure and a signed test AAB', async () => {
  const workflow = await repositoryFile('.github/workflows/android-release-signing.yml');

  assert.match(workflow, /pull_request:/);
  assert.match(workflow, /push:/);
  assert.match(workflow, /node --test tool\/android-release-signing\.test\.mjs/);
  assert.match(workflow, /flutter build appbundle --release/);
  assert.match(workflow, /flutter build apk --debug/);
  assert.match(workflow, /keytool -genkeypair/);
  assert.match(workflow, /jarsigner -verify -strict/);
  assert.match(workflow, /DEN-2843: Android release signing requires non-blank/);
  assertPinnedActions(workflow);
});

test('production AAB workflow is manual, protected, least-privilege, and non-publishing', async () => {
  const workflow = await repositoryFile('.github/workflows/android-production-aab.yml');

  assert.match(workflow, /workflow_dispatch:/);
  assert.doesNotMatch(workflow, /\n\s+pull_request:/);
  assert.doesNotMatch(workflow, /\n\s+push:/);
  assert.match(workflow, /permissions:\n\s+contents: read/);
  assert.match(workflow, /environment: android-production/);
  assert.match(workflow, /secrets\.FIDUCIA_ANDROID_KEYSTORE_BASE64/);
  assert.match(workflow, /secrets\.FIDUCIA_ANDROID_KEYSTORE_PASSWORD/);
  assert.match(workflow, /secrets\.FIDUCIA_ANDROID_KEY_ALIAS/);
  assert.match(workflow, /secrets\.FIDUCIA_ANDROID_KEY_PASSWORD/);
  assert.match(workflow, /vars\.FIDUCIA_ANDROID_EXPECTED_SHA256/);
  assert.match(workflow, /flutter build appbundle --release/);
  assert.match(workflow, /jarsigner -verify -strict/);
  assert.match(workflow, /certificate-sha256=/);
  assert.match(workflow, /retention-days: 30/);
  assert.doesNotMatch(workflow, /google-play|play-store|upload-to-play|publish-release/i);
  assertPinnedActions(workflow);
});
