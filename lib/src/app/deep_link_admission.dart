import 'dart:convert';

import 'app_lifecycle_machine.dart';

const int deepLinkContractVersion = 1;
const int maximumDeepLinkBytes = 2048;
const Set<String> allowedDeepLinkActions = <String>{
  'rotate-api-key',
  'review-reconciliation',
};

enum DeepLinkPhase { idle, resolving, pending }

enum DeepLinkDisposition {
  began,
  accepted,
  rejected,
  stale,
  consumed,
  failedClosed,
}

enum DeepLinkReason {
  resolving('resolving'),
  accepted('accepted'),
  consumed('consumed'),
  empty('empty'),
  tooLong('too_long'),
  malformed('malformed'),
  insecureScheme('insecure_scheme'),
  unexpectedOrigin('unexpected_origin'),
  credentialsForbidden('credentials_forbidden'),
  unexpectedPort('unexpected_port'),
  unexpectedPath('unexpected_path'),
  fragmentForbidden('fragment_forbidden'),
  unexpectedParameter('unexpected_parameter'),
  duplicateParameter('duplicate_parameter'),
  missingAction('missing_action'),
  unknownAction('unknown_action'),
  nonCanonical('non_canonical'),
  notPending('not_pending'),
  staleGeneration('stale_generation'),
  invalidSnapshot('invalid_snapshot'),
  lifecycleRejected('lifecycle_rejected');

  const DeepLinkReason(this.wireName);

  final String wireName;
}

class DeepLinkIntent {
  const DeepLinkIntent({required this.action});

  final String action;

  String get kind => 'request_action';

  String get canonicalUrl => 'https://fiducia.cloud/open?action=$action';

  Map<String, Object> toJson() => <String, Object>{
    'version': deepLinkContractVersion,
    'kind': kind,
    'action': action,
    'canonical_url': canonicalUrl,
  };

  @override
  bool operator ==(Object other) =>
      other is DeepLinkIntent && other.action == action;

  @override
  int get hashCode => action.hashCode;
}

class DeepLinkSnapshot {
  const DeepLinkSnapshot({
    required this.phase,
    required this.generation,
    required this.candidate,
    required this.lastAccepted,
  });

  const DeepLinkSnapshot.idle({this.generation = 0, this.lastAccepted})
    : phase = DeepLinkPhase.idle,
      candidate = null;

  final DeepLinkPhase phase;
  final int generation;
  final String? candidate;
  final DeepLinkIntent? lastAccepted;

  bool get canHandoff => phase == DeepLinkPhase.pending && lastAccepted != null;

  bool get isValid {
    if (generation < 0 || generation > AppSnapshot.maxPortableCounter) {
      return false;
    }
    if (lastAccepted != null &&
        !allowedDeepLinkActions.contains(lastAccepted!.action)) {
      return false;
    }
    return switch (phase) {
      DeepLinkPhase.idle => candidate == null,
      DeepLinkPhase.resolving =>
        candidate != null &&
            DeepLinkAdmissionMachine._preflight(candidate!) == null,
      DeepLinkPhase.pending => candidate == null && lastAccepted != null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DeepLinkSnapshot &&
      other.phase == phase &&
      other.generation == generation &&
      other.candidate == candidate &&
      other.lastAccepted == lastAccepted;

  @override
  int get hashCode => Object.hash(phase, generation, candidate, lastAccepted);
}

class DeepLinkEffect {
  const DeepLinkEffect({required this.generation});

  final int generation;
}

class DeepLinkTransition {
  const DeepLinkTransition({
    required this.previous,
    required this.current,
    required this.disposition,
    required this.reason,
    this.effect,
    this.intent,
  });

  final DeepLinkSnapshot previous;
  final DeepLinkSnapshot current;
  final DeepLinkDisposition disposition;
  final DeepLinkReason reason;
  final DeepLinkEffect? effect;
  final DeepLinkIntent? intent;
}

class DeepLinkHandoff {
  const DeepLinkHandoff({required this.admission, this.lifecycle});

  final DeepLinkTransition admission;
  final AppTransition? lifecycle;

  bool get delivered =>
      admission.disposition == DeepLinkDisposition.consumed &&
      lifecycle?.disposition == AppTransitionDisposition.applied;
}

class DeepLinkAdmissionMachine {
  DeepLinkAdmissionMachine({DeepLinkSnapshot? initialSnapshot})
    : _snapshot = _validatedInitial(initialSnapshot);

  DeepLinkSnapshot _snapshot;

  DeepLinkSnapshot get snapshot => _snapshot;

  static DeepLinkSnapshot _validatedInitial(DeepLinkSnapshot? initial) {
    if (initial == null) return const DeepLinkSnapshot.idle();
    if (initial.isValid) return initial;
    return DeepLinkSnapshot.idle(
      generation: _closedGeneration(initial.generation),
    );
  }

  DeepLinkTransition begin(String raw) {
    final previous = _snapshot;
    if (!previous.isValid) return _failClosed(previous);
    if (previous.generation >= AppSnapshot.maxPortableCounter) {
      return _failClosed(previous);
    }

    final preflight = _preflight(raw);
    if (preflight != null) {
      return DeepLinkTransition(
        previous: previous,
        current: previous,
        disposition: DeepLinkDisposition.rejected,
        reason: preflight,
      );
    }

    final current = DeepLinkSnapshot(
      phase: DeepLinkPhase.resolving,
      generation: previous.generation + 1,
      candidate: raw,
      lastAccepted: previous.lastAccepted,
    );
    _snapshot = current;
    return DeepLinkTransition(
      previous: previous,
      current: current,
      disposition: DeepLinkDisposition.began,
      reason: DeepLinkReason.resolving,
      effect: DeepLinkEffect(generation: current.generation),
    );
  }

  DeepLinkTransition complete(int generation) {
    final previous = _snapshot;
    if (!previous.isValid) return _failClosed(previous);
    if (previous.phase != DeepLinkPhase.resolving ||
        generation != previous.generation) {
      return DeepLinkTransition(
        previous: previous,
        current: previous,
        disposition: DeepLinkDisposition.stale,
        reason: DeepLinkReason.staleGeneration,
      );
    }

    final parsed = _parse(previous.candidate!);
    if (parsed.intent == null) {
      final current = DeepLinkSnapshot.idle(
        generation: previous.generation,
        lastAccepted: previous.lastAccepted,
      );
      _snapshot = current;
      return DeepLinkTransition(
        previous: previous,
        current: current,
        disposition: DeepLinkDisposition.rejected,
        reason: parsed.reason,
      );
    }

    final current = DeepLinkSnapshot(
      phase: DeepLinkPhase.pending,
      generation: previous.generation,
      candidate: null,
      lastAccepted: parsed.intent,
    );
    _snapshot = current;
    return DeepLinkTransition(
      previous: previous,
      current: current,
      disposition: DeepLinkDisposition.accepted,
      reason: DeepLinkReason.accepted,
      intent: parsed.intent,
    );
  }

  DeepLinkTransition consume(int generation) {
    final previous = _snapshot;
    if (!previous.isValid) return _failClosed(previous);
    if (generation != previous.generation) {
      return DeepLinkTransition(
        previous: previous,
        current: previous,
        disposition: DeepLinkDisposition.stale,
        reason: DeepLinkReason.staleGeneration,
      );
    }
    if (!previous.canHandoff) {
      return DeepLinkTransition(
        previous: previous,
        current: previous,
        disposition: DeepLinkDisposition.rejected,
        reason: DeepLinkReason.notPending,
      );
    }

    final current = DeepLinkSnapshot.idle(
      generation: previous.generation,
      lastAccepted: previous.lastAccepted,
    );
    _snapshot = current;
    return DeepLinkTransition(
      previous: previous,
      current: current,
      disposition: DeepLinkDisposition.consumed,
      reason: DeepLinkReason.consumed,
      intent: previous.lastAccepted,
    );
  }

  DeepLinkHandoff handoffTo(AppLifecycleMachine lifecycle) {
    final previous = _snapshot;
    if (!previous.canHandoff) {
      return DeepLinkHandoff(admission: consume(previous.generation));
    }

    final lifecycleTransition = lifecycle.dispatch(
      AppEvent.actionRequested(previous.lastAccepted!.action),
    );
    if (lifecycleTransition.disposition != AppTransitionDisposition.applied) {
      return DeepLinkHandoff(
        admission: DeepLinkTransition(
          previous: previous,
          current: previous,
          disposition: DeepLinkDisposition.rejected,
          reason: DeepLinkReason.lifecycleRejected,
          intent: previous.lastAccepted,
        ),
        lifecycle: lifecycleTransition,
      );
    }

    return DeepLinkHandoff(
      admission: consume(previous.generation),
      lifecycle: lifecycleTransition,
    );
  }

  DeepLinkTransition _failClosed(DeepLinkSnapshot previous) {
    final current = DeepLinkSnapshot.idle(
      generation: _closedGeneration(previous.generation),
    );
    _snapshot = current;
    return DeepLinkTransition(
      previous: previous,
      current: current,
      disposition: DeepLinkDisposition.failedClosed,
      reason: DeepLinkReason.invalidSnapshot,
    );
  }

  static int _closedGeneration(int generation) {
    if (generation < 0 || generation > AppSnapshot.maxPortableCounter) {
      return 0;
    }
    if (generation == AppSnapshot.maxPortableCounter) return generation;
    return generation + 1;
  }

  static DeepLinkReason? _preflight(String raw) {
    if (raw.isEmpty) return DeepLinkReason.empty;
    if (utf8.encode(raw).length > maximumDeepLinkBytes) {
      return DeepLinkReason.tooLong;
    }
    if (raw.trim() != raw ||
        raw.runes.any((int rune) => rune < 0x20 || rune == 0x7f)) {
      return DeepLinkReason.malformed;
    }
    return null;
  }

  static _ParseResult _parse(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return const _ParseResult.rejected(DeepLinkReason.malformed);
    }
    if (uri.scheme != 'https') {
      return const _ParseResult.rejected(DeepLinkReason.insecureScheme);
    }
    if (!raw.startsWith('https://')) {
      return const _ParseResult.rejected(DeepLinkReason.nonCanonical);
    }

    final authorityEnd = _firstDelimiter(raw, 'https://'.length);
    if (authorityEnd <= 'https://'.length) {
      return const _ParseResult.rejected(DeepLinkReason.malformed);
    }
    final authority = raw.substring('https://'.length, authorityEnd);
    if (authority.contains('@') || uri.userInfo.isNotEmpty) {
      return const _ParseResult.rejected(DeepLinkReason.credentialsForbidden);
    }
    if (authority.startsWith('fiducia.cloud:')) {
      return const _ParseResult.rejected(DeepLinkReason.unexpectedPort);
    }
    if (authority.toLowerCase() == 'fiducia.cloud' &&
        authority != 'fiducia.cloud') {
      return const _ParseResult.rejected(DeepLinkReason.nonCanonical);
    }
    if (authority != 'fiducia.cloud' || uri.host != 'fiducia.cloud') {
      return const _ParseResult.rejected(DeepLinkReason.unexpectedOrigin);
    }
    if (uri.hasPort) {
      return const _ParseResult.rejected(DeepLinkReason.unexpectedPort);
    }
    if (raw.contains('#') || uri.hasFragment) {
      return const _ParseResult.rejected(DeepLinkReason.fragmentForbidden);
    }
    if (uri.path != '/open') {
      return const _ParseResult.rejected(DeepLinkReason.unexpectedPath);
    }
    if (raw.contains('%') || raw.contains('+')) {
      return const _ParseResult.rejected(DeepLinkReason.nonCanonical);
    }

    final queryStart = raw.indexOf('?');
    if (queryStart < 0 || queryStart == raw.length - 1) {
      return const _ParseResult.rejected(DeepLinkReason.missingAction);
    }
    final query = raw.substring(queryStart + 1);
    final segments = query.split('&');
    if (segments.any((String segment) => segment.isEmpty)) {
      return const _ParseResult.rejected(DeepLinkReason.nonCanonical);
    }

    final actions = <String>[];
    for (final segment in segments) {
      final equals = segment.indexOf('=');
      if (equals <= 0 || equals != segment.lastIndexOf('=')) {
        return const _ParseResult.rejected(DeepLinkReason.nonCanonical);
      }
      final key = segment.substring(0, equals);
      final value = segment.substring(equals + 1);
      if (key != 'action') {
        return const _ParseResult.rejected(DeepLinkReason.unexpectedParameter);
      }
      actions.add(value);
    }

    if (actions.length > 1) {
      return const _ParseResult.rejected(DeepLinkReason.duplicateParameter);
    }
    final action = actions.single;
    if (action.isEmpty) {
      return const _ParseResult.rejected(DeepLinkReason.missingAction);
    }
    if (!allowedDeepLinkActions.contains(action)) {
      return const _ParseResult.rejected(DeepLinkReason.unknownAction);
    }

    final intent = DeepLinkIntent(action: action);
    if (raw != intent.canonicalUrl || uri.toString() != raw) {
      return const _ParseResult.rejected(DeepLinkReason.nonCanonical);
    }
    return _ParseResult.accepted(intent);
  }

  static int _firstDelimiter(String raw, int start) {
    var result = raw.length;
    for (final delimiter in <String>['/', '?', '#']) {
      final index = raw.indexOf(delimiter, start);
      if (index >= 0 && index < result) result = index;
    }
    return result;
  }
}

class _ParseResult {
  const _ParseResult.accepted(this.intent) : reason = DeepLinkReason.accepted;

  const _ParseResult.rejected(this.reason) : intent = null;

  final DeepLinkIntent? intent;
  final DeepLinkReason reason;
}
