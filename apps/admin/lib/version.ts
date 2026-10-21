// Single source of truth for the version surfaced by the health endpoint.
// `npm_package_version` is not populated on the Vercel runtime, so the
// health check would otherwise always report 1.0.0.
export const APP_VERSION = '1.0.0'
