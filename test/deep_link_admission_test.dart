import 'dart:convert';
import 'dart:io';

import 'package:fiducia_flutter/src/app/app_lifecycle_machine.dart';
import 'package:fiducia_flutter/src/app/deep_link_admission.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final corpus =
      jsonDecode(File('contracts/deep_link_vectors.json').readAsStringSync())
          as Map<String, Object?>;
  final vectors = (corpus['vectors']! as List<Object?>)
      .cast<Map<String, Object?>>();

  test('shared JSON contract and every conformance vector are valid', () {
    final schema =
        jsonDecode(File('contracts/deep_link.schema.json').readAsStringSync())
            as Map<String, Object?>;
    expect(schema[r'$schema'], 'https://json-schema.org/draft/2020-12/schema');
    expect(schema['additionalProperties'], isFalse);
    expect(corpus['contract_version'], deepLinkContractVersion);
    expect(corpus['maximum_input_bytes'], maximumDeepLinkBytes);

    for (final vector in vectors) {
      final machine = DeepLinkAdmissionMachine();
      final input = _expandedInput(vector);
      final expected = vector['expected']! as Map<String, Object?>;
      final begin = machine.begin(input);
      final DeepLinkTransition result;
      if (begin.effect == null) {
        result = begin;
      } else {
        result = machine.complete(begin.effect!.generation);
      }

      expect(
        result.disposition.name,
        expected['disposition'],
        reason: vector['id']! as String,
      );
      expect(
        result.reason.wireName,
        expected['reason'],
        reason: vector['id']! as String,
      );
      if (result.disposition == DeepLinkDisposition.accepted) {
        expect(
          result.intent!.toJson(),
          expected['intent'],
          reason: vector['id']! as String,
        );
      } else {
        expect(result.intent, isNull, reason: vector['id']! as String);
      }
      expect(machine.snapshot.isValid, isTrue);
    }
  });

  test('a newer capture fences a stale resolution completion', () {
    final machine = DeepLinkAdmissionMachine();
    final first = machine.begin(
      'https://fiducia.cloud/open?action=rotate-api-key',
    );
    final second = machine.begin(
      'https://fiducia.cloud/open?action=review-reconciliation',
    );
    final beforeStale = machine.snapshot;

    final stale = machine.complete(first.effect!.generation);
    expect(stale.disposition, DeepLinkDisposition.stale);
    expect(stale.current, beforeStale);

    final accepted = machine.complete(second.effect!.generation);
    expect(accepted.disposition, DeepLinkDisposition.accepted);
    expect(accepted.intent!.action, 'review-reconciliation');
  });

  test('a rejected input cannot erase the last accepted intent', () {
    final machine = DeepLinkAdmissionMachine();
    final accepted = machine.begin(
      'https://fiducia.cloud/open?action=rotate-api-key',
    );
    machine.complete(accepted.effect!.generation);
    machine.consume(machine.snapshot.generation);

    final invalid = machine.begin(
      'https://fiducia.cloud/open?action=delete-company',
    );
    final rejected = machine.complete(invalid.effect!.generation);
    expect(rejected.disposition, DeepLinkDisposition.rejected);
    expect(rejected.reason, DeepLinkReason.unknownAction);
    expect(machine.snapshot.phase, DeepLinkPhase.idle);
    expect(machine.snapshot.lastAccepted?.action, 'rotate-api-key');
  });

  test(
    'lifecycle authority retains a link until protected action is legal',
    () {
      final links = DeepLinkAdmissionMachine();
      final begin = links.begin(
        'https://fiducia.cloud/open?action=rotate-api-key',
      );
      links.complete(begin.effect!.generation);

      final lifecycle = AppLifecycleMachine();
      final rejected = links.handoffTo(lifecycle);
      expect(rejected.delivered, isFalse);
      expect(
        rejected.lifecycle?.disposition,
        AppTransitionDisposition.rejected,
      );
      expect(links.snapshot.phase, DeepLinkPhase.pending);
      expect(lifecycle.snapshot.phase, AppPhase.cold);

      final ready = _bootReady();
      final delivered = links.handoffTo(ready);
      expect(delivered.delivered, isTrue);
      expect(links.snapshot.phase, DeepLinkPhase.idle);
      expect(ready.snapshot.phase, AppPhase.confirmingAction);
      expect(ready.snapshot.pendingAction?.id, 'rotate-api-key');
    },
  );

  test('invalid snapshots fail closed and revoke admitted intent', () {
    const corrupt = DeepLinkSnapshot(
      phase: DeepLinkPhase.pending,
      generation: 7,
      candidate: 'forbidden candidate',
      lastAccepted: null,
    );
    expect(corrupt.isValid, isFalse);

    final machine = DeepLinkAdmissionMachine(initialSnapshot: corrupt);
    expect(machine.snapshot.isValid, isTrue);
    expect(machine.snapshot.phase, DeepLinkPhase.idle);
    expect(machine.snapshot.lastAccepted, isNull);
    expect(machine.snapshot.generation, 8);

    const outOfDomain = DeepLinkSnapshot(
      phase: DeepLinkPhase.idle,
      generation: AppSnapshot.maxPortableCounter + 1,
      candidate: null,
      lastAccepted: null,
    );
    final normalized = DeepLinkAdmissionMachine(initialSnapshot: outOfDomain);
    expect(normalized.snapshot, const DeepLinkSnapshot.idle());
  });

  test('generation exhaustion fails closed without token reuse', () {
    final machine = DeepLinkAdmissionMachine(
      initialSnapshot: const DeepLinkSnapshot.idle(
        generation: AppSnapshot.maxPortableCounter,
        lastAccepted: DeepLinkIntent(action: 'rotate-api-key'),
      ),
    );

    final exhausted = machine.begin(
      'https://fiducia.cloud/open?action=review-reconciliation',
    );
    expect(exhausted.disposition, DeepLinkDisposition.failedClosed);
    expect(exhausted.reason, DeepLinkReason.invalidSnapshot);
    expect(exhausted.effect, isNull);
    expect(exhausted.current.generation, AppSnapshot.maxPortableCounter);
    expect(exhausted.current.lastAccepted, isNull);
  });

  test('bounded graph is total, deterministic, and invariant preserving', () {
    final initial = DeepLinkAdmissionMachine().snapshot;
    final visited = <DeepLinkSnapshot>{initial};
    var frontier = <DeepLinkSnapshot>{initial};
    final phases = <DeepLinkPhase>{initial.phase};
    final dispositions = <DeepLinkDisposition>{};

    for (var depth = 0; depth < 7; depth += 1) {
      final next = <DeepLinkSnapshot>{};
      for (final snapshot in frontier) {
        for (final event in _boundedEvents(snapshot)) {
          final first = _apply(snapshot, event);
          final second = _apply(snapshot, event);
          expect(first.current, second.current);
          expect(first.disposition, second.disposition);
          expect(first.reason, second.reason);
          expect(first.current.isValid, isTrue);
          expect(
            first.current.generation,
            greaterThanOrEqualTo(snapshot.generation),
          );
          if (first.disposition == DeepLinkDisposition.stale) {
            expect(first.current, snapshot);
          }
          phases.add(first.current.phase);
          dispositions.add(first.disposition);
          if (visited.add(first.current)) next.add(first.current);
        }
      }
      frontier = next;
      if (frontier.isEmpty) break;
    }

    expect(phases, containsAll(DeepLinkPhase.values));
    expect(
      dispositions,
      containsAll(<DeepLinkDisposition>[
        DeepLinkDisposition.began,
        DeepLinkDisposition.accepted,
        DeepLinkDisposition.rejected,
        DeepLinkDisposition.stale,
        DeepLinkDisposition.consumed,
      ]),
    );
    expect(visited.length, lessThan(2000));
  });
}

String _expandedInput(Map<String, Object?> vector) {
  final input = vector['input']! as String;
  final append = vector['append_ascii']! as String;
  final count = vector['append_count']! as int;
  return input + List<String>.filled(count, append).join();
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
  return machine;
}

enum _BoundedEventKind { begin, complete, consume }

class _BoundedEvent {
  const _BoundedEvent.begin(this.raw)
    : kind = _BoundedEventKind.begin,
      generation = 0;

  const _BoundedEvent.complete(this.generation)
    : kind = _BoundedEventKind.complete,
      raw = '';

  const _BoundedEvent.consume(this.generation)
    : kind = _BoundedEventKind.consume,
      raw = '';

  final _BoundedEventKind kind;
  final String raw;
  final int generation;
}

List<_BoundedEvent> _boundedEvents(
  DeepLinkSnapshot snapshot,
) => <_BoundedEvent>[
  const _BoundedEvent.begin('https://fiducia.cloud/open?action=rotate-api-key'),
  const _BoundedEvent.begin(
    'https://fiducia.cloud/open?action=review-reconciliation',
  ),
  const _BoundedEvent.begin('https://fiducia.cloud/open?action=delete-company'),
  const _BoundedEvent.begin(''),
  _BoundedEvent.complete(snapshot.generation),
  _BoundedEvent.complete(snapshot.generation + 1),
  _BoundedEvent.consume(snapshot.generation),
  _BoundedEvent.consume(snapshot.generation + 1),
];

DeepLinkTransition _apply(DeepLinkSnapshot snapshot, _BoundedEvent event) {
  final machine = DeepLinkAdmissionMachine(initialSnapshot: snapshot);
  return switch (event.kind) {
    _BoundedEventKind.begin => machine.begin(event.raw),
    _BoundedEventKind.complete => machine.complete(event.generation),
    _BoundedEventKind.consume => machine.consume(event.generation),
  };
}
