import "server-only";

import { randomUUID } from "node:crypto";

import { getAdminClient } from "@/lib/supabase/admin";

// Seed images go to the PUBLIC post-images bucket so the app can read them
// directly (same bucket the community feed already uses). The console uploads as
// service_role (bypasses storage RLS). Returns the public URL.
const BUCKET = "post-images";
const MAX_BYTES = 8 * 1024 * 1024;

export type UploadResult = { ok: true; url: string } | { ok: false; error: string };

export async function uploadSeedImage(file: File, prefix: "avatars" | "looks"): Promise<UploadResult> {
  if (!file || file.size === 0) return { ok: false, error: "No file selected." };
  if (!file.type.startsWith("image/")) return { ok: false, error: "Please upload an image." };
  if (file.size > MAX_BYTES) return { ok: false, error: "Image is too large (max 8 MB)." };

  const ext = (file.name.split(".").pop() || "jpg").toLowerCase().replace(/[^a-z0-9]/g, "") || "jpg";
  const path = `seed/${prefix}/${randomUUID()}.${ext}`;
  const bytes = new Uint8Array(await file.arrayBuffer());

  const client = getAdminClient();
  const { error } = await client.storage.from(BUCKET).upload(path, bytes, {
    contentType: file.type || "image/jpeg",
    upsert: false,
  });
  if (error) return { ok: false, error: "Upload failed." };

  return { ok: true, url: client.storage.from(BUCKET).getPublicUrl(path).data.publicUrl };
}

/** Optional file field from a form → uploaded URL, or null if no file given. */
export async function maybeUpload(
  file: FormDataEntryValue | null,
  prefix: "avatars" | "looks"
): Promise<{ url: string | null; error?: string }> {
  if (!(file instanceof File) || file.size === 0) return { url: null };
  const res = await uploadSeedImage(file, prefix);
  return res.ok ? { url: res.url } : { url: null, error: res.error };
}
