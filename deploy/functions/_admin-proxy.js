// Transparent reverse proxy for the ops console, so the browser stays on
// wearthemood.com.
//
// WHY A PAGES FUNCTION AND NOT A CLOUDFLARE ORIGIN RULE.
// An Origin Rule (or a zone-level Worker route) is the tidier mechanism, but
// both are zone-scoped resources and the deployment credential available here is
// Pages-scoped: `GET /zones` returns zero zones, so the zone's plan cannot even
// be read, let alone a rule written. A Pages Function ships with the same
// credential that already deploys this site and needs no new access.
//
// Scoped deliberately narrowly. Only the two console routes import this, so
// every other path — the landing page, /legal/*, /invite/, /.well-known/* and
// the business-critical /r/* referral redirect in `_redirects` — is still served
// by Pages exactly as before. A root `_middleware.js` or an `_worker.js` would
// have put the whole site behind this code for no benefit.

const ADMIN_ORIGIN = "https://wtm-admin-aab1ebe5235d.herokuapp.com";

export async function proxyToAdmin(context) {
  const { request } = context;
  const incoming = new URL(request.url);

  // Full path + query preserved verbatim. The Next app is built with
  // basePath=/mood-ops-console-7x9 and 404s if the prefix is stripped, so the
  // path is passed through untouched rather than rewritten.
  const target = new URL(incoming.pathname + incoming.search, ADMIN_ORIGIN);

  // Copies method, headers and body. Host/SNI follow `target`, which is what
  // Heroku routes on — the app has no custom domain attached, so it must see its
  // own hostname or its router returns "no such app".
  const upstream = new Request(target, request);
  upstream.headers.delete("host");
  // What the browser actually asked for, for anything downstream that cares.
  upstream.headers.set("x-forwarded-host", incoming.host);
  upstream.headers.set("x-forwarded-proto", incoming.protocol.replace(":", ""));

  // manual: redirects must reach us so the Location can be rewritten below.
  const response = await fetch(upstream, { redirect: "manual" });

  // Next builds redirects from the URL the ORIGIN saw (`request.nextUrl.clone()`
  // in the auth middleware), so an unauthenticated hit on a protected page comes
  // back as an ABSOLUTE Location on the Heroku host. Passed through unchanged it
  // would bounce the browser straight off wearthemood.com — precisely what this
  // proxy exists to prevent. Rewritten against the incoming origin rather than a
  // hardcoded one, so preview deployments work too.
  const location = response.headers.get("location");
  if (location && location.startsWith(ADMIN_ORIGIN)) {
    const rewritten = new Response(response.body, response);
    rewritten.headers.set(
      "location",
      incoming.origin + location.slice(ADMIN_ORIGIN.length)
    );
    return rewritten;
  }

  // Everything else passes through untouched — status, body and headers,
  // including the origin's `X-Robots-Tag: noindex, nofollow`.
  //
  // Set-Cookie is deliberately NOT rewritten: the console's Supabase SSR client
  // sets host-only cookies (no Domain attribute), so they bind to whatever host
  // the browser sees — wearthemood.com — which is both correct and tighter than
  // a domain-scoped cookie would be.
  return response;
}
