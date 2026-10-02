"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";

export function Providers({ children }: { children: React.ReactNode }) {
  // useStateで包むことでリクエストごとに新しいQueryClientを作る（SSR時の共有を防ぐ）
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            // CSRページは鮮度優先（一覧に投稿を即時反映させたい）ためキャッシュは短めに
            staleTime: 10 * 1000,
            retry: 1,
          },
        },
      }),
  );

  return (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
}
