"use client";

import { useRouter } from "next/navigation";
import { useActionState, useTransition } from "react";

import { setAdminStatus, upsertAdmin, type ActionState } from "@/lib/actions/admin";
import { ROLES } from "@/lib/auth/permissions";
import { StatusBadge } from "@/components/StatusBadge";

type AdminRow = {
  user_id: string;
  email: string;
  role: string;
  status: string;
};

export function AdminUserManager({
  admins,
  currentUserId,
}: {
  admins: AdminRow[];
  currentUserId: string;
}) {
  const router = useRouter();
  const [state, action, pending] = useActionState<ActionState | null, FormData>(upsertAdmin, null);
  const [busy, start] = useTransition();

  function changeStatus(userId: string, status: string) {
    start(async () => {
      const fd = new FormData();
      fd.set("userId", userId);
      fd.set("status", status);
      await setAdminStatus(null, fd);
      router.refresh();
    });
  }

  return (
    <div className="space-y-4">
      <form action={action} className="flex flex-wrap items-end gap-2">
        <input
          name="email"
          type="email"
          required
          placeholder="Existing account email"
          className="min-w-56 grow rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
        <select name="role" defaultValue="moderator" className="rounded-md border border-neutral-300 px-2 py-2 text-sm">
          {ROLES.map((r) => (
            <option key={r} value={r}>
              {r}
            </option>
          ))}
        </select>
        <button
          type="submit"
          disabled={pending}
          className="rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-50"
        >
          {pending ? "Saving…" : "Add / update admin"}
        </button>
        {state?.ok ? <span className="text-sm text-green-700">Saved.</span> : null}
        {state && !state.ok ? <span className="text-sm text-red-700">{state.error}</span> : null}
      </form>

      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-neutral-200 text-left text-xs uppercase text-neutral-500">
            <th className="px-2 py-2">Email</th>
            <th className="px-2 py-2">Role</th>
            <th className="px-2 py-2">Status</th>
            <th className="px-2 py-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          {admins.map((a) => (
            <tr key={a.user_id} className="border-t border-neutral-100">
              <td className="px-2 py-2">{a.email}</td>
              <td className="px-2 py-2 font-medium">{a.role}</td>
              <td className="px-2 py-2">
                <StatusBadge status={a.status} />
              </td>
              <td className="px-2 py-2">
                {a.user_id === currentUserId ? (
                  <span className="text-xs text-neutral-400">you</span>
                ) : (
                  <div className="flex gap-1.5">
                    {a.status !== "active" ? (
                      <button
                        className="rounded border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100 disabled:opacity-50"
                        disabled={busy}
                        onClick={() => changeStatus(a.user_id, "active")}
                      >
                        Enable
                      </button>
                    ) : (
                      <button
                        className="rounded border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100 disabled:opacity-50"
                        disabled={busy}
                        onClick={() => changeStatus(a.user_id, "disabled")}
                      >
                        Disable
                      </button>
                    )}
                  </div>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
