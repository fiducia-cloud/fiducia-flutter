/// Total, deterministic application lifecycle for Fiducia mobile and Flutter
/// desktop clients.
///
/// The state machine is the sole owner of application-visible authority and
/// privileged-action intent. Platform, authentication, network, storage, and
/// API calls are represented as effects. Their completions must carry the
/// exact operation generation that produced them; stale completions stutter.
library;

enum AppPhase {
  cold,
  bootstrapping,
  signedOut,
  authenticating,
  selectingTenant,
  synchronizing,
  readyOnline,
  readyOffline,
  confirmingAction,
  executingAction,
  reconciliationRequired,
  reconcilingAction,
  recovering,
  signingOut,
  failed,
}

enum AppOperation {
  bootstrap,
  authenticate,
  synchronize,
  executeAction,
  reconcileAction,
  recover,
  signOut,
}

enum AppEffectKind {
  loadSession,
  authenticate,
  synchronize,
  executeAction,
  reconcileAction,
  recoverSession,
  clearSession,
}

enum AppEventKind {
  launchRequested,
  bootstrapSucceeded,
  signInRequested,
  authenticationSucceeded,
  tenantSelected,
  connectivityChanged,
  syncRequested,
  actionRequested,
  actionConfirmed,
  actionCancelled,
  operationSucceeded,
  operationFailed,
  signOutRequested,
  sessionRevoked,
  recoveryRequested,
  recoverySucceeded,
}

enum AppTransitionDisposition { applied, rejected, stale, failedClosed }

class PendingAction {
  const PendingAction({required this.id, required this.authorityEpoch});

  final String id;
  final int authorityEpoch;

  @override
  bool operator ==(Object other) =>
      other is PendingAction &&
      id == other.id &&
      authorityEpoch == other.authorityEpoch;

  @override
  int get hashCode => Object.hash(id, authorityEpoch);
}

class AppCapabilities {
  const AppCapabilities({
    required this.canLaunch,
    required this.canSignIn,
    required this.canSelectTenant,
    required this.canReadCachedData,
    required this.canRequestPrivilegedAction,
    required this.canConfirmAction,
    required this.canCancelAction,
    required this.canRecover,
    required this.canSignOut,
  });

  final bool canLaunch;
  final bool canSignIn;
  final bool canSelectTenant;
  final bool canReadCachedData;
  final bool canRequestPrivilegedAction;
  final bool canConfirmAction;
  final bool canCancelAction;
  final bool canRecover;
  final bool canSignOut;
}

class AppSnapshot {
  const AppSnapshot._({
    required this.phase,
    required this.generation,
    required this.authorityEpoch,
    required this.hasSession,
    required this.hasTenant,
    required this.online,
    this.activeOperation,
    this.activeOperationId,
    this.pendingAction,
    this.failure,
  });

  const AppSnapshot.initial()
    : this._(
        phase: AppPhase.cold,
        generation: 0,
        authorityEpoch: 0,
        hasSession: false,
        hasTenant: false,
        online: false,
      );

  /// Test-only construction seam for proving that corrupt snapshots fail
  /// closed. Production code must obtain snapshots from the machine.
  const AppSnapshot.forInvariantTest({
    required this.phase,
    required this.generation,
    required this.authorityEpoch,
    required this.hasSession,
    required this.hasTenant,
    required this.online,
    this.activeOperation,
    this.activeOperationId,
    this.pendingAction,
    this.failure,
  });

  static const int maxPortableCounter = 0x1fffffffffffff;

  final AppPhase phase;
  final int generation;
  final int authorityEpoch;
  final bool hasSession;
  final bool hasTenant;
  final bool online;
  final AppOperation? activeOperation;
  final int? activeOperationId;
  final PendingAction? pendingAction;
  final String? failure;

  bool get isBusy => switch (phase) {
    AppPhase.bootstrapping ||
    AppPhase.authenticating ||
    AppPhase.synchronizing ||
    AppPhase.executingAction ||
    AppPhase.reconcilingAction ||
    AppPhase.recovering ||
    AppPhase.signingOut => true,
    _ => false,
  };

  AppCapabilities get capabilities => AppCapabilities(
    canLaunch: phase == AppPhase.cold,
    canSignIn: phase == AppPhase.signedOut,
    canSelectTenant: phase == AppPhase.selectingTenant,
    canReadCachedData: const {
      AppPhase.readyOnline,
      AppPhase.readyOffline,
      AppPhase.confirmingAction,
      AppPhase.executingAction,
      AppPhase.reconciliationRequired,
      AppPhase.reconcilingAction,
    }.contains(phase),
    canRequestPrivilegedAction: phase == AppPhase.readyOnline,
    canConfirmAction: phase == AppPhase.confirmingAction,
    canCancelAction: phase == AppPhase.confirmingAction,
    canRecover: phase == AppPhase.failed,
    canSignOut: const {
      AppPhase.selectingTenant,
      AppPhase.synchronizing,
      AppPhase.readyOnline,
      AppPhase.readyOffline,
      AppPhase.confirmingAction,
      AppPhase.executingAction,
      AppPhase.reconciliationRequired,
      AppPhase.reconcilingAction,
      AppPhase.failed,
    }.contains(phase),
  );

  /// Runtime invariant checked before and after every transition.
  String? validate() {
    if (generation < 0 || generation > maxPortableCounter) {
      return 'generation is outside the portable non-negative domain';
    }
    if (authorityEpoch < 0 || authorityEpoch > maxPortableCounter) {
      return 'authority epoch is outside the portable non-negative domain';
    }

    final hasCompleteOperation =
        activeOperation != null && activeOperationId != null;
    if (isBusy != hasCompleteOperation) {
      return 'transitional phases require exactly one active operation';
    }
    if ((activeOperation == null) != (activeOperationId == null)) {
      return 'active operation and id must appear together';
    }
    if (activeOperationId != null &&
        (activeOperationId! <= 0 || activeOperationId != generation)) {
      return 'active operation id must equal the current generation';
    }

    final operationMatchesPhase = switch (phase) {
      AppPhase.bootstrapping => activeOperation == AppOperation.bootstrap,
      AppPhase.authenticating => activeOperation == AppOperation.authenticate,
      AppPhase.synchronizing => activeOperation == AppOperation.synchronize,
      AppPhase.executingAction => activeOperation == AppOperation.executeAction,
      AppPhase.reconcilingAction =>
        activeOperation == AppOperation.reconcileAction,
      AppPhase.recovering => activeOperation == AppOperation.recover,
      AppPhase.signingOut => activeOperation == AppOperation.signOut,
      _ => activeOperation == null,
    };
    if (!operationMatchesPhase) {
      return 'active operation is incompatible with the current phase';
    }

    if (hasTenant && !hasSession) {
      return 'tenant authority requires an authenticated session';
    }
    final requiresSession = const {
      AppPhase.selectingTenant,
      AppPhase.synchronizing,
      AppPhase.readyOnline,
      AppPhase.readyOffline,
      AppPhase.confirmingAction,
      AppPhase.executingAction,
      AppPhase.reconciliationRequired,
      AppPhase.reconcilingAction,
    }.contains(phase);
    if (requiresSession != hasSession) {
      return 'session presence is incompatible with the current phase';
    }
    final requiresTenant = const {
      AppPhase.synchronizing,
      AppPhase.readyOnline,
      AppPhase.readyOffline,
      AppPhase.confirmingAction,
      AppPhase.executingAction,
      AppPhase.reconciliationRequired,
      AppPhase.reconcilingAction,
    }.contains(phase);
    if (requiresTenant != hasTenant) {
      return 'tenant selection is incompatible with the current phase';
    }
    if (phase == AppPhase.selectingTenant && hasTenant) {
      return 'tenant-selection phase cannot already hold tenant authority';
    }

    final requiresOnline = const {
      AppPhase.synchronizing,
      AppPhase.readyOnline,
      AppPhase.confirmingAction,
      AppPhase.executingAction,
      AppPhase.reconcilingAction,
    }.contains(phase);
    if (requiresOnline && !online) {
      return 'the current phase requires verified online connectivity';
    }
    if (phase == AppPhase.readyOffline && online) {
      return 'offline readiness cannot claim online connectivity';
    }

    final requiresPendingAction = const {
      AppPhase.confirmingAction,
      AppPhase.executingAction,
      AppPhase.reconciliationRequired,
      AppPhase.reconcilingAction,
    }.contains(phase);
    if (requiresPendingAction != (pendingAction != null)) {
      return 'pending action presence is incompatible with the current phase';
    }
    if (pendingAction != null &&
        (pendingAction!.id.isEmpty ||
            pendingAction!.id.length > 128 ||
            pendingAction!.authorityEpoch != authorityEpoch)) {
      return 'pending action is not bound to current authority';
    }
    if ((phase == AppPhase.failed) != (failure != null)) {
      return 'failure details must exist exactly in the failed phase';
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is AppSnapshot &&
      phase == other.phase &&
      generation == other.generation &&
      authorityEpoch == other.authorityEpoch &&
      hasSession == other.hasSession &&
      hasTenant == other.hasTenant &&
      online == other.online &&
      activeOperation == other.activeOperation &&
      activeOperationId == other.activeOperationId &&
      pendingAction == other.pendingAction &&
      failure == other.failure;

  @override
  int get hashCode => Object.hash(
    phase,
    generation,
    authorityEpoch,
    hasSession,
    hasTenant,
    online,
    activeOperation,
    activeOperationId,
    pendingAction,
    failure,
  );
}

class AppEvent {
  const AppEvent._(
    this.kind, {
    this.operationId,
    this.authenticated = false,
    this.hasTenant = false,
    this.online = false,
    this.actionId,
    this.reason,
    this.retryable = false,
    this.ambiguous = false,
  });

  const AppEvent.launchRequested() : this._(AppEventKind.launchRequested);
  const AppEvent.bootstrapSucceeded(
    int operationId, {
    required bool authenticated,
    required bool hasTenant,
    required bool online,
  }) : this._(
         AppEventKind.bootstrapSucceeded,
         operationId: operationId,
         authenticated: authenticated,
         hasTenant: hasTenant,
         online: online,
       );
  const AppEvent.signInRequested() : this._(AppEventKind.signInRequested);
  const AppEvent.authenticationSucceeded(
    int operationId, {
    required bool hasTenant,
    required bool online,
  }) : this._(
         AppEventKind.authenticationSucceeded,
         operationId: operationId,
         authenticated: true,
         hasTenant: hasTenant,
         online: online,
       );
  const AppEvent.tenantSelected() : this._(AppEventKind.tenantSelected);
  const AppEvent.connectivityChanged(bool online)
    : this._(AppEventKind.connectivityChanged, online: online);
  const AppEvent.syncRequested() : this._(AppEventKind.syncRequested);
  const AppEvent.actionRequested(String actionId)
    : this._(AppEventKind.actionRequested, actionId: actionId);
  const AppEvent.actionConfirmed() : this._(AppEventKind.actionConfirmed);
  const AppEvent.actionCancelled() : this._(AppEventKind.actionCancelled);
  const AppEvent.operationSucceeded(int operationId)
    : this._(AppEventKind.operationSucceeded, operationId: operationId);
  const AppEvent.operationFailed(
    int operationId, {
    required String reason,
    required bool retryable,
    bool ambiguous = false,
  }) : this._(
         AppEventKind.operationFailed,
         operationId: operationId,
         reason: reason,
         retryable: retryable,
         ambiguous: ambiguous,
       );
  const AppEvent.signOutRequested() : this._(AppEventKind.signOutRequested);
  const AppEvent.sessionRevoked() : this._(AppEventKind.sessionRevoked);
  const AppEvent.recoveryRequested() : this._(AppEventKind.recoveryRequested);
  const AppEvent.recoverySucceeded(
    int operationId, {
    required bool authenticated,
    required bool hasTenant,
    required bool online,
  }) : this._(
         AppEventKind.recoverySucceeded,
         operationId: operationId,
         authenticated: authenticated,
         hasTenant: hasTenant,
         online: online,
       );

  final AppEventKind kind;
  final int? operationId;
  final bool authenticated;
  final bool hasTenant;
  final bool online;
  final String? actionId;
  final String? reason;
  final bool retryable;
  final bool ambiguous;

  @override
  bool operator ==(Object other) =>
      other is AppEvent &&
      kind == other.kind &&
      operationId == other.operationId &&
      authenticated == other.authenticated &&
      hasTenant == other.hasTenant &&
      online == other.online &&
      actionId == other.actionId &&
      reason == other.reason &&
      retryable == other.retryable &&
      ambiguous == other.ambiguous;

  @override
  int get hashCode => Object.hash(
    kind,
    operationId,
    authenticated,
    hasTenant,
    online,
    actionId,
    reason,
    retryable,
    ambiguous,
  );
}

class AppEffect {
  const AppEffect({
    required this.kind,
    required this.operation,
    required this.operationId,
    this.actionId,
    this.authorityEpoch,
  });

  final AppEffectKind kind;
  final AppOperation operation;
  final int operationId;
  final String? actionId;
  final int? authorityEpoch;

  @override
  bool operator ==(Object other) =>
      other is AppEffect &&
      kind == other.kind &&
      operation == other.operation &&
      operationId == other.operationId &&
      actionId == other.actionId &&
      authorityEpoch == other.authorityEpoch;

  @override
  int get hashCode =>
      Object.hash(kind, operation, operationId, actionId, authorityEpoch);
}

class AppTransition {
  const AppTransition({
    required this.before,
    required this.after,
    required this.disposition,
    required this.reason,
    this.effect,
  });

  final AppSnapshot before;
  final AppSnapshot after;
  final AppTransitionDisposition disposition;
  final String reason;
  final AppEffect? effect;

  @override
  bool operator ==(Object other) =>
      other is AppTransition &&
      before == other.before &&
      after == other.after &&
      disposition == other.disposition &&
      reason == other.reason &&
      effect == other.effect;

  @override
  int get hashCode => Object.hash(before, after, disposition, reason, effect);
}

class AppLifecycleMachine {
  AppLifecycleMachine([this._snapshot = const AppSnapshot.initial()]);

  AppSnapshot _snapshot;

  AppSnapshot get snapshot => _snapshot;

  AppTransition dispatch(AppEvent event) {
    final result = transition(_snapshot, event);
    _snapshot = result.after;
    return result;
  }

  /// Pure, total transition relation for every snapshot and event value.
  static AppTransition transition(AppSnapshot current, AppEvent event) {
    final violation = current.validate();
    if (violation != null) {
      return _failedClosed(current, 'invalid lifecycle snapshot: $violation');
    }

    final result = switch (event.kind) {
      AppEventKind.launchRequested => _launch(current),
      AppEventKind.bootstrapSucceeded => _bootstrapSucceeded(current, event),
      AppEventKind.signInRequested => _signIn(current),
      AppEventKind.authenticationSucceeded => _authenticationSucceeded(
        current,
        event,
      ),
      AppEventKind.tenantSelected => _tenantSelected(current),
      AppEventKind.connectivityChanged => _connectivityChanged(current, event),
      AppEventKind.syncRequested => _syncRequested(current),
      AppEventKind.actionRequested => _actionRequested(current, event),
      AppEventKind.actionConfirmed => _actionConfirmed(current),
      AppEventKind.actionCancelled => _actionCancelled(current),
      AppEventKind.operationSucceeded => _operationSucceeded(current, event),
      AppEventKind.operationFailed => _operationFailed(current, event),
      AppEventKind.signOutRequested => _signOut(current, 'sign-out requested'),
      AppEventKind.sessionRevoked => _signOut(current, 'session revoked'),
      AppEventKind.recoveryRequested => _recoveryRequested(current),
      AppEventKind.recoverySucceeded => _recoverySucceeded(current, event),
    };

    final afterViolation = result.after.validate();
    if (afterViolation != null) {
      return _failedClosed(
        current,
        'transition produced invalid lifecycle snapshot: $afterViolation',
      );
    }
    return result;
  }

  static AppTransition _launch(AppSnapshot current) {
    if (current.phase != AppPhase.cold) {
      return _rejected(current, 'launch is available only from cold state');
    }
    return _begin(
      current,
      phase: AppPhase.bootstrapping,
      operation: AppOperation.bootstrap,
      effectKind: AppEffectKind.loadSession,
      hasSession: false,
      hasTenant: false,
      online: false,
      pendingAction: null,
      authorityEpoch: current.authorityEpoch,
      reason: 'session bootstrap started',
    );
  }

  static AppTransition _bootstrapSucceeded(
    AppSnapshot current,
    AppEvent event,
  ) {
    if (!_matches(current, AppOperation.bootstrap, event.operationId)) {
      return _stale(current, 'stale bootstrap completion ignored');
    }
    return _establishRecoveredAuthority(
      current,
      authenticated: event.authenticated,
      hasTenant: event.hasTenant,
      online: event.online,
      reason: 'session bootstrap completed',
    );
  }

  static AppTransition _signIn(AppSnapshot current) {
    if (current.phase != AppPhase.signedOut) {
      return _rejected(current, 'sign-in requires signed-out state');
    }
    return _begin(
      current,
      phase: AppPhase.authenticating,
      operation: AppOperation.authenticate,
      effectKind: AppEffectKind.authenticate,
      hasSession: false,
      hasTenant: false,
      online: current.online,
      pendingAction: null,
      authorityEpoch: current.authorityEpoch,
      reason: 'authentication started',
    );
  }

  static AppTransition _authenticationSucceeded(
    AppSnapshot current,
    AppEvent event,
  ) {
    if (!_matches(current, AppOperation.authenticate, event.operationId)) {
      return _stale(current, 'stale authentication completion ignored');
    }
    return _establishRecoveredAuthority(
      current,
      authenticated: true,
      hasTenant: event.hasTenant,
      online: event.online,
      reason: 'authentication completed',
    );
  }

  static AppTransition _tenantSelected(AppSnapshot current) {
    if (current.phase != AppPhase.selectingTenant) {
      return _rejected(current, 'tenant selection is not currently available');
    }
    final nextAuthority = _nextAuthority(current);
    if (nextAuthority == null) {
      return _failedClosed(current, 'authority epoch exhausted');
    }
    final selected = _stable(
      current,
      phase: current.online ? AppPhase.readyOnline : AppPhase.readyOffline,
      hasSession: true,
      hasTenant: true,
      online: current.online,
      authorityEpoch: nextAuthority,
    );
    if (!current.online) {
      return _applied(current, selected, 'tenant selected for offline mode');
    }
    return _begin(
      selected,
      phase: AppPhase.synchronizing,
      operation: AppOperation.synchronize,
      effectKind: AppEffectKind.synchronize,
      hasSession: true,
      hasTenant: true,
      online: true,
      pendingAction: null,
      authorityEpoch: nextAuthority,
      reason: 'tenant selected; synchronization started',
    ).withBefore(current);
  }

  static AppTransition _connectivityChanged(
    AppSnapshot current,
    AppEvent event,
  ) {
    if (current.online == event.online) {
      return _rejected(current, 'connectivity state is unchanged');
    }
    if (event.online) {
      return switch (current.phase) {
        AppPhase.signedOut || AppPhase.selectingTenant => _applied(
          current,
          _stable(
            current,
            phase: current.phase,
            hasSession: current.hasSession,
            hasTenant: current.hasTenant,
            online: true,
            authorityEpoch: current.authorityEpoch,
          ),
          'connectivity restored',
        ),
        AppPhase.readyOffline => _beginSync(
          current,
          'connectivity restored; synchronization started',
        ),
        AppPhase.reconciliationRequired => _beginReconciliation(
          current,
          'connectivity restored; action reconciliation started',
        ),
        _ => _rejected(
          current,
          'connectivity restoration is not applicable in this phase',
        ),
      };
    }

    return switch (current.phase) {
      AppPhase.signedOut || AppPhase.selectingTenant => _applied(
        current,
        _stable(
          current,
          phase: current.phase,
          hasSession: current.hasSession,
          hasTenant: current.hasTenant,
          online: false,
          authorityEpoch: current.authorityEpoch,
        ),
        'connectivity lost',
      ),
      AppPhase.readyOnline => _applied(
        current,
        _stable(
          current,
          phase: AppPhase.readyOffline,
          hasSession: true,
          hasTenant: true,
          online: false,
          authorityEpoch: current.authorityEpoch,
        ),
        'entered controlled read-only offline mode',
      ),
      AppPhase.synchronizing => _fenceToStable(
        current,
        phase: AppPhase.readyOffline,
        hasSession: true,
        hasTenant: true,
        online: false,
        pendingAction: null,
        reason: 'sync fenced after connectivity loss',
      ),
      AppPhase.confirmingAction => _applied(
        current,
        _stable(
          current,
          phase: AppPhase.readyOffline,
          hasSession: true,
          hasTenant: true,
          online: false,
          authorityEpoch: current.authorityEpoch,
        ),
        'unexecuted action cancelled before entering offline mode',
      ),
      AppPhase.executingAction || AppPhase.reconcilingAction => _fenceToStable(
        current,
        phase: AppPhase.reconciliationRequired,
        hasSession: true,
        hasTenant: true,
        online: false,
        pendingAction: current.pendingAction,
        reason: 'ambiguous action fenced pending online reconciliation',
      ),
      AppPhase.authenticating => _fenceToStable(
        current,
        phase: AppPhase.signedOut,
        hasSession: false,
        hasTenant: false,
        online: false,
        pendingAction: null,
        reason: 'authentication fenced after connectivity loss',
      ),
      _ => _rejected(
        current,
        'connectivity loss is not applicable in this phase',
      ),
    };
  }

  static AppTransition _syncRequested(AppSnapshot current) {
    if (current.phase != AppPhase.readyOnline) {
      return _rejected(current, 'manual sync requires online readiness');
    }
    return _beginSync(current, 'manual synchronization started');
  }

  static AppTransition _actionRequested(AppSnapshot current, AppEvent event) {
    final actionId = event.actionId?.trim() ?? '';
    if (current.phase != AppPhase.readyOnline) {
      return _rejected(current, 'privileged actions require online readiness');
    }
    if (actionId.isEmpty || actionId.length > 128) {
      return _rejected(current, 'action id must contain 1 to 128 characters');
    }
    return _applied(
      current,
      _stable(
        current,
        phase: AppPhase.confirmingAction,
        hasSession: true,
        hasTenant: true,
        online: true,
        authorityEpoch: current.authorityEpoch,
        pendingAction: PendingAction(
          id: actionId,
          authorityEpoch: current.authorityEpoch,
        ),
      ),
      'privileged action awaits explicit confirmation',
    );
  }

  static AppTransition _actionConfirmed(AppSnapshot current) {
    if (current.phase != AppPhase.confirmingAction ||
        current.pendingAction == null ||
        !current.online) {
      return _rejected(
        current,
        'confirmation requires a bound online pending action',
      );
    }
    return _begin(
      current,
      phase: AppPhase.executingAction,
      operation: AppOperation.executeAction,
      effectKind: AppEffectKind.executeAction,
      hasSession: true,
      hasTenant: true,
      online: true,
      pendingAction: current.pendingAction,
      authorityEpoch: current.authorityEpoch,
      reason: 'confirmed privileged action started',
    );
  }

  static AppTransition _actionCancelled(AppSnapshot current) {
    if (current.phase != AppPhase.confirmingAction) {
      return _rejected(
        current,
        'no unexecuted action is awaiting confirmation',
      );
    }
    return _applied(
      current,
      _stable(
        current,
        phase: AppPhase.readyOnline,
        hasSession: true,
        hasTenant: true,
        online: true,
        authorityEpoch: current.authorityEpoch,
      ),
      'pending action cancelled without execution',
    );
  }

  static AppTransition _operationSucceeded(
    AppSnapshot current,
    AppEvent event,
  ) {
    if (current.activeOperation == null ||
        current.activeOperationId != event.operationId) {
      return _stale(current, 'stale operation success ignored');
    }
    return switch (current.activeOperation!) {
      AppOperation.synchronize => _applied(
        current,
        _stable(
          current,
          phase: AppPhase.readyOnline,
          hasSession: true,
          hasTenant: true,
          online: true,
          authorityEpoch: current.authorityEpoch,
        ),
        'synchronization completed',
      ),
      AppOperation.executeAction => _applied(
        current,
        _stable(
          current,
          phase: AppPhase.readyOnline,
          hasSession: true,
          hasTenant: true,
          online: true,
          authorityEpoch: current.authorityEpoch,
        ),
        'privileged action completed',
      ),
      AppOperation.reconcileAction => _applied(
        current,
        _stable(
          current,
          phase: AppPhase.readyOnline,
          hasSession: true,
          hasTenant: true,
          online: true,
          authorityEpoch: current.authorityEpoch,
        ),
        'ambiguous action reconciled',
      ),
      AppOperation.signOut => _applied(
        current,
        _stable(
          current,
          phase: AppPhase.signedOut,
          hasSession: false,
          hasTenant: false,
          online: current.online,
          authorityEpoch: current.authorityEpoch,
        ),
        'local and remote sign-out completed',
      ),
      AppOperation.bootstrap ||
      AppOperation.authenticate ||
      AppOperation.recover => _rejected(
        current,
        'typed completion is required for this operation',
      ),
    };
  }

  static AppTransition _operationFailed(AppSnapshot current, AppEvent event) {
    if (current.activeOperation == null ||
        current.activeOperationId != event.operationId) {
      return _stale(current, 'stale operation failure ignored');
    }
    final reason = _controlledReason(event.reason);
    return switch (current.activeOperation!) {
      AppOperation.authenticate => _applied(
        current,
        _stable(
          current,
          phase: AppPhase.signedOut,
          hasSession: false,
          hasTenant: false,
          online: current.online,
          authorityEpoch: current.authorityEpoch,
        ),
        'authentication failed without granting authority',
      ),
      AppOperation.synchronize when event.retryable => _applied(
        current,
        _stable(
          current,
          phase: AppPhase.readyOffline,
          hasSession: true,
          hasTenant: true,
          online: false,
          authorityEpoch: current.authorityEpoch,
        ),
        'sync failure entered controlled read-only offline mode: $reason',
      ),
      AppOperation.executeAction when event.ambiguous =>
        current.online
            ? _beginReconciliation(
                current,
                'ambiguous action result requires reconciliation',
              )
            : _fenceToStable(
                current,
                phase: AppPhase.reconciliationRequired,
                hasSession: true,
                hasTenant: true,
                online: false,
                pendingAction: current.pendingAction,
                reason: 'ambiguous action awaits online reconciliation',
              ),
      AppOperation.executeAction => _applied(
        current,
        _stable(
          current,
          phase: current.online ? AppPhase.readyOnline : AppPhase.readyOffline,
          hasSession: true,
          hasTenant: true,
          online: current.online,
          authorityEpoch: current.authorityEpoch,
        ),
        'action failed definitively without committing: $reason',
      ),
      AppOperation.signOut => _applied(
        current,
        _stable(
          current,
          phase: AppPhase.signedOut,
          hasSession: false,
          hasTenant: false,
          online: current.online,
          authorityEpoch: current.authorityEpoch,
        ),
        'local authority remains revoked despite cleanup failure',
      ),
      AppOperation.bootstrap ||
      AppOperation.synchronize ||
      AppOperation.reconcileAction ||
      AppOperation.recover => _failedClosed(current, reason),
    };
  }

  static AppTransition _signOut(AppSnapshot current, String reason) {
    if (current.phase == AppPhase.cold ||
        current.phase == AppPhase.signedOut ||
        current.phase == AppPhase.signingOut) {
      return _rejected(current, 'sign-out is not applicable in this phase');
    }
    final nextAuthority = _nextAuthority(current);
    if (nextAuthority == null) {
      return _failedClosed(current, 'authority epoch exhausted');
    }
    return _begin(
      current,
      phase: AppPhase.signingOut,
      operation: AppOperation.signOut,
      effectKind: AppEffectKind.clearSession,
      hasSession: false,
      hasTenant: false,
      online: current.online,
      pendingAction: null,
      authorityEpoch: nextAuthority,
      reason: '$reason; local authority revoked before cleanup',
    );
  }

  static AppTransition _recoveryRequested(AppSnapshot current) {
    if (current.phase != AppPhase.failed) {
      return _rejected(current, 'recovery requires controlled failed state');
    }
    return _begin(
      current,
      phase: AppPhase.recovering,
      operation: AppOperation.recover,
      effectKind: AppEffectKind.recoverSession,
      hasSession: false,
      hasTenant: false,
      online: false,
      pendingAction: null,
      authorityEpoch: current.authorityEpoch,
      reason: 'explicit recovery started',
    );
  }

  static AppTransition _recoverySucceeded(AppSnapshot current, AppEvent event) {
    if (!_matches(current, AppOperation.recover, event.operationId)) {
      return _stale(current, 'stale recovery completion ignored');
    }
    return _establishRecoveredAuthority(
      current,
      authenticated: event.authenticated,
      hasTenant: event.hasTenant,
      online: event.online,
      reason: 'explicit recovery completed',
    );
  }

  static AppTransition _establishRecoveredAuthority(
    AppSnapshot current, {
    required bool authenticated,
    required bool hasTenant,
    required bool online,
    required String reason,
  }) {
    if (!authenticated) {
      return _applied(
        current,
        _stable(
          current,
          phase: AppPhase.signedOut,
          hasSession: false,
          hasTenant: false,
          online: online,
          authorityEpoch: current.authorityEpoch,
        ),
        '$reason without an authenticated session',
      );
    }
    final nextAuthority = _nextAuthority(current);
    if (nextAuthority == null) {
      return _failedClosed(current, 'authority epoch exhausted');
    }
    if (!hasTenant) {
      return _applied(
        current,
        _stable(
          current,
          phase: AppPhase.selectingTenant,
          hasSession: true,
          hasTenant: false,
          online: online,
          authorityEpoch: nextAuthority,
        ),
        '$reason; tenant selection required',
      );
    }
    final authorized = _stable(
      current,
      phase: online ? AppPhase.readyOnline : AppPhase.readyOffline,
      hasSession: true,
      hasTenant: true,
      online: online,
      authorityEpoch: nextAuthority,
    );
    if (!online) {
      return _applied(
        current,
        authorized,
        '$reason into controlled read-only offline mode',
      );
    }
    return _begin(
      authorized,
      phase: AppPhase.synchronizing,
      operation: AppOperation.synchronize,
      effectKind: AppEffectKind.synchronize,
      hasSession: true,
      hasTenant: true,
      online: true,
      pendingAction: null,
      authorityEpoch: nextAuthority,
      reason: '$reason; synchronization started',
    ).withBefore(current);
  }

  static AppTransition _beginSync(AppSnapshot current, String reason) => _begin(
    current,
    phase: AppPhase.synchronizing,
    operation: AppOperation.synchronize,
    effectKind: AppEffectKind.synchronize,
    hasSession: true,
    hasTenant: true,
    online: true,
    pendingAction: null,
    authorityEpoch: current.authorityEpoch,
    reason: reason,
  );

  static AppTransition _beginReconciliation(
    AppSnapshot current,
    String reason,
  ) => _begin(
    current,
    phase: AppPhase.reconcilingAction,
    operation: AppOperation.reconcileAction,
    effectKind: AppEffectKind.reconcileAction,
    hasSession: true,
    hasTenant: true,
    online: true,
    pendingAction: current.pendingAction,
    authorityEpoch: current.authorityEpoch,
    reason: reason,
  );

  static bool _matches(
    AppSnapshot current,
    AppOperation operation,
    int? operationId,
  ) =>
      current.activeOperation == operation &&
      current.activeOperationId == operationId;

  static int? _nextAuthority(AppSnapshot current) =>
      current.authorityEpoch >= AppSnapshot.maxPortableCounter
      ? null
      : current.authorityEpoch + 1;

  static AppTransition _begin(
    AppSnapshot current, {
    required AppPhase phase,
    required AppOperation operation,
    required AppEffectKind effectKind,
    required bool hasSession,
    required bool hasTenant,
    required bool online,
    required PendingAction? pendingAction,
    required int authorityEpoch,
    required String reason,
  }) {
    if (current.generation >= AppSnapshot.maxPortableCounter) {
      return _failedClosed(current, 'operation generation exhausted');
    }
    final operationId = current.generation + 1;
    final after = AppSnapshot._(
      phase: phase,
      generation: operationId,
      authorityEpoch: authorityEpoch,
      hasSession: hasSession,
      hasTenant: hasTenant,
      online: online,
      activeOperation: operation,
      activeOperationId: operationId,
      pendingAction: pendingAction,
    );
    return _applied(
      current,
      after,
      reason,
      effect: AppEffect(
        kind: effectKind,
        operation: operation,
        operationId: operationId,
        actionId: pendingAction?.id,
        authorityEpoch: pendingAction?.authorityEpoch,
      ),
    );
  }

  static AppTransition _fenceToStable(
    AppSnapshot current, {
    required AppPhase phase,
    required bool hasSession,
    required bool hasTenant,
    required bool online,
    required PendingAction? pendingAction,
    required String reason,
  }) {
    if (current.generation >= AppSnapshot.maxPortableCounter) {
      return _failedClosed(current, 'operation generation exhausted');
    }
    return _applied(
      current,
      AppSnapshot._(
        phase: phase,
        generation: current.generation + 1,
        authorityEpoch: current.authorityEpoch,
        hasSession: hasSession,
        hasTenant: hasTenant,
        online: online,
        pendingAction: pendingAction,
      ),
      reason,
    );
  }

  static AppSnapshot _stable(
    AppSnapshot current, {
    required AppPhase phase,
    required bool hasSession,
    required bool hasTenant,
    required bool online,
    required int authorityEpoch,
    PendingAction? pendingAction,
  }) => AppSnapshot._(
    phase: phase,
    generation: current.generation,
    authorityEpoch: authorityEpoch,
    hasSession: hasSession,
    hasTenant: hasTenant,
    online: online,
    pendingAction: pendingAction,
  );

  static AppTransition _applied(
    AppSnapshot before,
    AppSnapshot after,
    String reason, {
    AppEffect? effect,
  }) => AppTransition(
    before: before,
    after: after,
    disposition: AppTransitionDisposition.applied,
    reason: reason,
    effect: effect,
  );

  static AppTransition _rejected(AppSnapshot current, String reason) =>
      AppTransition(
        before: current,
        after: current,
        disposition: AppTransitionDisposition.rejected,
        reason: reason,
      );

  static AppTransition _stale(AppSnapshot current, String reason) =>
      AppTransition(
        before: current,
        after: current,
        disposition: AppTransitionDisposition.stale,
        reason: reason,
      );

  static AppTransition _failedClosed(AppSnapshot current, String reason) {
    final generation = current.generation < AppSnapshot.maxPortableCounter
        ? current.generation + 1
        : current.generation;
    final authority = current.authorityEpoch < AppSnapshot.maxPortableCounter
        ? current.authorityEpoch + 1
        : current.authorityEpoch;
    return AppTransition(
      before: current,
      after: AppSnapshot._(
        phase: AppPhase.failed,
        generation: generation,
        authorityEpoch: authority,
        hasSession: false,
        hasTenant: false,
        online: false,
        failure: _controlledReason(reason),
      ),
      disposition: AppTransitionDisposition.failedClosed,
      reason: 'lifecycle failed closed',
    );
  }

  static String _controlledReason(String? reason) {
    final normalized = (reason ?? '').trim();
    if (normalized.isEmpty) return 'unspecified controlled failure';
    return normalized.length <= 256 ? normalized : normalized.substring(0, 256);
  }
}

extension on AppTransition {
  AppTransition withBefore(AppSnapshot before) => AppTransition(
    before: before,
    after: after,
    disposition: disposition,
    reason: reason,
    effect: effect,
  );
}
