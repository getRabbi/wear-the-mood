// The bare /mood-ops-console-7x9 path. A `[[path]]` catch-all covers the
// children but not the parent itself, and that bare path is what people type and
// bookmark — the same reason the temporary `_redirects` fix needed two rules.
import { proxyToAdmin } from "./_admin-proxy.js";

export const onRequest = proxyToAdmin;
