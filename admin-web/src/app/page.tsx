import { redirect } from "next/navigation";

// Console root → dashboard. The protected layout's requireAdmin() handles the
// (un)authorized cases (→ /login).
export default function Home() {
  redirect("/dashboard");
}
