"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

import { createSupabaseBrowser } from "@/lib/supabase/browser";

export function LoginForm({ denied }: { denied: boolean }) {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(
    denied ? "Access denied — this account isn't authorized for the console." : null
  );

  // If we were bounced here because the user is authenticated but NOT an admin,
  // sign the stray session out so a non-admin never lingers logged in (§12.1).
  useEffect(() => {
    if (denied) {
      createSupabaseBrowser()
        .auth.signOut()
        .catch(() => {});
    }
  }, [denied]);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setMessage(null);
    try {
      const { error } = await createSupabaseBrowser().auth.signInWithPassword({
        email,
        password,
      });
      if (error) {
        // Generic message only — never reveal whether the email exists (§12.1).
        setMessage("Invalid login. Check your credentials and try again.");
        return;
      }
      router.replace("/dashboard");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-neutral-50 px-4">
      <form
        onSubmit={onSubmit}
        className="w-full max-w-sm space-y-4 rounded-xl border border-neutral-200 bg-white p-6 shadow-sm"
      >
        <div>
          <div className="text-base font-semibold">Wear The Mood</div>
          <div className="text-sm text-neutral-500">Ops Console — sign in</div>
        </div>

        {message ? (
          <div className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{message}</div>
        ) : null}

        <label className="block text-sm">
          <span className="mb-1 block text-neutral-600">Email</span>
          <input
            type="email"
            required
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-neutral-500"
          />
        </label>

        <label className="block text-sm">
          <span className="mb-1 block text-neutral-600">Password</span>
          <input
            type="password"
            required
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-neutral-500"
          />
        </label>

        <button
          type="submit"
          disabled={busy}
          className="w-full rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-50"
        >
          {busy ? "Signing in…" : "Sign in"}
        </button>
      </form>
    </div>
  );
}
