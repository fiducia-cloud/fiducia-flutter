import 'package:fiducia_flutter/src/app/app_lifecycle_machine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'happy path requires auth, tenant selection, sync, and confirmation',
    () {
      final machine = AppLifecycleMachine();

      final launch = machine.dispatch(const AppEvent.launchRequested());
      expect(launch.effect?.kind, AppEffectKind.loadSession);
      machine.dispatch(
        AppEvent.bootstrapSucceeded(
          launch.effect!.operationId,
          authenticated: false,
          hasTenant: false,
          online: true,
        ),
      );
      expect(machine.snapshot.phase, AppPhase.signedOut);

      final signIn = machine.dispatch(const AppEvent.signInRequested());
      machine.dispatch(
        AppEvent.authenticationSucceeded(
          signIn.effect!.operationId,
          hasTenant: false,
          online: true,
        ),
      );
      expect(machine.snapshot.phase, AppPhase.selectingTenant);

      final select = machine.dispatch(const AppEvent.tenantSelected());
      expect(select.effect?.kind, AppEffectKind.synchronize);
      machine.dispatch(AppEvent.operationSucceeded(select.effect!.operationId));
      expect(machine.snapshot.phase, AppPhase.readyOnline);

      machine.dispatch(const AppEvent.actionRequested('rotate-api-key'));
      expect(machine.snapshot.phase, AppPhase.confirmingAction);
      final confirm = machine.dispatch(const AppEvent.actionConfirmed());
      expect(confirm.effect?.kind, AppEffectKind.executeAction);
      expect(confirm.effect?.authorityEpoch, machine.snapshot.authorityEpoch);
      machine.dispatch(
        AppEvent.operationSucceeded(confirm.effect!.operationId),
      );
      expect(machine.snapshot.phase, AppPhase.readyOnline);
      expect(machine.snapshot.pendingAction, isNull);
    },
  );

  test('offline mode is read-only and rejects privileged actions', () {
    final machine = _bootReady();
    machine.dispatch(const AppEvent.connectivityChanged(false));

    expect(machine.snapshot.phase, AppPhase.readyOffline);
    expect(machine.snapshot.capabilities.canReadCachedData, isTrue);
    expect(machine.snapshot.capabilities.canRequestPrivilegedAction, isFalse);
    final rejected = machine.dispatch(
      const AppEvent.actionRequested('rotate-api-key'),
    );
    expect(rejected.disposition, AppTransitionDisposition.rejected);
    expect(rejected.after, rejected.before);
  });

  test(
    'sign-out fences stale async completions and revokes authority first',
    () {
      final machine = AppLifecycleMachine();
      final launch = machine.dispatch(const AppEvent.launchRequested());
      machine.dispatch(
        AppEvent.bootstrapSucceeded(
          launch.effect!.operationId,
          authenticated: false,
          hasTenant: false,
          online: true,
        ),
      );
      final auth = machine.dispatch(const AppEvent.signInRequested());
      final authToken = auth.effect!.operationId;

      final signOut = machine.dispatch(const AppEvent.sessionRevoked());
      expect(machine.snapshot.phase, AppPhase.signingOut);
      expect(machine.snapshot.hasSession, isFalse);
      expect(machine.snapshot.hasTenant, isFalse);

      final stale = machine.dispatch(
        AppEvent.authenticationSucceeded(
          authToken,
          hasTenant: true,
          online: true,
        ),
      );
      expect(stale.disposition, AppTransitionDisposition.stale);
      expect(machine.snapshot.phase, AppPhase.signingOut);

      machine.dispatch(
        AppEvent.operationSucceeded(signOut.effect!.operationId),
      );
      expect(machine.snapshot.phase, AppPhase.signedOut);
      expect(machine.snapshot.hasSession, isFalse);
    },
  );

  test('ambiguous action is blocked until explicit reconciliation', () {
    final machine = _bootReady();
    machine.dispatch(const AppEvent.actionRequested('move-leader'));
    final execute = machine.dispatch(const AppEvent.actionConfirmed());
    final executeToken = execute.effect!.operationId;

    machine.dispatch(const AppEvent.connectivityChanged(false));
    expect(machine.snapshot.phase, AppPhase.reconciliationRequired);
    expect(machine.snapshot.pendingAction?.id, 'move-leader');
    expect(machine.snapshot.capabilities.canRequestPrivilegedAction, isFalse);

    final stale = machine.dispatch(AppEvent.operationSucceeded(executeToken));
    expect(stale.disposition, AppTransitionDisposition.stale);

    final reconnect = machine.dispatch(
      const AppEvent.connectivityChanged(true),
    );
    expect(reconnect.effect?.kind, AppEffectKind.reconcileAction);
    machine.dispatch(
      AppEvent.operationSucceeded(reconnect.effect!.operationId),
    );
    expect(machine.snapshot.phase, AppPhase.readyOnline);
    expect(machine.snapshot.pendingAction, isNull);
  });

  test('corrupt snapshots fail closed without preserving authority', () {
    const corrupt = AppSnapshot.forInvariantTest(
      phase: AppPhase.readyOnline,
      generation: 4,
      authorityEpoch: 2,
      hasSession: false,
      hasTenant: true,
      online: true,
    );
    expect(corrupt.validate(), isNotNull);

    final transition = AppLifecycleMachine.transition(
      corrupt,
      const AppEvent.actionRequested('unsafe'),
    );
    expect(transition.disposition, AppTransitionDisposition.failedClosed);
    expect(transition.after.phase, AppPhase.failed);
    expect(transition.after.hasSession, isFalse);
    expect(transition.after.hasTenant, isFalse);
    expect(transition.after.pendingAction, isNull);
    expect(transition.after.validate(), isNull);
  });

  test('bounded graph is total, deterministic, and invariant preserving', () {
    final visited = <AppSnapshot>{const AppSnapshot.initial()};
    var frontier = <AppSnapshot>{const AppSnapshot.initial()};
    final reachedPhases = <AppPhase>{AppPhase.cold};
    final reachedDispositions = <AppTransitionDisposition>{};

    for (var depth = 0; depth < 9; depth += 1) {
      final next = <AppSnapshot>{};
      for (final snapshot in frontier) {
        for (final event in _boundedEvents(snapshot)) {
          final first = AppLifecycleMachine.transition(snapshot, event);
          final second = AppLifecycleMachine.transition(snapshot, event);
          expect(first, second, reason: 'transition must be deterministic');
          expect(
            first.after.validate(),
            isNull,
            reason: '${snapshot.phase} + ${event.kind}',
          );
          expect(
            first.after.generation,
            greaterThanOrEqualTo(snapshot.generation),
          );
          if (first.disposition == AppTransitionDisposition.rejected ||
              first.disposition == AppTransitionDisposition.stale) {
            expect(first.after, snapshot);
            expect(first.effect, isNull);
          }
          if (first.effect?.kind == AppEffectKind.executeAction) {
            expect(first.after.phase, AppPhase.executingAction);
            expect(first.after.hasSession, isTrue);
            expect(first.after.hasTenant, isTrue);
            expect(first.after.online, isTrue);
            expect(first.effect?.authorityEpoch, first.after.authorityEpoch);
          }
          reachedPhases.add(first.after.phase);
          reachedDispositions.add(first.disposition);
          if (visited.add(first.after)) next.add(first.after);
        }
      }
      frontier = next;
      if (frontier.isEmpty) break;
    }

    expect(reachedPhases, containsAll(AppPhase.values));
    expect(reachedDispositions, containsAll(AppTransitionDisposition.values));
    expect(visited.length, lessThan(5000));
  });
}

AppLifecycleMachine _bootReady() {
  final machine = AppLifecycleMachine();
  final launch = machine.dispatch(const AppEvent.launchRequested());
  final bootstrap = machine.dispatch(
    AppEvent.bootstrapSucceeded(
      launch.effect!.operationId,
      authenticated: true,
      hasTenant: true,
      online: true,
    ),
  );
  machine.dispatch(AppEvent.operationSucceeded(bootstrap.effect!.operationId));
  expect(machine.snapshot.phase, AppPhase.readyOnline);
  return machine;
}

List<AppEvent> _boundedEvents(AppSnapshot snapshot) {
  final current = snapshot.generation;
  final active = snapshot.activeOperationId ?? current;
  return <AppEvent>[
    const AppEvent.launchRequested(),
    AppEvent.bootstrapSucceeded(
      active,
      authenticated: false,
      hasTenant: false,
      online: true,
    ),
    AppEvent.bootstrapSucceeded(
      active,
      authenticated: true,
      hasTenant: false,
      online: true,
    ),
    AppEvent.bootstrapSucceeded(
      active,
      authenticated: true,
      hasTenant: true,
      online: true,
    ),
    AppEvent.bootstrapSucceeded(
      active,
      authenticated: true,
      hasTenant: true,
      online: false,
    ),
    const AppEvent.signInRequested(),
    AppEvent.authenticationSucceeded(active, hasTenant: false, online: true),
    AppEvent.authenticationSucceeded(active, hasTenant: true, online: true),
    const AppEvent.tenantSelected(),
    const AppEvent.connectivityChanged(false),
    const AppEvent.connectivityChanged(true),
    const AppEvent.syncRequested(),
    const AppEvent.actionRequested('bounded-action'),
    const AppEvent.actionRequested(''),
    const AppEvent.actionConfirmed(),
    const AppEvent.actionCancelled(),
    AppEvent.operationSucceeded(active),
    AppEvent.operationSucceeded(current + 7),
    AppEvent.operationFailed(
      active,
      reason: 'bounded failure',
      retryable: false,
    ),
    AppEvent.operationFailed(
      active,
      reason: 'ambiguous bounded failure',
      retryable: true,
      ambiguous: true,
    ),
    const AppEvent.signOutRequested(),
    const AppEvent.sessionRevoked(),
    const AppEvent.recoveryRequested(),
    AppEvent.recoverySucceeded(
      active,
      authenticated: false,
      hasTenant: false,
      online: true,
    ),
    AppEvent.recoverySucceeded(
      active,
      authenticated: true,
      hasTenant: true,
      online: true,
    ),
  ];
}
