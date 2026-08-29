import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'src/app/app_lifecycle_machine.dart';
import 'src/app/deep_link_admission.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final appLinks = AppLinks();
  runApp(FiduciaApp(linkStream: appLinks.stringLinkStream));
}

class FiduciaApp extends StatelessWidget {
  const FiduciaApp({super.key, this.linkStream});

  final Stream<String>? linkStream;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Fiducia',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff62d9c2),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xff071411),
      useMaterial3: true,
    ),
    home: LifecycleConsole(linkStream: linkStream),
  );
}

/// Thin demonstration shell. Real platform/auth/API adapters replace
/// [_runEffect], but they may never mutate application state directly.
class LifecycleConsole extends StatefulWidget {
  const LifecycleConsole({super.key, this.linkStream});

  final Stream<String>? linkStream;

  @override
  State<LifecycleConsole> createState() => _LifecycleConsoleState();
}

class _LifecycleConsoleState extends State<LifecycleConsole> {
  final AppLifecycleMachine _machine = AppLifecycleMachine();
  final DeepLinkAdmissionMachine _deepLinks = DeepLinkAdmissionMachine();
  final List<String> _audit = <String>[];
  StreamSubscription<String>? _linkSubscription;
  bool _handoffScheduled = false;

  @override
  void initState() {
    super.initState();
    _linkSubscription = widget.linkStream?.listen(
      _captureDeepLink,
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        setState(() {
          _audit.insert(0, 'deepLink: rejected — platform stream error');
        });
      },
    );
    scheduleMicrotask(() => _dispatch(const AppEvent.launchRequested()));
  }

  @override
  void dispose() {
    unawaited(_linkSubscription?.cancel());
    super.dispose();
  }

  void _captureDeepLink(String raw) {
    final begin = _deepLinks.begin(raw);
    _recordDeepLink(begin);
    final effect = begin.effect;
    if (effect == null) return;
    scheduleMicrotask(() {
      if (!mounted) return;
      final completed = _deepLinks.complete(effect.generation);
      _recordDeepLink(completed);
      _scheduleDeepLinkHandoff();
    });
  }

  void _recordDeepLink(DeepLinkTransition transition) {
    if (!mounted) return;
    setState(() {
      _audit.insert(
        0,
        'deepLink: ${transition.disposition.name} — '
        '${transition.reason.wireName}',
      );
      if (_audit.length > 8) _audit.removeLast();
    });
  }

  void _scheduleDeepLinkHandoff() {
    if (_handoffScheduled ||
        !_deepLinks.snapshot.canHandoff ||
        !_machine.snapshot.capabilities.canRequestPrivilegedAction) {
      return;
    }
    _handoffScheduled = true;
    scheduleMicrotask(() {
      _handoffScheduled = false;
      if (!mounted || !_deepLinks.snapshot.canHandoff) return;
      final handoff = _deepLinks.handoffTo(_machine);
      _recordDeepLink(handoff.admission);
      if (handoff.lifecycle != null) {
        setState(() {
          _audit.insert(
            0,
            'deepLink lifecycle: '
            '${handoff.lifecycle!.disposition.name} — '
            '${handoff.lifecycle!.reason}',
          );
          if (_audit.length > 8) _audit.removeLast();
        });
      }
    });
  }

  void _dispatch(AppEvent event) {
    final transition = _machine.dispatch(event);
    if (!mounted) return;
    setState(() {
      _audit.insert(
        0,
        '${event.kind.name}: ${transition.disposition.name} — '
        '${transition.reason}',
      );
      if (_audit.length > 8) _audit.removeLast();
    });
    final effect = transition.effect;
    if (effect != null) unawaited(_runEffect(effect));
    _scheduleDeepLinkHandoff();
  }

  Future<void> _runEffect(AppEffect effect) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    switch (effect.kind) {
      case AppEffectKind.loadSession:
        _dispatch(
          AppEvent.bootstrapSucceeded(
            effect.operationId,
            authenticated: false,
            hasTenant: false,
            online: true,
          ),
        );
      case AppEffectKind.authenticate:
        _dispatch(
          AppEvent.authenticationSucceeded(
            effect.operationId,
            hasTenant: false,
            online: true,
          ),
        );
      case AppEffectKind.synchronize:
      case AppEffectKind.executeAction:
      case AppEffectKind.reconcileAction:
      case AppEffectKind.clearSession:
        _dispatch(AppEvent.operationSucceeded(effect.operationId));
      case AppEffectKind.recoverSession:
        _dispatch(
          AppEvent.recoverySucceeded(
            effect.operationId,
            authenticated: false,
            hasTenant: false,
            online: true,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _machine.snapshot;
    final capabilities = snapshot.capabilities;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiducia lifecycle console'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            _StateCard(snapshot: snapshot),
            const SizedBox(height: 8),
            Text(
              'deep link ${_deepLinks.snapshot.phase.name} · '
              'generation ${_deepLinks.snapshot.generation} · '
              'last ${_deepLinks.snapshot.lastAccepted?.action ?? 'none'}',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                FilledButton(
                  onPressed: capabilities.canSignIn
                      ? () => _dispatch(const AppEvent.signInRequested())
                      : null,
                  child: const Text('Sign in'),
                ),
                FilledButton(
                  onPressed: capabilities.canSelectTenant
                      ? () => _dispatch(const AppEvent.tenantSelected())
                      : null,
                  child: const Text('Select tenant'),
                ),
                FilledButton(
                  onPressed: capabilities.canRequestPrivilegedAction
                      ? () => _dispatch(
                          const AppEvent.actionRequested('rotate-api-key'),
                        )
                      : null,
                  child: const Text('Request protected action'),
                ),
                FilledButton.tonal(
                  onPressed: capabilities.canConfirmAction
                      ? () => _dispatch(const AppEvent.actionConfirmed())
                      : null,
                  child: const Text('Confirm'),
                ),
                FilledButton.tonal(
                  onPressed: capabilities.canCancelAction
                      ? () => _dispatch(const AppEvent.actionCancelled())
                      : null,
                  child: const Text('Cancel'),
                ),
                OutlinedButton(
                  onPressed: snapshot.phase == AppPhase.readyOnline
                      ? () =>
                            _dispatch(const AppEvent.connectivityChanged(false))
                      : snapshot.phase == AppPhase.readyOffline ||
                            snapshot.phase == AppPhase.reconciliationRequired ||
                            snapshot.phase == AppPhase.selectingTenant ||
                            snapshot.phase == AppPhase.signedOut
                      ? () =>
                            _dispatch(const AppEvent.connectivityChanged(true))
                      : null,
                  child: Text(snapshot.online ? 'Go offline' : 'Go online'),
                ),
                OutlinedButton(
                  onPressed: capabilities.canRecover
                      ? () => _dispatch(const AppEvent.recoveryRequested())
                      : null,
                  child: const Text('Recover'),
                ),
                OutlinedButton(
                  onPressed: capabilities.canSignOut
                      ? () => _dispatch(const AppEvent.signOutRequested())
                      : null,
                  child: const Text('Sign out'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Transition audit',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final entry in _audit)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(entry),
              ),
          ],
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.snapshot});

  final AppSnapshot snapshot;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            snapshot.phase.name,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'generation ${snapshot.generation} · authority '
            '${snapshot.authorityEpoch} · ${snapshot.online ? 'online' : 'offline'}',
          ),
          Text(
            'session ${snapshot.hasSession} · tenant '
            '${snapshot.hasTenant} · operation '
            '${snapshot.activeOperation?.name ?? 'none'}',
          ),
          if (snapshot.pendingAction != null)
            Text('pending ${snapshot.pendingAction!.id}'),
          if (snapshot.failure != null)
            Text(
              snapshot.failure!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}
