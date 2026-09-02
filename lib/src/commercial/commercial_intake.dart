import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fiducia_interfaces/fiducia_interfaces.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String _defaultApiOrigin = String.fromEnvironment(
  'FIDUCIA_API_ORIGIN',
  defaultValue: 'https://api.fiducia.cloud',
);

final class CommercialIntakeException implements Exception {
  const CommercialIntakeException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class CommercialIntakeClient {
  CommercialIntakeClient({String apiOrigin = _defaultApiOrigin, http.Client? httpClient})
    : _apiOrigin = apiOrigin.endsWith('/')
          ? apiOrigin.substring(0, apiOrigin.length - 1)
          : apiOrigin,
      _httpClient = httpClient ?? http.Client();

  final String _apiOrigin;
  final http.Client _httpClient;
  final Random _random = Random.secure();

  Future<Map<String, Object?>> submit({
    required String path,
    required String schema,
    required Map<String, Object?> payload,
  }) async {
    validateFiduciaJson(schema, payload);
    final request = http.Request('POST', Uri.parse('$_apiOrigin$path'))
      ..followRedirects = false
      ..headers.addAll(<String, String>{
        'content-type': 'application/json',
        'idempotency-key': _idempotencyKey(),
      })
      ..body = jsonEncode(payload);
    final streamed = await _httpClient
        .send(request)
        .timeout(const Duration(seconds: 15));
    final responseBody = await streamed.stream.bytesToString();
    if (streamed.isRedirect) {
      throw const CommercialIntakeException(
        'The protected API attempted an unexpected redirect. Nothing was accepted.',
      );
    }
    Object? decoded;
    try {
      decoded = responseBody.isEmpty ? <String, Object?>{} : jsonDecode(responseBody);
    } on FormatException {
      throw const CommercialIntakeException(
        'The protected API returned an unreadable response.',
      );
    }
    if (decoded is! Map) {
      throw const CommercialIntakeException(
        'The protected API returned an unexpected response shape.',
      );
    }
    final body = Map<String, Object?>.from(decoded);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final message = body['message'];
      throw CommercialIntakeException(
        message is String && message.isNotEmpty
            ? message
            : 'The protected API rejected this submission.',
      );
    }
    return body;
  }

  String _idempotencyKey() {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    final entropy = List<int>.generate(16, (_) => _random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'fiducia-flutter:$micros:$entropy';
  }

  void close() => _httpClient.close();
}

class CommercialIntakeHub extends StatelessWidget {
  const CommercialIntakeHub({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fiducia commercial intake')),
    body: SafeArea(
      child: ListView(
        key: const ValueKey<String>('fiducia-commercial-intake-hub'),
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            'Plan dependable coordination',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Build a non-binding estimate, register an upcoming project, or submit a detailed enterprise application. Never include passwords, tokens, private keys, connection strings, OTPs, recovery phrases, or production secrets.',
          ),
          const SizedBox(height: 20),
          _JourneyCard(
            icon: Icons.request_quote_outlined,
            title: 'Quote',
            description:
                'Estimate monthly platform and implementation ranges from scale, deployment, retention, and support preferences.',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const QuotePage()),
            ),
          ),
          _JourneyCard(
            icon: Icons.notifications_active_outlined,
            title: 'Pre-interest registration',
            description:
                'Describe an upcoming use case without reserving capacity or accepting commercial terms.',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PreInterestPage()),
            ),
          ),
          _JourneyCard(
            icon: Icons.domain_verification_outlined,
            title: 'Enterprise application',
            description:
                'Capture architecture, security, support, SLO/SLA, procurement, legal, and billing requirements.',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EnterpriseApplicationPage(),
              ),
            ),
          ),
          _JourneyCard(
            icon: Icons.support_agent_outlined,
            title: 'Support and contract boundary',
            description:
                'Review how engineering SLOs, requested support, and signed contractual SLAs differ.',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SupportAndContractPage(),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: Icon(icon, size: 34),
      title: Text(title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(description),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onPressed,
    ),
  );
}

abstract base class _SubmittingState<T extends StatefulWidget> extends State<T> {
  final CommercialIntakeClient client = CommercialIntakeClient();
  bool submitting = false;
  Map<String, Object?>? receipt;
  String? errorMessage;

  Future<void> submitPayload({
    required String path,
    required String schema,
    required Map<String, Object?> payload,
  }) async {
    setState(() {
      submitting = true;
      receipt = null;
      errorMessage = null;
    });
    try {
      final result = await client.submit(path: path, schema: schema, payload: payload);
      if (!mounted) return;
      setState(() => receipt = result);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        errorMessage =
            'The protected API timed out. Nothing is assumed accepted; retry with a new submission.';
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => errorMessage = 'Contract validation failed: ${error.message}');
    } on CommercialIntakeException catch (error) {
      if (!mounted) return;
      setState(() => errorMessage = error.message);
    } on Object {
      if (!mounted) return;
      setState(() {
        errorMessage =
            'The submission could not be completed. Nothing is assumed accepted.';
      });
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Widget resultPanel() {
    if (errorMessage != null) {
      return Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(errorMessage!),
        ),
      );
    }
    if (receipt != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(receipt),
            key: const ValueKey<String>('fiducia-intake-receipt'),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    client.close();
    super.dispose();
  }
}

class QuotePage extends StatefulWidget {
  const QuotePage({super.key});

  @override
  State<QuotePage> createState() => _QuotePageState();
}

class _QuotePageState extends _SubmittingState<QuotePage> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final role = TextEditingController();
  final organization = TextEditingController();
  final country = TextEditingController(text: 'US');
  final industry = TextEditingController(text: 'software');
  final capabilities = TextEditingController(
    text: 'distributed_locks, idempotency, durable_tasks',
  );
  final environments = TextEditingController(text: '3');
  final averageOps = TextEditingController(text: '1000');
  final peakOps = TextEditingController(text: '5000');
  final retentionDays = TextEditingController(text: '30');
  final notes = TextEditingController();
  String companySize = 'employees_51_200';
  String deploymentModel = 'managed_multi_tenant';
  String supportPlan = 'standard';
  String budgetBand = 'monthly_2000_10000';
  bool onboardingRequired = true;
  bool estimateAcknowledged = false;
  bool secretsAcknowledged = false;
  bool privacyAccepted = false;

  @override
  Widget build(BuildContext context) => _FormScaffold(
    title: 'Request a quote',
    notice:
        'This software-generated range is non-binding and is not an offer, order form, SLA, legal approval, or capacity reservation.',
    children: <Widget>[
      _section('Contact and organization', <Widget>[
        _requiredField(name, 'Full name'),
        _requiredField(email, 'Work email', keyboardType: TextInputType.emailAddress),
        _requiredField(role, 'Role'),
        _requiredField(organization, 'Legal organization name'),
        _requiredField(country, 'Country'),
        _requiredField(industry, 'Industry'),
        DropdownButtonFormField<String>(
          initialValue: companySize,
          decoration: const InputDecoration(labelText: 'Company size'),
          items: _companySizes,
          onChanged: (value) => setState(() => companySize = value ?? companySize),
        ),
      ]),
      _section('Workload and commercial assumptions', <Widget>[
        _requiredField(capabilities, 'Capabilities (comma separated)'),
        DropdownButtonFormField<String>(
          initialValue: deploymentModel,
          decoration: const InputDecoration(labelText: 'Deployment model'),
          items: _deploymentModels,
          onChanged: (value) => setState(
            () => deploymentModel = value ?? deploymentModel,
          ),
        ),
        _requiredField(environments, 'Environments', number: true),
        _requiredField(averageOps, 'Average operations/second', number: true),
        _requiredField(peakOps, 'Peak operations/second', number: true),
        _requiredField(retentionDays, 'Retention days', number: true),
        DropdownButtonFormField<String>(
          initialValue: supportPlan,
          decoration: const InputDecoration(labelText: 'Requested support plan'),
          items: _supportPlans,
          onChanged: (value) => setState(() => supportPlan = value ?? supportPlan),
        ),
        DropdownButtonFormField<String>(
          initialValue: budgetBand,
          decoration: const InputDecoration(labelText: 'Budget band'),
          items: _budgetBands,
          onChanged: (value) => setState(() => budgetBand = value ?? budgetBand),
        ),
        TextFormField(
          controller: notes,
          decoration: const InputDecoration(
            labelText: 'Notes',
            helperText: 'Do not include credentials or secrets.',
          ),
          maxLength: 6000,
          maxLines: 5,
        ),
        SwitchListTile(
          value: onboardingRequired,
          title: const Text('Include onboarding and architecture review'),
          onChanged: (value) => setState(() => onboardingRequired = value),
        ),
      ]),
      _acknowledgement(
        value: estimateAcknowledged,
        label: 'I understand this estimate is non-binding.',
        onChanged: (value) => setState(() => estimateAcknowledged = value),
      ),
      _acknowledgement(
        value: secretsAcknowledged,
        label: 'I did not include credentials or secrets.',
        onChanged: (value) => setState(() => secretsAcknowledged = value),
      ),
      _acknowledgement(
        value: privacyAccepted,
        label: 'I accept the current privacy notice for this submission.',
        onChanged: (value) => setState(() => privacyAccepted = value),
      ),
      FilledButton.icon(
        key: const ValueKey<String>('submit-fiducia-quote'),
        onPressed: submitting ? null : _submit,
        icon: submitting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.calculate_outlined),
        label: const Text('Calculate and store estimate'),
      ),
      resultPanel(),
    ],
  );

  Future<void> _submit() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    if (!estimateAcknowledged || !secretsAcknowledged || !privacyAccepted) {
      setState(() => errorMessage = 'Complete every required acknowledgement.');
      return;
    }
    await submitPayload(
      path: '/v1/quotes',
      schema: 'QuoteRequest',
      payload: <String, Object?>{
        'contact': <String, Object?>{
          'email': email.text.trim(),
          'full_name': name.text.trim(),
          'role': role.text.trim(),
        },
        'organization': <String, Object?>{
          'legal_name': organization.text.trim(),
          'country': country.text.trim(),
          'company_size': companySize,
          'industry': industry.text.trim(),
        },
        'capabilities': _csv(capabilities.text),
        'deployment_model': deploymentModel,
        'environments': _integer(environments.text),
        'average_operations_per_second': _integer(averageOps.text),
        'peak_operations_per_second': _integer(peakOps.text),
        'retention_days': _integer(retentionDays.text),
        'support_plan': supportPlan,
        'budget_band': budgetBand,
        'onboarding_required': onboardingRequired,
        if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
        'acknowledges_non_binding_estimate': true,
        'acknowledges_no_secrets': true,
        'privacy_notice_accepted': true,
      },
    );
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      name,
      email,
      role,
      organization,
      country,
      industry,
      capabilities,
      environments,
      averageOps,
      peakOps,
      retentionDays,
      notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }
}

class PreInterestPage extends StatefulWidget {
  const PreInterestPage({super.key});

  @override
  State<PreInterestPage> createState() => _PreInterestPageState();
}

class _PreInterestPageState extends _SubmittingState<PreInterestPage> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final role = TextEditingController();
  final organization = TextEditingController();
  final country = TextEditingController(text: 'US');
  final industry = TextEditingController(text: 'software');
  final useCase = TextEditingController();
  final capabilities = TextEditingController(
    text: 'distributed_locks, leader_election, idempotency',
  );
  String companySize = 'employees_51_200';
  String startWindow = 'within_90_days';
  String budgetBand = 'unknown';
  String supportPlan = 'standard';
  bool productUpdates = false;
  bool secretsAcknowledged = false;
  bool privacyAccepted = false;

  @override
  Widget build(BuildContext context) => _FormScaffold(
    title: 'Register pre-interest',
    notice:
        'Registration does not reserve capacity, guarantee eligibility, or create a support or commercial commitment.',
    children: <Widget>[
      _section('Contact and organization', <Widget>[
        _requiredField(name, 'Full name'),
        _requiredField(email, 'Work email', keyboardType: TextInputType.emailAddress),
        _requiredField(role, 'Role'),
        _requiredField(organization, 'Legal organization name'),
        _requiredField(country, 'Country'),
        _requiredField(industry, 'Industry'),
        DropdownButtonFormField<String>(
          initialValue: companySize,
          decoration: const InputDecoration(labelText: 'Company size'),
          items: _companySizes,
          onChanged: (value) => setState(() => companySize = value ?? companySize),
        ),
      ]),
      _section('Upcoming project', <Widget>[
        _requiredField(useCase, 'Use case summary', maxLines: 7),
        _requiredField(capabilities, 'Capabilities (comma separated)'),
        DropdownButtonFormField<String>(
          initialValue: startWindow,
          decoration: const InputDecoration(labelText: 'Desired start window'),
          items: _startWindows,
          onChanged: (value) => setState(() => startWindow = value ?? startWindow),
        ),
        DropdownButtonFormField<String>(
          initialValue: budgetBand,
          decoration: const InputDecoration(labelText: 'Budget band'),
          items: _budgetBands,
          onChanged: (value) => setState(() => budgetBand = value ?? budgetBand),
        ),
        DropdownButtonFormField<String>(
          initialValue: supportPlan,
          decoration: const InputDecoration(labelText: 'Support interest'),
          items: _supportPlans,
          onChanged: (value) => setState(() => supportPlan = value ?? supportPlan),
        ),
        SwitchListTile(
          value: productUpdates,
          title: const Text('Send relevant product and availability updates'),
          onChanged: (value) => setState(() => productUpdates = value),
        ),
      ]),
      _acknowledgement(
        value: secretsAcknowledged,
        label: 'I did not include credentials or secrets.',
        onChanged: (value) => setState(() => secretsAcknowledged = value),
      ),
      _acknowledgement(
        value: privacyAccepted,
        label: 'I accept the current privacy notice.',
        onChanged: (value) => setState(() => privacyAccepted = value),
      ),
      FilledButton.icon(
        key: const ValueKey<String>('submit-fiducia-pre-interest'),
        onPressed: submitting ? null : _submit,
        icon: const Icon(Icons.notifications_active_outlined),
        label: const Text('Register interest'),
      ),
      resultPanel(),
    ],
  );

  Future<void> _submit() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    if (!secretsAcknowledged || !privacyAccepted) {
      setState(() => errorMessage = 'Complete every required acknowledgement.');
      return;
    }
    await submitPayload(
      path: '/v1/pre-interest-registrations',
      schema: 'PreInterestRequest',
      payload: <String, Object?>{
        'contact': <String, Object?>{
          'email': email.text.trim(),
          'full_name': name.text.trim(),
          'role': role.text.trim(),
        },
        'organization': <String, Object?>{
          'legal_name': organization.text.trim(),
          'country': country.text.trim(),
          'company_size': companySize,
          'industry': industry.text.trim(),
        },
        'use_case_summary': useCase.text.trim(),
        'capabilities': _csv(capabilities.text),
        'desired_start_window': startWindow,
        'budget_band': budgetBand,
        'support_plan': supportPlan,
        'product_updates_consent': productUpdates,
        'acknowledges_no_secrets': true,
        'privacy_notice_accepted': true,
      },
    );
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      name,
      email,
      role,
      organization,
      country,
      industry,
      useCase,
      capabilities,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }
}

class EnterpriseApplicationPage extends StatefulWidget {
  const EnterpriseApplicationPage({super.key});

  @override
  State<EnterpriseApplicationPage> createState() =>
      _EnterpriseApplicationPageState();
}

class _EnterpriseApplicationPageState
    extends _SubmittingState<EnterpriseApplicationPage> {
  final formKey = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{
    'contact_name': TextEditingController(),
    'contact_email': TextEditingController(),
    'contact_role': TextEditingController(),
    'contact_phone': TextEditingController(),
    'contact_timezone': TextEditingController(text: 'America/New_York'),
    'organization_name': TextEditingController(),
    'organization_country': TextEditingController(text: 'US'),
    'organization_region': TextEditingController(),
    'organization_industry': TextEditingController(text: 'software'),
    'project_name': TextEditingController(),
    'use_case': TextEditingController(),
    'start_date': TextEditingController(
      text: DateTime.now().add(const Duration(days: 30)).toIso8601String().split('T').first,
    ),
    'production_deadline': TextEditingController(),
    'internal_users': TextEditingController(text: '10'),
    'end_users': TextEditingController(text: '1000'),
    'environment_count': TextEditingController(text: '3'),
    'capabilities': TextEditingController(
      text: 'distributed_locks, idempotency, durable_tasks',
    ),
    'deployment_models': TextEditingController(text: 'managed_dedicated'),
    'client_languages': TextEditingController(text: 'rust, typescript, go'),
    'integrations': TextEditingController(
      text: 'kubernetes, terraform, open_telemetry',
    ),
    'regions': TextEditingController(text: 'us-east, us-west'),
    'data_classes': TextEditingController(
      text: 'internal, confidential_business, customer_content',
    ),
    'average_ops': TextEditingController(text: '5000'),
    'peak_ops': TextEditingController(text: '25000'),
    'active_keys': TextEditingController(text: '100000'),
    'payload_bytes': TextEditingController(text: '4096'),
    'retention_days': TextEditingController(text: '30'),
    'p95_ms': TextEditingController(text: '100'),
    'p99_ms': TextEditingController(text: '250'),
    'failover_seconds': TextEditingController(text: '60'),
    'rpo_seconds': TextEditingController(text: '0'),
    'rto_seconds': TextEditingController(text: '300'),
    'current_stack': TextEditingController(),
    'migration_source': TextEditingController(),
    'architecture_notes': TextEditingController(),
    'compliance': TextEditingController(text: 'soc_2'),
    'residency_locations': TextEditingController(),
    'audit_retention': TextEditingController(text: '365'),
    'security_notes': TextEditingController(),
    'support_channels': TextEditingController(text: 'email, ticket_portal'),
    'p1_minutes': TextEditingController(text: '60'),
    'p2_minutes': TextEditingController(text: '240'),
    'p3_hours': TextEditingController(text: '24'),
    'support_notes': TextEditingController(),
    'maintenance_notice': TextEditingController(text: '72'),
    'slo_notes': TextEditingController(),
    'requested_documents': TextEditingController(
      text: 'msa, order_form, sla, dpa, security_addendum',
    ),
    'term_months': TextEditingController(text: '12'),
    'termination_notice': TextEditingController(text: '30'),
    'governing_law': TextEditingController(),
    'venue': TextEditingController(),
    'liability': TextEditingController(),
    'indemnity': TextEditingController(),
    'insurance': TextEditingController(),
    'audit_rights': TextEditingController(),
    'data_processing': TextEditingController(),
    'ip_requirements': TextEditingController(),
    'procurement_notes': TextEditingController(),
    'monthly_budget': TextEditingController(text: '1000000'),
    'implementation_budget': TextEditingController(text: '2500000'),
    'billing_name': TextEditingController(),
    'billing_email': TextEditingController(),
    'billing_role': TextEditingController(text: 'Billing contact'),
    'signatory_name': TextEditingController(),
    'signatory_email': TextEditingController(),
    'signatory_role': TextEditingController(text: 'Authorized signatory'),
    'commercial_notes': TextEditingController(),
    'additional_requirements': TextEditingController(),
  };

  String companySize = 'employees_51_200';
  String projectStage = 'pilot';
  String decisionTimeline = 'within_90_days';
  String consistency = 'linearizable';
  String supportPlan = 'priority';
  String supportHours = 'twenty_four_by_five';
  String availability = 'availability_99_5';
  String measurementWindow = 'monthly';
  String errorBudgetPolicy = 'joint_review';
  String contractPath = 'fiducia_msa';
  String billingCadence = 'annual';
  String paymentTerms = 'net_30';
  String currency = 'USD';
  String budgetBand = 'monthly_10000_50000';
  String pricingModel = 'platform_subscription';
  bool privateNetworking = false;
  bool offlineEdge = false;
  bool ssoRequired = true;
  bool scimRequired = false;
  bool mfaRequired = true;
  bool mtlsRequired = false;
  bool cmkRequired = false;
  bool residencyRequired = false;
  bool auditLogRequired = true;
  bool securityQuestionnaire = true;
  bool onboardingRequired = true;
  bool trainingRequired = true;
  bool architectureReview = true;
  bool migrationAssistance = false;
  bool namedContact = true;
  bool tamRequired = false;
  bool incidentBridge = false;
  bool serviceCredits = false;
  bool acceptsEvaluationSlo = true;
  bool autoRenewal = false;
  bool terminationForConvenience = false;
  bool purchaseOrderRequired = true;
  bool vendorPortalRequired = false;
  bool securityReviewRequired = true;
  bool legalReviewRequired = true;
  bool taxExempt = false;
  bool reseller = false;
  bool authorized = false;
  bool nonBindingAcknowledged = false;
  bool noSecretsAcknowledged = false;
  bool privacyAccepted = false;

  TextEditingController field(String key) => fields[key]!;

  @override
  Widget build(BuildContext context) => _FormScaffold(
    title: 'Enterprise application',
    notice:
        'This detailed questionnaire starts technical, security, support, procurement, and legal review. It is not itself a contract or SLA.',
    children: <Widget>[
      _section('Primary contact and organization', <Widget>[
        _requiredField(field('contact_name'), 'Primary contact name'),
        _requiredField(
          field('contact_email'),
          'Primary contact email',
          keyboardType: TextInputType.emailAddress,
        ),
        _requiredField(field('contact_role'), 'Primary contact role'),
        _optionalField(field('contact_phone'), 'Phone'),
        _optionalField(field('contact_timezone'), 'Timezone'),
        _requiredField(field('organization_name'), 'Legal organization name'),
        _requiredField(field('organization_country'), 'Country'),
        _optionalField(field('organization_region'), 'State/region'),
        _requiredField(field('organization_industry'), 'Industry'),
        DropdownButtonFormField<String>(
          initialValue: companySize,
          decoration: const InputDecoration(labelText: 'Company size'),
          items: _companySizes,
          onChanged: (value) => setState(() => companySize = value ?? companySize),
        ),
      ]),
      _section('Project and decision process', <Widget>[
        _requiredField(field('project_name'), 'Project name'),
        DropdownButtonFormField<String>(
          initialValue: projectStage,
          decoration: const InputDecoration(labelText: 'Project stage'),
          items: _projectStages,
          onChanged: (value) => setState(() => projectStage = value ?? projectStage),
        ),
        _requiredField(field('use_case'), 'Use case summary', maxLines: 7),
        _requiredField(field('start_date'), 'Desired start date (YYYY-MM-DD)'),
        _optionalField(field('production_deadline'), 'Production deadline (YYYY-MM-DD)'),
        DropdownButtonFormField<String>(
          initialValue: decisionTimeline,
          decoration: const InputDecoration(labelText: 'Decision timeline'),
          items: _startWindows,
          onChanged: (value) => setState(
            () => decisionTimeline = value ?? decisionTimeline,
          ),
        ),
        _requiredField(field('internal_users'), 'Internal users', number: true),
        _requiredField(field('end_users'), 'End users', number: true),
        _requiredField(field('environment_count'), 'Environment count', number: true),
      ]),
      _section('Architecture and scale', <Widget>[
        _requiredField(field('capabilities'), 'Capabilities (comma separated)'),
        _requiredField(
          field('deployment_models'),
          'Deployment models (comma separated)',
        ),
        _requiredField(
          field('client_languages'),
          'Client languages (comma separated)',
        ),
        _optionalField(field('integrations'), 'Integrations (comma separated)'),
        _requiredField(field('regions'), 'Regions (comma separated)'),
        _requiredField(field('data_classes'), 'Data classes (comma separated)'),
        _requiredField(field('average_ops'), 'Average operations/second', number: true),
        _requiredField(field('peak_ops'), 'Peak operations/second', number: true),
        _optionalField(field('active_keys'), 'Estimated active keys', number: true),
        _optionalField(field('payload_bytes'), 'Maximum payload bytes', number: true),
        _optionalField(field('retention_days'), 'Retention days', number: true),
        DropdownButtonFormField<String>(
          initialValue: consistency,
          decoration: const InputDecoration(labelText: 'Consistency expectation'),
          items: _consistencyLevels,
          onChanged: (value) => setState(() => consistency = value ?? consistency),
        ),
        _optionalField(field('p95_ms'), 'p95 latency target (ms)', number: true),
        _optionalField(field('p99_ms'), 'p99 latency target (ms)', number: true),
        _optionalField(field('failover_seconds'), 'Failover target (seconds)', number: true),
        _optionalField(field('rpo_seconds'), 'RPO (seconds)', number: true),
        _optionalField(field('rto_seconds'), 'RTO (seconds)', number: true),
        _switch('Private networking required', privateNetworking, (value) => privateNetworking = value),
        _switch('Offline or edge operation required', offlineEdge, (value) => offlineEdge = value),
        _optionalField(field('current_stack'), 'Current stack', maxLines: 4),
        _optionalField(field('migration_source'), 'Migration source', maxLines: 4),
        _optionalField(field('architecture_notes'), 'Architecture notes', maxLines: 7),
      ]),
      _section('Security and compliance', <Widget>[
        _requiredField(field('compliance'), 'Frameworks (comma separated)'),
        _optionalField(
          field('residency_locations'),
          'Residency locations (comma separated)',
        ),
        _switch('SSO required', ssoRequired, (value) => ssoRequired = value),
        _switch('SCIM required', scimRequired, (value) => scimRequired = value),
        _switch('MFA required', mfaRequired, (value) => mfaRequired = value),
        _switch('mTLS required', mtlsRequired, (value) => mtlsRequired = value),
        _switch('Customer-managed keys required', cmkRequired, (value) => cmkRequired = value),
        _switch('Data residency required', residencyRequired, (value) => residencyRequired = value),
        _switch('Audit logs required', auditLogRequired, (value) => auditLogRequired = value),
        _switch(
          'Security questionnaire required',
          securityQuestionnaire,
          (value) => securityQuestionnaire = value,
        ),
        _optionalField(field('audit_retention'), 'Audit retention days', number: true),
        _optionalField(field('security_notes'), 'Additional security requirements', maxLines: 7),
      ]),
      _section('Support and requested service level', <Widget>[
        DropdownButtonFormField<String>(
          initialValue: supportPlan,
          decoration: const InputDecoration(labelText: 'Support plan'),
          items: _supportPlans,
          onChanged: (value) => setState(() => supportPlan = value ?? supportPlan),
        ),
        DropdownButtonFormField<String>(
          initialValue: supportHours,
          decoration: const InputDecoration(labelText: 'Support hours'),
          items: _supportHours,
          onChanged: (value) => setState(() => supportHours = value ?? supportHours),
        ),
        _requiredField(field('support_channels'), 'Support channels (comma separated)'),
        _requiredField(field('p1_minutes'), 'Requested P1 response minutes', number: true),
        _requiredField(field('p2_minutes'), 'Requested P2 response minutes', number: true),
        _requiredField(field('p3_hours'), 'Requested P3 response hours', number: true),
        _switch('Onboarding required', onboardingRequired, (value) => onboardingRequired = value),
        _switch('Training required', trainingRequired, (value) => trainingRequired = value),
        _switch('Architecture review required', architectureReview, (value) => architectureReview = value),
        _switch('Migration assistance required', migrationAssistance, (value) => migrationAssistance = value),
        _switch('Named technical contact required', namedContact, (value) => namedContact = value),
        _switch('Technical account manager required', tamRequired, (value) => tamRequired = value),
        _switch('Incident bridge required', incidentBridge, (value) => incidentBridge = value),
        _optionalField(field('support_notes'), 'Support notes', maxLines: 6),
        DropdownButtonFormField<String>(
          initialValue: availability,
          decoration: const InputDecoration(labelText: 'Requested availability'),
          items: _availabilityTargets,
          onChanged: (value) => setState(() => availability = value ?? availability),
        ),
        _requiredField(
          field('maintenance_notice'),
          'Maintenance notice hours',
          number: true,
        ),
        DropdownButtonFormField<String>(
          initialValue: measurementWindow,
          decoration: const InputDecoration(labelText: 'Measurement window'),
          items: _measurementWindows,
          onChanged: (value) => setState(
            () => measurementWindow = value ?? measurementWindow,
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: errorBudgetPolicy,
          decoration: const InputDecoration(labelText: 'Error-budget policy'),
          items: _errorBudgetPolicies,
          onChanged: (value) => setState(
            () => errorBudgetPolicy = value ?? errorBudgetPolicy,
          ),
        ),
        _switch('Service credits requested', serviceCredits, (value) => serviceCredits = value),
        _switch(
          'Accept SLO-only evaluation phase',
          acceptsEvaluationSlo,
          (value) => acceptsEvaluationSlo = value,
        ),
        _optionalField(field('slo_notes'), 'SLO/SLA notes', maxLines: 6),
      ]),
      _section('Procurement and B2B terms', <Widget>[
        DropdownButtonFormField<String>(
          initialValue: contractPath,
          decoration: const InputDecoration(labelText: 'Contract path'),
          items: _contractPaths,
          onChanged: (value) => setState(() => contractPath = value ?? contractPath),
        ),
        _requiredField(
          field('requested_documents'),
          'Requested documents (comma separated)',
        ),
        _requiredField(field('term_months'), 'Term months', number: true),
        _optionalField(
          field('termination_notice'),
          'Termination notice days',
          number: true,
        ),
        DropdownButtonFormField<String>(
          initialValue: billingCadence,
          decoration: const InputDecoration(labelText: 'Billing cadence'),
          items: _billingCadences,
          onChanged: (value) => setState(
            () => billingCadence = value ?? billingCadence,
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: paymentTerms,
          decoration: const InputDecoration(labelText: 'Payment terms'),
          items: _paymentTerms,
          onChanged: (value) => setState(() => paymentTerms = value ?? paymentTerms),
        ),
        DropdownButtonFormField<String>(
          initialValue: currency,
          decoration: const InputDecoration(labelText: 'Currency'),
          items: _currencies,
          onChanged: (value) => setState(() => currency = value ?? currency),
        ),
        _switch('Auto-renewal allowed', autoRenewal, (value) => autoRenewal = value),
        _switch(
          'Termination for convenience requested',
          terminationForConvenience,
          (value) => terminationForConvenience = value,
        ),
        _switch('Purchase order required', purchaseOrderRequired, (value) => purchaseOrderRequired = value),
        _switch('Vendor portal required', vendorPortalRequired, (value) => vendorPortalRequired = value),
        _switch('Security review required', securityReviewRequired, (value) => securityReviewRequired = value),
        _switch('Legal review required', legalReviewRequired, (value) => legalReviewRequired = value),
        _optionalField(field('governing_law'), 'Governing-law preference'),
        _optionalField(field('venue'), 'Venue preference'),
        _optionalField(field('liability'), 'Liability-cap preference', maxLines: 4),
        _optionalField(field('indemnity'), 'Indemnity requirements', maxLines: 4),
        _optionalField(field('insurance'), 'Insurance requirements', maxLines: 4),
        _optionalField(field('audit_rights'), 'Audit-rights requirements', maxLines: 4),
        _optionalField(field('data_processing'), 'Data-processing/DPA requirements', maxLines: 6),
        _optionalField(field('ip_requirements'), 'Intellectual-property requirements', maxLines: 4),
        _optionalField(field('procurement_notes'), 'Procurement notes', maxLines: 6),
      ]),
      _section('Commercial and signatory', <Widget>[
        DropdownButtonFormField<String>(
          initialValue: budgetBand,
          decoration: const InputDecoration(labelText: 'Budget band'),
          items: _budgetBands,
          onChanged: (value) => setState(() => budgetBand = value ?? budgetBand),
        ),
        DropdownButtonFormField<String>(
          initialValue: pricingModel,
          decoration: const InputDecoration(labelText: 'Pricing model preference'),
          items: _pricingModels,
          onChanged: (value) => setState(() => pricingModel = value ?? pricingModel),
        ),
        _optionalField(field('monthly_budget'), 'Monthly budget cents', number: true),
        _optionalField(
          field('implementation_budget'),
          'Implementation budget cents',
          number: true,
        ),
        _requiredField(field('billing_name'), 'Billing contact name'),
        _requiredField(
          field('billing_email'),
          'Billing contact email',
          keyboardType: TextInputType.emailAddress,
        ),
        _requiredField(field('billing_role'), 'Billing contact role'),
        _requiredField(field('signatory_name'), 'Authorized signatory name'),
        _requiredField(
          field('signatory_email'),
          'Authorized signatory email',
          keyboardType: TextInputType.emailAddress,
        ),
        _requiredField(field('signatory_role'), 'Authorized signatory role'),
        _switch('Tax exempt', taxExempt, (value) => taxExempt = value),
        _switch('Reseller or partner', reseller, (value) => reseller = value),
        _optionalField(field('commercial_notes'), 'Commercial notes', maxLines: 6),
        _optionalField(
          field('additional_requirements'),
          'Additional requirements',
          maxLines: 8,
        ),
      ]),
      _acknowledgement(
        value: authorized,
        label: 'I am authorized to submit for this organization.',
        onChanged: (value) => setState(() => authorized = value),
      ),
      _acknowledgement(
        value: nonBindingAcknowledged,
        label: 'I understand requested terms, support, SLOs, and SLAs are non-binding until signed.',
        onChanged: (value) => setState(() => nonBindingAcknowledged = value),
      ),
      _acknowledgement(
        value: noSecretsAcknowledged,
        label: 'I did not include credentials or secrets.',
        onChanged: (value) => setState(() => noSecretsAcknowledged = value),
      ),
      _acknowledgement(
        value: privacyAccepted,
        label: 'I accept the current privacy notice.',
        onChanged: (value) => setState(() => privacyAccepted = value),
      ),
      FilledButton.icon(
        key: const ValueKey<String>('submit-fiducia-enterprise-application'),
        onPressed: submitting ? null : _submit,
        icon: const Icon(Icons.domain_verification_outlined),
        label: const Text('Submit protected enterprise application'),
      ),
      resultPanel(),
    ],
  );

  Widget _switch(String label, bool value, ValueChanged<bool> assign) =>
      SwitchListTile(
        value: value,
        title: Text(label),
        onChanged: (next) => setState(() => assign(next)),
      );

  Future<void> _submit() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    if (!authorized ||
        !nonBindingAcknowledged ||
        !noSecretsAcknowledged ||
        !privacyAccepted ||
        !acceptsEvaluationSlo) {
      setState(() => errorMessage = 'Complete every required authority and service-level acknowledgement.');
      return;
    }
    final payload = <String, Object?>{
      'primary_contact': <String, Object?>{
        'email': field('contact_email').text.trim(),
        'full_name': field('contact_name').text.trim(),
        'role': field('contact_role').text.trim(),
        if (field('contact_phone').text.trim().isNotEmpty)
          'phone': field('contact_phone').text.trim(),
        if (field('contact_timezone').text.trim().isNotEmpty)
          'timezone': field('contact_timezone').text.trim(),
        'preferred_contact': 'email',
      },
      'organization': <String, Object?>{
        'legal_name': field('organization_name').text.trim(),
        'country': field('organization_country').text.trim(),
        if (field('organization_region').text.trim().isNotEmpty)
          'state_or_region': field('organization_region').text.trim(),
        'company_size': companySize,
        'industry': field('organization_industry').text.trim(),
      },
      'project': <String, Object?>{
        'name': field('project_name').text.trim(),
        'stage': projectStage,
        'use_case_summary': field('use_case').text.trim(),
        'desired_start_date': field('start_date').text.trim(),
        'decision_timeline': decisionTimeline,
        if (field('production_deadline').text.trim().isNotEmpty)
          'production_deadline': field('production_deadline').text.trim(),
        'estimated_internal_users': _integer(field('internal_users').text),
        'estimated_end_users': _integer(field('end_users').text),
        'environment_count': _integer(field('environment_count').text),
      },
      'technical': <String, Object?>{
        'capabilities': _csv(field('capabilities').text),
        'deployment_models': _csv(field('deployment_models').text),
        'client_languages': _csv(field('client_languages').text),
        'integrations': _csv(field('integrations').text),
        'regions': _csv(field('regions').text),
        'average_operations_per_second': _integer(field('average_ops').text),
        'peak_operations_per_second': _integer(field('peak_ops').text),
        'estimated_active_keys': _integer(field('active_keys').text),
        'maximum_payload_bytes': _integer(field('payload_bytes').text),
        'retention_days': _integer(field('retention_days').text),
        'consistency_expectation': consistency,
        'latency_p95_ms': _integer(field('p95_ms').text),
        'latency_p99_ms': _integer(field('p99_ms').text),
        'failover_seconds': _integer(field('failover_seconds').text),
        'rpo_seconds': _integer(field('rpo_seconds').text),
        'rto_seconds': _integer(field('rto_seconds').text),
        'private_networking_required': privateNetworking,
        'offline_or_edge_required': offlineEdge,
        'data_classes': _csv(field('data_classes').text),
        if (field('current_stack').text.trim().isNotEmpty)
          'current_stack': field('current_stack').text.trim(),
        if (field('migration_source').text.trim().isNotEmpty)
          'migration_source': field('migration_source').text.trim(),
        if (field('architecture_notes').text.trim().isNotEmpty)
          'architecture_notes': field('architecture_notes').text.trim(),
      },
      'security': <String, Object?>{
        'compliance_frameworks': _csv(field('compliance').text),
        'sso_required': ssoRequired,
        'scim_required': scimRequired,
        'mfa_required': mfaRequired,
        'mtls_required': mtlsRequired,
        'customer_managed_keys_required': cmkRequired,
        'data_residency_required': residencyRequired,
        'data_residency_locations': _csv(field('residency_locations').text),
        'audit_log_required': auditLogRequired,
        'audit_retention_days': _integer(field('audit_retention').text),
        'security_questionnaire_required': securityQuestionnaire,
        if (field('security_notes').text.trim().isNotEmpty)
          'additional_security_requirements': field('security_notes').text.trim(),
      },
      'support': <String, Object?>{
        'support_plan': supportPlan,
        'support_hours': supportHours,
        'channels': _csv(field('support_channels').text),
        'onboarding_required': onboardingRequired,
        'training_required': trainingRequired,
        'architecture_review_required': architectureReview,
        'migration_assistance_required': migrationAssistance,
        'named_technical_contact_required': namedContact,
        'technical_account_manager_required': tamRequired,
        'incident_bridge_required': incidentBridge,
        'requested_p1_response_minutes': _integer(field('p1_minutes').text),
        'requested_p2_response_minutes': _integer(field('p2_minutes').text),
        'requested_p3_response_hours': _integer(field('p3_hours').text),
        if (field('support_notes').text.trim().isNotEmpty)
          'support_notes': field('support_notes').text.trim(),
      },
      'service_levels': <String, Object?>{
        'requested_availability': availability,
        'service_credit_requested': serviceCredits,
        'maintenance_notice_hours': _integer(field('maintenance_notice').text),
        'error_budget_policy': errorBudgetPolicy,
        'accepts_slo_not_sla_during_evaluation': true,
        'measurement_window': measurementWindow,
        if (field('slo_notes').text.trim().isNotEmpty)
          'slo_notes': field('slo_notes').text.trim(),
      },
      'procurement': <String, Object?>{
        'contract_path': contractPath,
        'requested_documents': _csv(field('requested_documents').text),
        'term_months': _integer(field('term_months').text),
        'auto_renewal_allowed': autoRenewal,
        'termination_for_convenience_requested': terminationForConvenience,
        'termination_notice_days': _integer(field('termination_notice').text),
        'billing_cadence': billingCadence,
        'payment_terms': paymentTerms,
        'currency': currency,
        'purchase_order_required': purchaseOrderRequired,
        'vendor_portal_required': vendorPortalRequired,
        'security_review_required': securityReviewRequired,
        'legal_review_required': legalReviewRequired,
        if (field('governing_law').text.trim().isNotEmpty)
          'governing_law_preference': field('governing_law').text.trim(),
        if (field('venue').text.trim().isNotEmpty)
          'venue_preference': field('venue').text.trim(),
        if (field('liability').text.trim().isNotEmpty)
          'liability_cap_preference': field('liability').text.trim(),
        if (field('indemnity').text.trim().isNotEmpty)
          'indemnity_requirements': field('indemnity').text.trim(),
        if (field('insurance').text.trim().isNotEmpty)
          'insurance_requirements': field('insurance').text.trim(),
        if (field('audit_rights').text.trim().isNotEmpty)
          'audit_rights_requirements': field('audit_rights').text.trim(),
        if (field('data_processing').text.trim().isNotEmpty)
          'data_processing_requirements': field('data_processing').text.trim(),
        if (field('ip_requirements').text.trim().isNotEmpty)
          'intellectual_property_requirements': field('ip_requirements').text.trim(),
        if (field('procurement_notes').text.trim().isNotEmpty)
          'procurement_notes': field('procurement_notes').text.trim(),
      },
      'commercial': <String, Object?>{
        'budget_band': budgetBand,
        'pricing_model_preference': pricingModel,
        'estimated_monthly_budget_cents': _integer(field('monthly_budget').text),
        'estimated_implementation_budget_cents': _integer(
          field('implementation_budget').text,
        ),
        'billing_contact': <String, Object?>{
          'email': field('billing_email').text.trim(),
          'full_name': field('billing_name').text.trim(),
          'role': field('billing_role').text.trim(),
        },
        'authorized_signatory': <String, Object?>{
          'email': field('signatory_email').text.trim(),
          'full_name': field('signatory_name').text.trim(),
          'role': field('signatory_role').text.trim(),
        },
        'tax_exempt': taxExempt,
        'reseller_or_partner': reseller,
        if (field('commercial_notes').text.trim().isNotEmpty)
          'commercial_notes': field('commercial_notes').text.trim(),
      },
      if (field('additional_requirements').text.trim().isNotEmpty)
        'additional_requirements': field('additional_requirements').text.trim(),
      'authorized_to_submit': true,
      'acknowledges_requested_terms_are_non_binding': true,
      'acknowledges_no_credentials_or_secrets': true,
      'privacy_notice_accepted': true,
    };
    await submitPayload(
      path: '/v1/enterprise-applications',
      schema: 'EnterpriseApplicationRequest',
      payload: payload,
    );
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }
}

class SupportAndContractPage extends StatelessWidget {
  const SupportAndContractPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Support and contract boundary')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: const <Widget>[
          _InfoCard(
            title: 'Engineering SLO',
            body:
                'An internal measured reliability target and error-budget policy. It guides operations but is not automatically a customer remedy.',
          ),
          _InfoCard(
            title: 'Contractual SLA',
            body:
                'A signed commitment defining covered services, measurement, exclusions, maintenance, support clocks, and any service-credit remedy.',
          ),
          _InfoCard(
            title: 'Support model',
            body:
                'Applicants may request business-hours, 24×5, or 24×7 coverage, named technical contacts, architecture review, migration assistance, training, a TAM, and incident bridges.',
          ),
          _InfoCard(
            title: 'B2B documents',
            body:
                'The application can request an MSA, SOW, order form, SLA, DPA, NDA, acceptable-use policy, security addendum, insurance evidence, tax forms, or accessibility documentation.',
          ),
          _InfoCard(
            title: 'Human review',
            body:
                'Requested availability, response times, liability, indemnity, insurance, governing law, audit rights, data-processing terms, and customer paper remain unaccepted until reviewed and signed.',
          ),
        ],
      ),
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(body),
        ],
      ),
    ),
  );
}

class _FormScaffold extends StatelessWidget {
  const _FormScaffold({
    required this.title,
    required this.notice,
    required this.children,
  });

  final String title;
  final String notice;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final formState = context.findAncestorStateOfType<State<StatefulWidget>>();
    final formKey = switch (formState) {
      _QuotePageState state => state.formKey,
      _PreInterestPageState state => state.formKey,
      _EnterpriseApplicationPageState state => state.formKey,
      _ => GlobalKey<FormState>(),
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(notice),
                ),
              ),
              const SizedBox(height: 12),
              ...children.expand(
                (child) => <Widget>[child, const SizedBox(height: 12)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _section(String title, List<Widget> children) => Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ...children.expand(
          (child) => <Widget>[child, const SizedBox(height: 10)],
        ),
      ],
    ),
  ),
);

Widget _requiredField(
  TextEditingController controller,
  String label, {
  bool number = false,
  int maxLines = 1,
  TextInputType? keyboardType,
}) => TextFormField(
  controller: controller,
  decoration: InputDecoration(labelText: label),
  keyboardType: keyboardType ?? (number ? TextInputType.number : null),
  maxLines: maxLines,
  validator: (value) => value == null || value.trim().isEmpty ? 'Required' : null,
);

Widget _optionalField(
  TextEditingController controller,
  String label, {
  bool number = false,
  int maxLines = 1,
}) => TextFormField(
  controller: controller,
  decoration: InputDecoration(labelText: label),
  keyboardType: number ? TextInputType.number : null,
  maxLines: maxLines,
);

Widget _acknowledgement({
  required bool value,
  required String label,
  required ValueChanged<bool> onChanged,
}) => CheckboxListTile(
  value: value,
  title: Text(label),
  controlAffinity: ListTileControlAffinity.leading,
  onChanged: (next) => onChanged(next ?? false),
);

List<String> _csv(String value) => value
    .split(',')
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toSet()
    .toList(growable: false);

int _integer(String value) => int.tryParse(value.trim()) ?? 0;

DropdownMenuItem<String> _item(String value, String label) =>
    DropdownMenuItem<String>(value: value, child: Text(label));

final List<DropdownMenuItem<String>> _companySizes = <DropdownMenuItem<String>>[
  _item('employees_1_10', '1–10'),
  _item('employees_11_50', '11–50'),
  _item('employees_51_200', '51–200'),
  _item('employees_201_1000', '201–1,000'),
  _item('employees_1001_5000', '1,001–5,000'),
  _item('employees_5001_plus', '5,001+'),
];
final List<DropdownMenuItem<String>> _deploymentModels = <DropdownMenuItem<String>>[
  _item('evaluation', 'Evaluation'),
  _item('managed_multi_tenant', 'Managed multi-tenant'),
  _item('managed_dedicated', 'Managed dedicated'),
  _item('customer_kubernetes', 'Customer Kubernetes'),
  _item('customer_cloud', 'Customer cloud'),
  _item('hybrid', 'Hybrid'),
];
final List<DropdownMenuItem<String>> _supportPlans = <DropdownMenuItem<String>>[
  _item('community', 'Community / evaluation'),
  _item('standard', 'Standard'),
  _item('priority', 'Priority'),
  _item('enterprise', 'Enterprise'),
  _item('custom', 'Custom'),
];
final List<DropdownMenuItem<String>> _budgetBands = <DropdownMenuItem<String>>[
  _item('unknown', 'Unknown'),
  _item('under_500_monthly', 'Under $500/month'),
  _item('monthly_500_2000', '$500–$2,000/month'),
  _item('monthly_2000_10000', '$2,000–$10,000/month'),
  _item('monthly_10000_50000', '$10,000–$50,000/month'),
  _item('monthly_50000_plus', '$50,000+/month'),
  _item('custom_contract', 'Custom contract'),
];
final List<DropdownMenuItem<String>> _startWindows = <DropdownMenuItem<String>>[
  _item('immediate', 'Immediate'),
  _item('within_30_days', 'Within 30 days'),
  _item('within_90_days', 'Within 90 days'),
  _item('within_6_months', 'Within 6 months'),
  _item('later', 'Later'),
  _item('exploring', 'Exploring'),
];
final List<DropdownMenuItem<String>> _projectStages = <DropdownMenuItem<String>>[
  _item('research', 'Research'),
  _item('prototype', 'Prototype'),
  _item('pilot', 'Pilot'),
  _item('pre_production', 'Pre-production'),
  _item('production', 'Production'),
  _item('migration', 'Migration'),
];
final List<DropdownMenuItem<String>> _consistencyLevels = <DropdownMenuItem<String>>[
  _item('linearizable', 'Linearizable'),
  _item('serializable', 'Serializable'),
  _item('read_your_writes', 'Read your writes'),
  _item('eventual', 'Eventual'),
  _item('unsure', 'Unsure'),
];
final List<DropdownMenuItem<String>> _supportHours = <DropdownMenuItem<String>>[
  _item('business_hours', 'Business hours'),
  _item('twenty_four_by_five', '24×5'),
  _item('twenty_four_by_seven', '24×7'),
];
final List<DropdownMenuItem<String>> _availabilityTargets = <DropdownMenuItem<String>>[
  _item('best_effort_beta', 'Best-effort beta'),
  _item('availability_99_0', '99.0% request'),
  _item('availability_99_5', '99.5% request'),
  _item('availability_99_9', '99.9% request'),
  _item('availability_99_95', '99.95% request'),
  _item('custom', 'Custom'),
];
final List<DropdownMenuItem<String>> _measurementWindows = <DropdownMenuItem<String>>[
  _item('monthly', 'Monthly'),
  _item('rolling_30_day', 'Rolling 30 day'),
  _item('quarterly', 'Quarterly'),
  _item('custom', 'Custom'),
];
final List<DropdownMenuItem<String>> _errorBudgetPolicies = <DropdownMenuItem<String>>[
  _item('informational', 'Informational'),
  _item('release_freeze', 'Release freeze'),
  _item('joint_review', 'Joint review'),
  _item('custom', 'Custom'),
];
final List<DropdownMenuItem<String>> _contractPaths = <DropdownMenuItem<String>>[
  _item('online_terms', 'Online terms'),
  _item('fiducia_msa', 'Fiducia MSA'),
  _item('customer_msa', 'Customer MSA'),
  _item('sow_only', 'SOW only'),
  _item('public_sector_terms', 'Public-sector terms'),
  _item('custom', 'Custom'),
];
final List<DropdownMenuItem<String>> _billingCadences = <DropdownMenuItem<String>>[
  _item('monthly', 'Monthly'),
  _item('quarterly', 'Quarterly'),
  _item('annual', 'Annual'),
  _item('prepaid_commit', 'Prepaid commit'),
  _item('custom', 'Custom'),
];
final List<DropdownMenuItem<String>> _paymentTerms = <DropdownMenuItem<String>>[
  _item('card_due_on_receipt', 'Due on receipt'),
  _item('net_15', 'Net 15'),
  _item('net_30', 'Net 30'),
  _item('net_45', 'Net 45'),
  _item('net_60', 'Net 60'),
  _item('custom', 'Custom'),
];
final List<DropdownMenuItem<String>> _currencies = <DropdownMenuItem<String>>[
  _item('USD', 'USD'),
  _item('EUR', 'EUR'),
  _item('GBP', 'GBP'),
  _item('CAD', 'CAD'),
  _item('AUD', 'AUD'),
  _item('other', 'Other'),
];
final List<DropdownMenuItem<String>> _pricingModels = <DropdownMenuItem<String>>[
  _item('usage_based', 'Usage based'),
  _item('per_cluster', 'Per cluster'),
  _item('per_environment', 'Per environment'),
  _item('platform_subscription', 'Platform subscription'),
  _item('committed_spend', 'Committed spend'),
  _item('custom', 'Custom'),
];
