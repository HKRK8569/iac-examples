"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { ReportContent } from "@/components/report-content";
import type { ReportDto } from "@/lib/api-types";
import { IMAGE_CONTENT_TYPES, MAX_IMAGE_SIZE, imageUrl } from "@/lib/image";

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
  imageKey: string | null;
};

type SelectedImage = {
  file: File;
  previewUrl: string;
  imageKey: string | null;
};

async function uploadImage(file: File, signal: AbortSignal): Promise<string> {
  const response = await fetch("/api/upload-url", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ contentType: file.type }),
    signal,
  });
  if (!response.ok) {
    const error = await response.json().catch(() => null);
    throw new Error(error?.message ?? "アップロードURLの取得に失敗しました");
  }
  const { uploadUrl, imageKey } = await response.json();
  const uploaded = await fetch(uploadUrl, {
    method: "PUT",
    headers: { "Content-Type": file.type },
    body: file,
    signal,
  });
  if (!uploaded.ok) {
    const error = await uploaded.json().catch(() => null);
    throw new Error(error?.message ?? "画像のアップロードに失敗しました");
  }
  return imageKey;
}

async function submitReport(input: FormInput): Promise<ReportDto> {
  const res = await fetch("/api/reports", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      title: input.title,
      body: input.body,
      reportedAt: input.reportedAt,
      imageKey: input.imageKey,
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
  const [mode, setMode] = useState<"edit" | "preview">("edit");
  const [image, setImage] = useState<SelectedImage | null>(null);
  const [isUploading, setIsUploading] = useState(false);
  const [imageError, setImageError] = useState<string | null>(null);
  const imageInput = useRef<HTMLInputElement>(null);
  const uploadController = useRef<AbortController | null>(null);
  const previewUrl = image?.previewUrl;

  useEffect(() => () => {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
  }, [previewUrl]);

  useEffect(() => () => uploadController.current?.abort(), []);

  async function selectImage(file: File) {
    if (!Object.hasOwn(IMAGE_CONTENT_TYPES, file.type)) {
      setImageError("JPEG・PNG・WebP・GIFの画像を選んでください");
      return;
    }
    if (file.size === 0 || file.size > MAX_IMAGE_SIZE) {
      setImageError("画像は空でない10MB以下のファイルを選んでください");
      return;
    }

    uploadController.current?.abort();
    const controller = new AbortController();
    uploadController.current = controller;
    setImage({ file, previewUrl: URL.createObjectURL(file), imageKey: null });
    setImageError(null);
    setIsUploading(true);

    try {
      const imageKey = await uploadImage(file, controller.signal);
      if (!controller.signal.aborted) {
        setImage((current) => current ? { ...current, imageKey } : null);
      }
    } catch (error) {
      if (!controller.signal.aborted) {
        setImageError(error instanceof Error ? error.message : "画像のアップロードに失敗しました");
      }
    } finally {
      if (!controller.signal.aborted) setIsUploading(false);
    }
  }

  function removeImage() {
    uploadController.current?.abort();
    setImage(null);
    setImageError(null);
    setIsUploading(false);
  }

  const mutation = useMutation({
    mutationFn: submitReport,
    onSuccess: async (report) => {
      // 一覧のキャッシュも更新し、投稿した記事を表示する。
      await queryClient.invalidateQueries({ queryKey: ["reports"] });
      router.push(`/reports/${report.id}`);
    },
  });

  const imageSrc = image ? imageUrl(image.imageKey) ?? image.previewUrl : null;
  const canSubmit = title.trim() && body.trim() && reportedAt && !isUploading && (!image || image.imageKey);

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        if (!canSubmit || mutation.isPending) return;
        mutation.mutate({ title, body, reportedAt, imageKey: image?.imageKey ?? null });
      }}
      className="space-y-6"
    >
      <div role="group" aria-label="表示モード" className="flex gap-1 border-b border-zinc-200 pb-3 dark:border-zinc-800">
        {(["edit", "preview"] as const).map((value) => (
          <button
            key={value}
            type="button"
            aria-pressed={mode === value}
            onClick={() => setMode(value)}
            className={`rounded px-4 py-2 text-sm font-medium transition ${mode === value ? "bg-zinc-900 text-white dark:bg-zinc-100 dark:text-zinc-900" : "text-zinc-500 hover:bg-zinc-100 dark:hover:bg-zinc-800"}`}
          >
            {value === "edit" ? "編集" : "プレビュー"}
          </button>
        ))}
      </div>

      {mode === "edit" ? (
        <fieldset disabled={mutation.isPending} className="space-y-6">
          <div>
            <label htmlFor="reportedAt" className="mb-1 block text-sm font-medium">日付</label>
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
            <label htmlFor="title" className="mb-1 block text-sm font-medium">タイトル</label>
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
            <label htmlFor="image" className="mb-2 block text-sm font-medium">画像（任意）</label>
            {imageSrc && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={imageSrc} alt="選択した画像" className="mb-3 w-full rounded-lg object-cover" />
            )}
            <input
              ref={imageInput}
              id="image"
              type="file"
              accept={Object.keys(IMAGE_CONTENT_TYPES).join(",")}
              onChange={(e) => {
                const file = e.currentTarget.files?.[0];
                e.currentTarget.value = "";
                if (file) void selectImage(file);
              }}
              aria-describedby="image-help"
              className="hidden"
            />
            <button
              type="button"
              onClick={() => imageInput.current?.click()}
              aria-describedby="image-help"
              className="rounded border border-zinc-300 px-3 py-2 text-sm text-zinc-700 hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-200 dark:hover:bg-zinc-800"
            >
              {image ? "画像を変更" : "画像を選択"}
            </button>
            <p id="image-help" className="mt-2 text-xs text-zinc-500">JPEG・PNG・WebP・GIF / 10MBまで</p>
            {image && (
              <div className="mt-2 flex flex-wrap items-center gap-3 text-sm">
                <span className="min-w-0 break-all text-zinc-500">{image.file.name}</span>
                <button type="button" onClick={removeImage} className="text-red-600 hover:underline">画像を外す</button>
                {!isUploading && !image.imageKey && (
                  <button type="button" onClick={() => void selectImage(image.file)} className="hover:underline">再アップロード</button>
                )}
              </div>
            )}
          </div>

          <div>
            <label htmlFor="body" className="mb-1 block text-sm font-medium">本文</label>
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
        </fieldset>
      ) : (
        <ReportContent
          title={title.trim() || "タイトル未入力"}
          body={body || "本文未入力"}
          reportedAt={new Date(`${reportedAt || todayJst()}T00:00:00+09:00`)}
          imageSrc={imageSrc}
        />
      )}

      {isUploading && <p role="status" className="text-sm text-zinc-500">画像をアップロード中...</p>}
      {imageError && <p role="alert" className="text-sm text-red-600">{imageError}</p>}

      {mutation.isError && (
        <p role="alert" className="text-sm text-red-600">{mutation.error.message}</p>
      )}

      <button
        type="submit"
        disabled={!canSubmit || mutation.isPending}
        className="rounded bg-zinc-900 px-6 py-2 text-white transition hover:bg-zinc-700 disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900"
      >
        {mutation.isPending ? "投稿中..." : "投稿する"}
      </button>
    </form>
  );
}
