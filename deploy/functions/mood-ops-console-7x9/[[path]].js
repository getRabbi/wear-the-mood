// Everything under /mood-ops-console-7x9/ — login, the app shell, /_next/*
// static assets and API routes alike.
import { proxyToAdmin } from "../_admin-proxy.js";

export const onRequest = proxyToAdmin;
