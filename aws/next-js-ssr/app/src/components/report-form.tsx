"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { useState } from "react";

// JSTでの今日の日付（YYYY-MM-DD）。date inputの初期値用
function todayJst(): string {
  return new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Tokyo" }).format(
    new Date(),
  );
}

type FormInput = {
  title: string;
  body: string;
  reportedAt: string;
  file: File | null;
};

async function submitReport(input: FormInput) {
  let imageKey: string | null = null;

  // 画像があれば署名付きURLを取得してS3へ直接アップロードする
  if (input.file) {
    const presignRes = await fetch("/api/upload-url", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ contentType: input.file.type }),
    });
    if (!presignRes.ok) {
      const err = await presignRes.json().catch(() => null);
      throw new Error(err?.message ?? "アップロードURLの取得に失敗しました");
    }
    const { uploadUrl, imageKey: key } = await presignRes.json();

    const putRes = await fetch(uploadUrl, {
      method: "PUT",
      headers: { "Content-Type": input.file.type },
      body: input.file,
    });
    if (!putRes.ok) {
      throw new Error("画像のアップロードに失敗しました");
    }
    imageKey = key;
  }

  const res = await fetch("/api/reports", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      title: input.title,
      body: input.body,
      reportedAt: input.reportedAt,
      imageKey,
    }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => null);
    throw new Error(err?.message ?? "投稿に失敗しました");
  }
  return res.json();
}

export function ReportForm() {
  const router = useRouter();
  const queryClient = useQueryClient();

  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [reportedAt, setReportedAt] = useState(todayJst());
  const [file, setFile] = useState<File | null>(null);

  const mutation = useMutation({
    mutationFn: submitReport,
    onSuccess: async () => {
      // 一覧のキャッシュを無効化してから戻る（CSRなので即時反映される）
      await queryClient.invalidateQueries({ queryKey: ["reports"] });
      router.push("/");
    },
  });

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        mutation.mutate({ title, body, reportedAt, file });
      }}
      className="space-y-6"
    >
      <div>
        <label htmlFor="reportedAt" className="mb-1 block text-sm font-medium">
          日付
        </label>
        <input
          id="reportedAt"
          type="date"
          required
          value={reportedAt}
          onChange={(e) => setReportedAt(e.target.value)}
          className="rounded border border-zinc-300 px-3 py-2 dark:border-zinc-700 dark:bg-zinc-900"
        />
      </div>

      <div>
        <label htmlFor="title" className="mb-1 block text-sm font-medium">
          タイトル
        </label>
        <input
          id="title"
          type="text"
          required
          maxLength={200}
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="今日やったこと"
          className="w-full rounded border border-zinc-300 px-3 py-2 dark:border-zinc-700 dark:bg-zinc-900"
        />
      </div>

      <div>
        <label htmlFor="body" className="mb-1 block text-sm font-medium">
          本文
        </label>
        <textarea
          id="body"
          required
          rows={10}
          value={body}
          onChange={(e) => setBody(e.target.value)}
          placeholder="作業内容・気づき・明日やることなど"
          className="w-full rounded border border-zinc-300 px-3 py-2 dark:border-zinc-700 dark:bg-zinc-900"
        />
      </div>

      <div>
        <label htmlFor="image" className="mb-1 block text-sm font-medium">
          画像（任意）
        </label>
        <input
          id="image"
          type="file"
          accept="image/jpeg,image/png,image/webp,image/gif"
          onChange={(e) => setFile(e.target.files?.[0] ?? null)}
          className="block text-sm"
        />
      </div>

      {mutation.isError && (
        <p className="text-sm text-red-600">{mutation.error.message}</p>
      )}

      <button
        type="submit"
        disabled={mutation.isPending}
        className="rounded bg-zinc-900 px-6 py-2 text-white transition hover:bg-zinc-700 disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900"
      >
        {mutation.isPending ? "投稿中..." : "投稿する"}
      </button>
    </form>
  );
}
