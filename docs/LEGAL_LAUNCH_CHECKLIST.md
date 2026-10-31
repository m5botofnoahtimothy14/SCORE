# Legal launch checklist — India

This is a practical launch checklist, not legal advice. Before publishing or
accepting school/student data, have an Indian technology/privacy lawyer review
the final policies, contracts, data flows and your entity choice. The owner
details below must be confirmed by the person who will legally operate the
service; do not invent a GSTIN, registered address, grievance contact, or
registration number in the app.

## Owner information to confirm before release

- Legal owner/entity name: `Noah Timothy Keba Joseph` is currently shown in the
  app as the developer attribution; confirm whether this is the actual
  proprietor or replace it with the registered entity name.
- Principal place of business, official support email, grievance contact and
  response process.
- Whether each school is an independent data controller/fiduciary or TeachCross
  is the primary operator, and the signed data-processing terms that allocate
  responsibilities.
- The production domain, Android application ID, Apple developer account holder
  and Google Play developer account holder.

## Registrations and filings to assess

| Item | When it matters | Action before launch |
| --- | --- | --- |
| Business structure | Contracting, invoicing, liability and banking | Choose sole proprietorship, LLP or company with an accountant/lawyer; obtain PAN/current account as appropriate. |
| GST | Taxable supply/turnover or another compulsory-registration trigger | Confirm with a GST professional. CBIC describes the usual INR 20 lakh aggregate-turnover threshold and exceptions; registration is electronic. |
| Trademark | Protecting `SCORE+`, `TeachCross`, logo and CRIMSON branding | Search first, select the applicable class(es), then file Form TM-A through IP India. Do not claim `®` until it is registered; use `™` only after counsel confirms the claim is appropriate. |
| Copyright/IP assignments | Developers, designers and contractors contributed to app/code/assets | Execute written IP assignment/confidentiality agreements; retain provenance for all curriculum and media assets. |
| School contracts | Every pilot/production school | Sign a service agreement, data-processing terms, security schedule, retention/deletion schedule, support/SLA and incident-notice process. |
| App-store declarations | Google Play / App Store release | Complete Data safety/App Privacy disclosures from the final data inventory, including student data, AI processing, retention and deletion. |

## Data, children and AI controls

- Publish a separate Privacy Notice and parent/guardian-facing notice. Include
  what is collected, why, the school/operator roles, recipients/sub-processors,
  retention, contact/grievance path and the rights/request process.
- Because the app serves children, have counsel validate the consent/verifiable
  parental-consent flow and the age/guardian assumptions for each school.
- Before enabling AI Ask, disclose that the question is sent to the configured
  AI provider for the limited educational purpose, identify the provider in the
  privacy notice, and prohibit training/secondary use in the provider contract
  where available.
- Keep the reviewed-corpus and human-teacher escalation controls in
  `AI_ASK_PRODUCTION.md`. Do not process sensitive personal content in AI Ask
  unless the legal basis, notices and provider terms cover it.
- Review your grievance/redressal, notice-and-takedown and moderation process
  against the IT Rules with counsel. The app's existing moderation/audit design
  supports these processes but is not itself a legal registration.

## App changes still needed after owner confirmation

The app currently has placeholder support contact details in
`apps/mobile/lib/core/config/app_config.dart`. Replace them with verified
production contacts. Update the EULA/privacy notice with the confirmed legal
owner, registered/official address, grievance contact, retention terms and
effective version before release. Do not use the current EULA as a substitute
for a reviewed privacy notice or school contract.

## Official starting points

- The [Digital Personal Data Protection Act, 2023](https://www.meity.gov.in/writereaddata/files/Digital%20Personal%20Data%20Protection%20Act%202023.pdf)
  and the [DPDP Rules 2025 materials](https://www.meity.gov.in/documents/act-and-policies/digital-personal-data-protection-rules-2025-gDOxUjMtQWa?pageTitle=Digital-Personal-Data-Protection-Rules-2025%3B).
- MeitY's [IT Rules, 2021](https://www.meity.gov.in/static/uploads/2026/02/550681ab908f8afb135b0ad42816a1c9.pdf).
- CBIC's [GST registration FAQs](https://cbic-gst.gov.in/pdf/faq-manual/faqs-registration.pdf).
- IP India's [trademark filing process](https://ipindia.gov.in/application-workflow/trademark-filing-process).

