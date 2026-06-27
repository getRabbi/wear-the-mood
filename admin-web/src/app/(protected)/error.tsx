"use client";

// Error boundary for the protected console area — keeps a failed data read from
// blanking the whole app (the four-states discipline). Never renders raw secrets.
export default function ProtectedError({ reset }: { error: Error; reset: () => void }) {
  return (
    <div className="rounded-lg border border-red-200 bg-red-50 p-6">
      <h2 className="text-sm font-semibold text-red-800">Something went wrong</h2>
      <p className="mt-1 text-sm text-red-700">
        We couldn&apos;t load this section. Please retry; if it persists, check the server logs.
      </p>
      <button
        type="button"
        onClick={reset}
        className="mt-3 rounded-md border border-red-300 bg-white px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-100"
      >
        Retry
      </button>
    </div>
  );
}
