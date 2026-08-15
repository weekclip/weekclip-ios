import Foundation

/// The API's canonical response envelope.
///
/// Source of truth: weekclip-api `src/platform/http/envelope.ts`.
///
///     success -> { "data": T,                      "meta": { "traceId": "..." } }
///     failure -> { "error": { "code", "message" }, "traceId": "..." }
///
/// Note the asymmetry — `traceId` sits under `meta` on success and at the top
/// level on failure. That is the server's shape, not a transcription slip.
struct APIEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
  let data: T?
  let meta: APIMeta?
  let error: APIErrorBody?
  let traceId: String?
}

struct APIMeta: Decodable, Sendable {
  let traceId: String?
}

struct APIErrorBody: Decodable, Sendable {
  let code: String?
  let message: String?
}

/// List payloads nest one level further: `{ "data": { "items": [...] } }`.
/// `listStudiosForProfile` in weekclip-api returns `{ items }`, and the web
/// client reads `["data","items"]` first for that reason.
struct ItemsPayload<T: Decodable & Sendable>: Decodable, Sendable {
  let items: [T]
}
