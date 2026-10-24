# SCORE Mentor Desk - Self-Hosted Video Deployment

## Components
- LiveKit Server (self-hosted) on a persistent VM/container host.
- coturn (TURN/STUN) with authenticated, time-limited credentials.
- Supabase Edge Function `issue-video-token` for room-scoped JWT issuance.
- Private storage for recordings (disabled by default).

## Required environment variables (Supabase Edge Functions)
- LIVEKIT_URL (wss://media.example.com)
- LIVEKIT_API_KEY
- LIVEKIT_API_SECRET
- TURN_URLS (optional, comma-separated)
- TURN_USERNAME / TURN_CREDENTIAL (or generate ephemeral)

## Ports / firewall
- LiveKit: TCP 7880 (HTTP/WebSocket), UDP 7881 (WebRTC), UDP 50000-60000 (media)
- coturn: UDP/TCP 3478, TCP 5349 (TLS), relay range UDP 49160-49200

## Capacity assumptions
- 1:1 calls, 720p, ~1.5 Mbps up/down per participant.
- 100 concurrent calls ~300 Mbps + TURN overhead.
- Recordings multiply storage: 1 hour ~1.1 GB at 2.5 Mbps.

## Recording policy
- Disabled by default. School must explicitly enable.
- Consent required from all participants (guardian consent where policy requires).
- Retention per school policy; automatic deletion after expiry.
