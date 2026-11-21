# Tester Requests API

This page is the contract for the TestFlight tester requests. The website Pages Function, the
Gora Operations Dashboard, and the backend build against it. Do not change a name or a shape
without a change to all three clients.

---

## Flow

1. The website form posts to the Cloudflare Pages Function. The function checks Turnstile.
2. The function posts the form to `POST /api/v1/tester_requests` with the shared secret.
3. The backend saves a `pending` row and broadcasts `created` on Action Cable.
4. An admin taps Send TestFlight Invite. The dashboard calls the `invite` endpoint.
5. `TesterInviteJob` calls App Store Connect. The row becomes `invited` or `failed`.
6. Each change to a row broadcasts `updated`. A delete broadcasts `deleted`.

## Conventions

| Item | Rule |
|---|---|
| Response keys | camelCase, the same as the graph API. |
| Request keys | snake_case. The public endpoint also accepts `consentAt`. |
| Times | ISO 8601 with a UTC offset, for example `2026-11-22T16:00:00+08:00`. |
| Admin auth | `Authorization: Bearer <token>` from a user with the `admin` role. No token gives 401. A user that is not an admin gives 403. |

## TesterRequest JSON

```json
{
  "id": "uuid",
  "name": "string or null",
  "age": 21,
  "location": "string",
  "email": "string",
  "status": "pending | inviting | invited | failed | declined",
  "consentAt": "ISO 8601",
  "source": "website",
  "ascBetaTesterId": "string or null",
  "invitedAt": "ISO 8601 or null",
  "lastError": "string or null",
  "createdAt": "ISO 8601",
  "updatedAt": "ISO 8601"
}
```

### Status

| Status | Meaning | Next actions |
|---|---|---|
| `pending` | The form arrived. No admin action yet. | Invite, decline, delete |
| `inviting` | The invite job runs. | Wait. After 10 minutes, invite again. |
| `invited` | App Store Connect accepted the tester. | Resend, delete |
| `failed` | App Store Connect refused the request. `lastError` holds the reason. | Invite, decline, delete |
| `declined` | An admin declined the request. The backend sends no email. | Invite, delete |

A status that does not permit an action gives `409 { "error": "Conflict", "message": "..." }`.

## Public endpoint

### `POST /api/v1/tester_requests`

| Item | Value |
|---|---|
| Header | `X-Gora-Form-Key: <TESTER_FORM_KEY>`. The server compares it in constant time. |
| Body | `{ "name"?, "age", "location", "email", "consent_at", "source"? }` |
| 202 | `{ "status": "received" }` for each valid body, also for an email that is already on the list. |
| 401 | `{ "error": "Unauthorized" }`. The key is missing or wrong, or `TESTER_FORM_KEY` is not set. |
| 422 | `{ "error": "Invalid request", "errors": { "<field>": ["message"] } }`. Field names are camelCase. |
| 429 | `{ "error": "Too many requests. Please try again later." }` |

Validation:

| Field | Rule |
|---|---|
| `email` | Required. Valid format. 254 characters or fewer. The server stores it in lower case. |
| `age` | Required. A whole number from 16 to 120. A database check also refuses an age under 16. |
| `name` | Optional. 60 characters or fewer. A blank name is stored as null. |
| `location` | Required. 80 characters or fewer. |
| `consent_at` | Required. An ISO 8601 time. |
| `source` | Optional. Lowercase letters and underscores. The default is `website`. |

A second request with a known email (in any letter case) makes no new row. The server changes
only `updated_at` of the old row and broadcasts `updated`.

Rate limit `tester_requests/ip`: 5 requests per hour for each client IP. The key is the first
address in `X-Forwarded-For`. The Pages Function puts `CF-Connecting-IP` there. The global
`api/ip` limit also applies.

## Admin endpoints

| Method | Path | Success | Does |
|---|---|---|---|
| GET | `/api/v1/admin/tester_requests?status=&page=&per_page=` | 200 | Lists rows, newest first. |
| POST | `/api/v1/admin/tester_requests/:id/invite` | 202 | Sets `inviting` and starts the invite job. |
| POST | `/api/v1/admin/tester_requests/:id/resend` | 202 | Only for `invited`. Sets `inviting` and starts the resend job. |
| POST | `/api/v1/admin/tester_requests/:id/decline` | 200 | Only for `pending` or `failed`. Sets `declined`. |
| DELETE | `/api/v1/admin/tester_requests/:id` | 204 | Deletes the row. App Store Connect keeps the tester. |

List response:

```json
{ "data": [TesterRequest], "meta": { "page": 1, "perPage": 50, "total": 123 } }
```

`per_page` is from 1 to 100. The default is 50. An unknown `status` gives 422. A page past the
end is empty.

`invite`, `resend`, and `decline` return `{ "data": TesterRequest }`. An unknown id gives 404.

## Live updates (Action Cable)

| Item | Value |
|---|---|
| URL | `wss://<host>/cable?token=<admin JWT>` |
| Auth | The server decodes the token with devise-jwt and checks `users.jti`. A missing token, a bad token, a revoked token, or a user that is not an admin is rejected. |
| Channel | `TesterRequestsChannel`. Send `{"command":"subscribe","identifier":"{\"channel\":\"TesterRequestsChannel\"}"}`. |
| Stream | `tester_requests` |
| Adapter | `postgresql` (LISTEN and NOTIFY on the app database). No Redis. |

Messages, sent after the database commit:

```json
{ "event": "created", "request": TesterRequest }
{ "event": "updated", "request": TesterRequest }
{ "event": "deleted", "id": "uuid" }
```

A broadcast failure does not fail the request. The dashboard reloads the list after each
reconnect, so it gets each change that it did not receive.

The server keeps an open connection after the token expires. The dashboard reconnects with a
new token after each refresh.

## App Store Connect

`AppStoreConnect::Client` (`app/services/app_store_connect/client.rb`) signs an ES256 JWT with
`kid`, `iss`, and `aud = appstoreconnect-v1`. The token expires 19 minutes after issue. The
process reuses it for 14 minutes.

| Action | Requests |
|---|---|
| Invite | `POST /v1/betaTesters` with the email, `firstName` and `lastName` from `name`, and the group `ASC_BETA_GROUP_ID`. |
| Invite, Apple answers 409 | `GET /v1/betaTesters?filter[email]=...`, then `POST /v1/betaGroups/{id}/relationships/betaTesters`. |
| Resend | `POST /v1/betaTesterInvitations` with the app `ASC_APP_ID` and the beta tester. |

The name splits at the first space: `Juan Dela Cruz` gives `Juan` and `Dela Cruz`.

`TesterInviteJob` (`app/jobs/tester_invite_job.rb`):

| Result | Row |
|---|---|
| Success | `invited`, `ascBetaTesterId`, `invitedAt`, `lastError = null` |
| Apple 4xx | `failed`, `lastError` = the `detail` of each Apple error |
| Missing setting | `failed`, `lastError` names the missing variables |
| Network error or HTTP 5xx | Retries 3 times (4 attempts). After the last attempt: `failed`. |

The job runs on the `:async` adapter, in the web process. The global adapter is `:sidekiq`, but
the deploy has no Sidekiq worker. A restart stops a running job. The row then stays `inviting`,
and an admin can invite it again after 10 minutes.

## Environment variables

| Key | Used by | When it is missing |
|---|---|---|
| `TESTER_FORM_KEY` | Public endpoint | Every form request gives 401. |
| `ASC_ISSUER_ID` | Client | The invite fails with a clear `lastError`. |
| `ASC_KEY_ID` | Client | The invite fails with a clear `lastError`. |
| `ASC_PRIVATE_KEY` | Client. The `.p8` PEM text. A `\n` escape is read as a line break. | The invite fails with a clear `lastError`. |
| `ASC_APP_ID` | Client (resend) | The invite fails with a clear `lastError`. |
| `ASC_BETA_GROUP_ID` | Client (invite) | The invite fails with a clear `lastError`. |

The app boots without these variables. Set them as Render secrets. Never commit a value.

## Privacy and logs

- `config/initializers/filter_parameter_logging.rb` hides `email`, `name`, `age`, `location`,
  `consent_at`, and `token` in the logs. The request log shows `[FILTERED]` for each one.
- The server logs no request body of the public endpoint.
- A delete removes the row. It does not remove the tester from TestFlight.

## Tables

`tester_requests` (migration `045_create_tester_requests.rb`): uuid `id`, `name`, `age`
(check `age >= 16`), `location`, `email` (citext, unique), `status` (check on the 5 values),
`consent_at`, `source`, `asc_beta_tester_id`, `invited_at`, `invited_by_id`, `last_error`,
timestamps. Index on `(status, created_at)`.
