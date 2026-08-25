# Fiducia Flutter

The Fiducia mobile application for Android and iOS, with Flutter desktop shells
for macOS, Windows, and Linux. The lifecycle core is total, deterministic,
runtime-validated, and backed by the same Quint model as the native Rust/GPUI
desktop companion in `../fiducia-desktop.rs`.

The current shell demonstrates the architectural boundary: widgets derive
controls from `AppSnapshot`, while platform/auth/network adapters may only run
an emitted `AppEffect` and return a typed `AppEvent`. They cannot directly
mutate session, tenant, connectivity, or protected-action state.

## Safety contract

- Offline mode is read-only.
- Protected actions require online readiness and explicit confirmation.
- Async completions carry operation generations; stale callbacks cannot change
  state.
- Pending actions are bound to the authority epoch that created them.
- Ambiguous write outcomes block new writes until reconciliation finishes.
- Sign-out revokes local authority before cleanup begins.
- Invalid snapshots fail closed with no session, tenant, or pending action.

See `docs/FORMAL_METHODS.md` and `formal/README.md` for the model, proof bounds,
and honest claim boundary. Delivery is tracked by DEN-3971.

## Develop

```sh
zed install --frozen
zed validate --require-lock
zed run flutter pub get
zed run dart format --output=none --set-exit-if-changed lib test
zed run flutter analyze
zed run flutter test
zed run flutter build apk --debug
zed run flutter build macos --debug
```

The generated project also carries iOS, Linux, and Windows platform shells.
Build those on their native supported hosts before release. This repository is
not published to pub.dev. The Zed package has no cross-repository dependency
yet; its committed lock is therefore intentionally empty and makes that
boundary explicit and frozen.
