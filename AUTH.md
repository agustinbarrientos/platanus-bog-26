# Auth for the frontend

Everything `apps/web` needs to sign a user up, log them in, and save their
answers to the API.

Two separate conversations. Supabase owns the password and issues tokens; the
API owns the health data and only ever verifies them.

```
Browser  ──email + password──▶  Supabase Auth
Browser  ──JWT in header─────▶  Moirai API
```

The password never reaches the API. There is no signup endpoint on it, by design.

## 1. Install and set the environment

```bash
cd apps/web
npm install @supabase/supabase-js
```

`apps/web/.env.local`:

```
NEXT_PUBLIC_SUPABASE_URL=https://wplkytspqzwotmatnbxo.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndwbGt5dHNwcXp3b3RtYXRuYnhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODczNzIxOTEsImV4cCI6MjEwMjk0ODE5MX0.UUiu8ysxWbnjJlKZp-w0GPJVTVFX0emvmtjZjChSP88
NEXT_PUBLIC_API_BASE_URL=https://platanus-bog-26.onrender.com
```

The anon key is built to ship inside the browser bundle; it is not a secret. The
database password and service key never come near `apps/web`. Set the same three
in Vercel before deploying.

## 2. Create the client once

`src/lib/supabase.ts`

```typescript
import { createClient } from "@supabase/supabase-js";

export const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);
```

## 3. Sign up

`src/lib/auth.ts`

```typescript
"use client";
import { supabase } from "@/lib/supabase";

export async function signUp(email: string, password: string) {
  const { data, error } = await supabase.auth.signUp({ email, password });

  if (error) {
    if (error.message.includes("already registered")) {
      throw new Error("Ya existe una cuenta con ese correo.");
    }
    throw new Error(error.message);
  }

  // Email confirmation is off, so the session exists right now.
  // Send them straight into the form, no inbox detour.
  return data.session;
}
```

## 4. Log in

```typescript
export async function signIn(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (error) {
    if (error.message.includes("Invalid login credentials")) {
      throw new Error("Correo o contraseña incorrectos.");
    }
    throw new Error(error.message);
  }

  return data.session;
}

export async function signOut() {
  await supabase.auth.signOut();
}
```

## 5. Call the API

Write this once and route every request through it, or the eighth screen someone
adds forgets the header and you debug a 401 that looks like a backend bug.

`src/lib/api.ts`

```typescript
import { supabase } from "@/lib/supabase";

const API = process.env.NEXT_PUBLIC_API_BASE_URL!;

export async function apiFetch(path: string, init: RequestInit = {}) {
  const { data } = await supabase.auth.getSession();
  if (!data.session) throw new Error("No hay sesión activa");

  const res = await fetch(`${API}${path}`, {
    ...init,
    headers: {
      ...init.headers,
      "Content-Type": "application/json",
      Authorization: `Bearer ${data.session.access_token}`,
    },
  });

  if (!res.ok) throw new Error(await res.text());
  return res.json();
}
```

Using it:

```typescript
// On entering the form. Creates the profile row on the first call.
const me = await apiFetch("/me");

// After each question. Send one field; the rest stay untouched.
const updated = await apiFetch("/me", {
  method: "PATCH",
  body: JSON.stringify({ weight_kg: 71.5 }),
});

// Drive the "dato 4 de 6" counter off the response, not a local count.
setProgress(updated.answered.length, updated.total);
```

## Endpoints

| Route | Auth | What it does |
| --- | --- | --- |
| `GET /me` | required | The user and their profile. Creates the row the first time it is called. |
| `PATCH /me` | required | Save any subset of the fields. Returns the same shape as GET. |
| `DELETE /me` | required | Erase this user's data. |
| `GET /health` | open | Liveness. Useful for waking the instance before a demo. |

Every response carries `answered`, `remaining`, `total` and `complete` alongside
the profile, so progress is computed server-side and cannot drift from what is
actually stored.

## Profile fields

| Field | Type | Accepted |
| --- | --- | --- |
| `full_name` | string | 1–120 characters, trimmed |
| `date_of_birth` | string | `"1991-11-02"`, must give an age of 18–120 |
| `height_cm` | number | 100–250 |
| `weight_kg` | number | 25–350 |
| `blood_type` | enum | `A+` `A-` `B+` `B-` `AB+` `AB-` `O+` `O-` |
| `sex_at_birth` | enum | `female` `male` `intersex` |
| `age` | number | read-only, derived from `date_of_birth`, never send it |

Anything outside those ranges returns `422` with a per-field message you can show
inline. An unknown field name is also a 422: the API rejects what it does not
recognize rather than silently dropping it.

## Four things that will bite

**The first request after idle takes 30–50 seconds.** Render's free tier sleeps
after about fifteen minutes. Do not block the whole screen on `GET /me` — render
the form shell immediately and fill it in when the response lands. Hit `/health`
once before any demo.

**Tokens expire after an hour.** `getSession()` refreshes automatically, which is
why every request should read the token fresh rather than caching it in a module
variable at startup.

**Signing up creates no profile row.** The API first hears about a user when a
request arrives carrying their token. If you sign up and look straight at the
`profiles` table it will be empty — that is correct. Call `GET /me` and the row
appears.

**Never store the token yourself.** Let the Supabase client manage it.
Hand-rolled `localStorage` handling is how a cross-site scripting bug turns into
a health-record leak.

## Poking at it by hand

Live docs: https://platanus-bog-26.onrender.com/docs

Get a token:

```bash
curl -s -X POST "https://wplkytspqzwotmatnbxo.supabase.co/auth/v1/token?grant_type=password" \
  -H "apikey: $NEXT_PUBLIC_SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"juan@moirai.test","password":"una-clave-larga-123"}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])"
```

Click **Authorize** in the docs and paste it with no `Bearer` prefix.
