// End User Licence Agreement and Acceptable Use Policy.
//
// One screen, two modes:
//   * consent mode (first boot) — asks for an explicit tick and offers Decline;
//   * acceptedMode (profile)     — read-only, shows when the user accepted.
// The same content is rendered either way, so the terms a user agreed to can
// never drift from the terms the app shows later.
import 'package:flutter/material.dart';

import '../../../core/legal/eula_gate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/developer_signature.dart';

/// One numbered clause of the agreement.
class EulaSection {
  final String number;
  final String heading;
  final List<String> paragraphs;

  const EulaSection({
    required this.number,
    required this.heading,
    required this.paragraphs,
  });
}

const String kEulaTitle = 'End User Licence Agreement';
const String kEulaEffectiveDate = '18 October 2026';
const String kEulaPreamble =
    'SCORE+ is a school communication tool. Before you can use it, please '
    'read this agreement. It explains what the app does, what we ask of you, '
    'and how we protect the people who use it. If anything here is unclear, '
    'contact your school office or our support team before you accept.';

const List<EulaSection> kEulaSections = <EulaSection>[
  EulaSection(
    number: '1',
    heading: 'Acceptance of Terms',
    paragraphs: [
      'By ticking the consent box and selecting "Accept and continue", you confirm that you have read, understood and agree to be bound by this End User Licence Agreement and Acceptable Use Policy, together with any policy referenced in it.',
      'If you do not agree, you must select "Decline" and stop using the app. Declining closes your session and no SCORE+ data will be available to you on this device.',
      'You may not use SCORE+ on behalf of anyone else, and you may not use it if you are barred under these terms or under the safeguarding rules of your school.',
    ],
  ),
  EulaSection(
    number: '2',
    heading: 'Purpose of the App',
    paragraphs: [
      'SCORE+ exists to help schools communicate with each other: notices from leadership, messages between teachers and students or parents, class updates, and school announcements.',
      'The app is a communication aid. It is not an official record system. Attendance registers, marksheets, timetables, report cards and any other formal school record remain the responsibility of the school, and where SCORE+ and an official record disagree, the official record is correct.',
      'The school that issued your account decides what content you may post and to whom you may post it. SCORE+ does not verify the accuracy of announcements or messages, except where automatic moderation is triggered.',
    ],
  ),
  EulaSection(
    number: '3',
    heading: 'Account and Eligibility',
    paragraphs: [
      'Access is limited to people the school has authorised. You activate your account with the school-issued identifier and activation code, or with a one-time verification code sent to the phone number your school has on file.',
      'Your account is personal. Do not share your activation code, verification code, student or staff identifier, or password with anyone, including people who claim to be school staff. School staff will never ask you for them inside a chat message.',
      'You are responsible for everything done from your account. Tell your school immediately if you believe your account has been used by someone else, so access can be suspended and reviewed.',
      'Accounts may be suspended, deactivated or removed by the school or by SCORE+ when these terms are breached, when an account is no longer eligible, or when required by law.',
    ],
  ),
  EulaSection(
    number: '4',
    heading: 'Acceptable Use',
    paragraphs: [
      'You must not use SCORE+ to harass, bully, threaten, humiliate or target anyone. This applies to direct messages, group conversations, announcements, images, audio and profile information, and it applies whether or not the other person uses the app.',
      'You must not upload or share nudity, sexual content, pornography, or any content that is obscene, graphic or humiliating. You must not share hate speech, slurs or content that promotes hatred against any religion, caste, race, gender, disability or sexual orientation.',
      'You must not post or distribute illegal content, content that infringes someone else\'s rights, content that encourages self-harm or violence, or content that could reasonably be used to identify, track or endanger a child.',
      'You must not impersonate a teacher, a student, a parent or any other person, and you must not attempt to enter another person\'s account, read their messages, or access a conversation you are not a member of.',
      'You must respect your school\'s safeguarding rules at all times. Where school rules are stricter than these terms, the school\'s rules apply.',
    ],
  ),
  EulaSection(
    number: '5',
    heading: 'Content Moderation and Safeguarding',
    paragraphs: [
      'Messages and images are automatically screened when they are sent. Screening looks for the categories of content described in section 4, including harassment, nudity, hate speech and threats.',
      'If screening flags content, the message may be held rather than delivered so that it can be reviewed. Depending on what was detected, the content may be escalated to the safeguarding staff of your school, and in serious cases the school may be notified under its own child protection procedures.',
      'Automated screening is a safety net, not a substitute for judgement. It can miss content and it can flag content that turns out to be harmless. Held messages are reviewed against these terms, and the decision is recorded.',
      'Anyone may report content in the app. Good-faith reports are taken seriously. Knowingly and repeatedly reporting content in order to harass or remove another person\'s legitimate message is itself a breach of these terms. Reports that are found to be false or made in bad faith are handled in line with your school\'s disciplinary process.',
      'If a user is a child and is at risk of harm, SCORE+ will follow the safeguarding escalation path agreed with the school, which may include limiting access, preserving relevant content for review, and notifying the school\'s designated safeguarding lead.',
    ],
  ),
  EulaSection(
    number: '6',
    heading: 'Privacy and Data Protection',
    paragraphs: [
      'SCORE+ processes personal data in accordance with the Digital Personal Data Protection Act, 2023 (India) and the rules made under it, together with any other law that applies to your school.',
      'Your data is processed for the school\'s lawful purpose: to deliver the communication services the school has commissioned, and to keep those services safe. Data is not collected for unrelated purposes.',
      'Personal data is retained only as long as it is needed for that purpose and for the retention periods the school and the law require. Messages, images and account records are deleted or anonymised when that purpose ends, subject to any legal hold, safeguarding review or school record-keeping obligation.',
      'Your data is not sold. It is not shared with advertisers or data brokers. Access is limited to you, the other members of your conversations, and staff of your school who are authorised to review content for safeguarding or administration.',
      'You may ask what personal data SCORE+ holds about you, request correction, and ask for information about the processing of your data, by contacting your school or our support team. Requests are handled with the school, which remains the primary holder of your records.',
    ],
  ),
  EulaSection(
    number: '7',
    heading: 'Child Safety and Age',
    paragraphs: [
      'SCORE+ is used by school staff and by students under school supervision. It is not a general social network and is not intended for unsupervised use by children.',
      'Most users are below the age of 18, so heightened safeguards apply. Messages and images are screened, conversations are limited to authorised participants, and content that suggests a child is unsafe is escalated to the school\'s safeguarding staff.',
      'If you are a parent or carer and you believe a child is being harmed through SCORE+, contact the school\'s safeguarding lead. If there is an immediate risk to a child\'s safety, contact the relevant emergency services first.',
      'You must not use SCORE+ to contact, groom or arrange to meet a child outside the supervision arrangements of the school, and you must report any such behaviour.',
    ],
  ),
  EulaSection(
    number: '8',
    heading: 'Intellectual Property',
    paragraphs: [
      'SCORE+, its software, its design and its documentation are owned by Noah Timothy Keba Joseph. SCORE+™ is a trademark of Noah Timothy Keba Joseph. CRIMSON is a proprietary brand of Noah Timothy Keba Joseph.',
      'Copyright © 2026 Noah Timothy Keba Joseph. All rights reserved. No part of SCORE+ may be copied, reproduced, modified, distributed, reverse engineered or used to create a derivative work without prior written permission, except where such use is permitted by law.',
      'You retain the rights to the content you post. By posting, you grant SCORE+ a limited, worldwide, royalty-free licence to host, store, transmit, display and screen that content for the sole purpose of operating the service for your school. That licence ends when the content is deleted, except for copies retained under a legal hold or safeguarding review.',
    ],
  ),
  EulaSection(
    number: '9',
    heading: 'SMS Notifications',
    paragraphs: [
      'When your school has enabled SMS verification, SCORE+ sends a one-time verification code to the phone number your school has on file, so that your identity can be confirmed before your account is activated. That number is used for one-time verification codes and for messages your school sends to you.',
      'SMS messages are sent through the SMS gateway configured by your school. Standard carrier rates may apply to receive them, and delivery depends on your mobile network.',
      'Do not share a verification code with anyone, including anyone claiming to be from the school or from SCORE+ support. SCORE+ support will never ask you for a verification code.',
    ],
  ),
  EulaSection(
    number: '10',
    heading: 'Limitation of Liability and Governing Law',
    paragraphs: [
      'To the maximum extent permitted by law, SCORE+ is provided "as is" and without warranties of any kind, whether express or implied, including any implied warranty of merchantability, fitness for a particular purpose or non-infringement. We do not warrant that the app will be uninterrupted, error-free, or that communications will always be delivered immediately.',
      'To the maximum extent permitted by law, SCORE+ and its developer are not liable for indirect, incidental, special or consequential loss or damage, including loss of data, missed messages, or loss arising from reliance on SCORE+ as an official record. The app is a communication aid; it is not the school\'s record system.',
      'Nothing in this agreement excludes or limits liability for death or personal injury caused by negligence, for fraud or fraudulent misrepresentation, or for anything else that cannot lawfully be excluded.',
      'These terms are governed by the laws of India. The courts at Bengaluru, Karnataka, India have exclusive jurisdiction over any dispute arising out of or in connection with these terms, without prejudice to any mandatory safeguarding or statutory process available to the school or to any authority.',
    ],
  ),
  EulaSection(
    number: '11',
    heading: 'Changes to These Terms',
    paragraphs: [
      'We may update these terms from time to time, for example to reflect legal changes, new safeguarding requirements or new features. The effective date at the top of this screen always shows the version you are reading.',
      'When the terms change materially, you will be asked to read and accept them again the next time you open the app. The date on which you accepted the current version is recorded, and you can see it under Profile at any time.',
      'Continuing to use SCORE+ after a change takes effect means you accept the revised terms. If you do not accept them, select "Decline" and stop using the app.',
    ],
  ),
];

/// Full-screen, scrollable terms. Genuinely readable rather than clipped:
/// the whole document lives in one scroll view with generous type and spacing.
class EulaScreen extends StatefulWidget {
  /// Read-only mode: shows when the user accepted and hides the controls.
  final bool acceptedMode;
  final Future<void> Function(BuildContext context)? onAccepted;
  final Future<void> Function(BuildContext context)? onDeclined;

  const EulaScreen({
    super.key,
    this.acceptedMode = false,
    this.onAccepted,
    this.onDeclined,
  });

  @override
  State<EulaScreen> createState() => _EulaScreenState();
}

class _EulaScreenState extends State<EulaScreen> {
  // Never pre-checked: consent has to be a deliberate act.
  bool _accepted = false;
  bool _working = false;

  Future<void> _accept() async {
    if (!_accepted || _working) return;
    setState(() => _working = true);
    try {
      final handler = widget.onAccepted;
      if (handler != null) {
        await handler(context);
      } else {
        await EulaStore.accept();
        if (mounted) Navigator.of(context).maybePop();
      }
    } catch (error) {
      debugPrint('[CRIMSON] Could not record EULA acceptance: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not record your acceptance. Please try again.'),
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _decline() async {
    if (_working) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline the terms?'),
        content: const Text(
          'SCORE+ cannot be used without accepting the agreement. '
          'Your session will be closed and you will be returned to the '
          'school selection screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      final handler = widget.onDeclined;
      if (handler != null) {
        await handler(context);
      } else if (mounted) {
        Navigator.of(context).maybePop();
      }
    } catch (error) {
      debugPrint('[CRIMSON] Could not record EULA decline: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.acceptedMode ? 'Terms & EULA' : 'Before you continue'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const _EulaHeader(),
            const SizedBox(height: 20),
            Text(kEulaPreamble, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 24),
            for (final section in kEulaSections) ...[
              _EulaClause(section: section),
              const SizedBox(height: 22),
            ],
            const DeveloperSignature(compact: true),
            const SizedBox(height: 16),
            if (widget.acceptedMode)
              const _AcceptedBanner()
            else
              _ConsentCard(
                accepted: _accepted,
                working: _working,
                onChanged: _working
                    ? null
                    : (value) => setState(() => _accepted = value ?? false),
                onAccept: _accept,
                onDecline: _decline,
              ),
          ],
        ),
      ),
    );
  }
}

class _EulaHeader extends StatelessWidget {
  const _EulaHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand, AppColors.brandDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.26),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SCORE+™ · CRIMSON',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            kEulaTitle,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '& Acceptable Use Policy',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: 0.14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Effective date: $kEulaEffectiveDate',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Version ${EulaStore.version} · Governed by the laws of India',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EulaClause extends StatelessWidget {
  final EulaSection section;

  const _EulaClause({required this.section});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                section.number,
                style: const TextStyle(
                  color: AppColors.brandDark,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  section.heading,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final paragraph in section.paragraphs) ...[
          Text(
            paragraph,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _AcceptedBanner extends StatelessWidget {
  const _AcceptedBanner();

  @override
  Widget build(BuildContext context) {
    final acceptedOn = EulaStore.acceptedOnLabel();
    final message = acceptedOn.isEmpty
        ? 'You accepted these terms.'
        : 'You accepted these on $acceptedOn.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.success.withValues(alpha: 0.10),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            size: 20,
            color: AppColors.success,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'These terms stay available here whenever you need to read them.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  final bool accepted;
  final bool working;
  final ValueChanged<bool?>? onChanged;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _ConsentCard({
    required this.accepted,
    required this.working,
    required this.onChanged,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your consent',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Tick the box to accept the End User Licence Agreement and '
              'Acceptable Use Policy. You cannot use SCORE+ without '
              'accepting.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: accepted,
              onChanged: onChanged,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.brand,
              title: Text(
                'I have read and accept the terms above',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: accepted && !working ? onAccept : null,
                child: Text(working ? 'Working...' : 'Accept and continue'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: working ? null : onDecline,
                icon: const Icon(Icons.close, color: AppColors.danger),
                label: const Text(
                  'Decline',
                  style: TextStyle(color: AppColors.danger),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.danger.withValues(alpha: 0.35)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
