import { LoginForm } from "@/components/LoginForm";

// Public route (no admin gate). `denied=1` arrives when an authenticated but
// non-admin user was bounced here by requireAdmin().
export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ denied?: string }>;
}) {
  const { denied } = await searchParams;
  return <LoginForm denied={denied === "1"} />;
}
