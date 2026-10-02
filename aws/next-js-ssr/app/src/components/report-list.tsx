"use client";

import { keepPreviousData, useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";
import type { ReportListResponse } from "@/lib/api-types";
import { formatReportDate } from "@/lib/date";
import { imageUrl } from "@/lib/image";

async function fetchReports(page: number): Promise<ReportListResponse> {
  const res = await fetch(`/api/reports?page=${page}`);
  if (!res.ok) {
    throw new Error("一覧の取得に失敗しました");
  }
  return res.json();
}

export function ReportList() {
  const [page, setPage] = useState(1);
  const { data, isPending, isError } = useQuery({
    queryKey: ["reports", page],
    queryFn: () => fetchReports(page),
    // ページ切り替え時に前ページの表示を保ったままロードする
    placeholderData: keepPreviousData,
  });

  if (isPending) {
    return <p className="py-16 text-center text-zinc-500">読み込み中...</p>;
  }
  if (isError) {
    return (
      <p className="py-16 text-center text-red-600">
        一覧の取得に失敗しました。時間をおいて再読み込みしてください。
      </p>
    );
  }

  const { reports, meta } = data;

  if (meta.totalCount === 0) {
    return (
      <p className="py-16 text-center text-zinc-500">
        まだ日報がありません。最初の日報を投稿してみましょう。
      </p>
    );
  }

  return (
    <div className="space-y-6">
      <ul className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {reports.map((report) => {
          const src = imageUrl(report.imageKey);
          return (
            <li key={report.id}>
              <Link
                href={`/reports/${report.id}`}
                className="block overflow-hidden rounded-lg border border-zinc-200 bg-white transition hover:shadow-md dark:border-zinc-800 dark:bg-zinc-900"
              >
                {src ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={src}
                    alt=""
                    className="h-40 w-full object-cover"
                  />
                ) : (
                  <div className="flex h-40 w-full items-center justify-center bg-zinc-100 text-sm text-zinc-400 dark:bg-zinc-800">
                    No Image
                  </div>
                )}
                <div className="p-4">
                  <h2 className="truncate font-semibold">{report.title}</h2>
                  <time className="mt-1 block text-sm text-zinc-500">
                    {formatReportDate(new Date(report.reportedAt))}
                  </time>
                </div>
              </Link>
            </li>
          );
        })}
      </ul>

      <nav className="flex items-center justify-center gap-4">
        <button
          type="button"
          onClick={() => setPage((p) => p - 1)}
          disabled={!meta.hasPrev}
          className="rounded border border-zinc-300 px-4 py-2 text-sm disabled:opacity-40 dark:border-zinc-700"
        >
          前へ
        </button>
        <span className="text-sm text-zinc-500">
          {meta.page} / {meta.totalPages} ページ（全{meta.totalCount}件）
        </span>
        <button
          type="button"
          onClick={() => setPage((p) => p + 1)}
          disabled={!meta.hasNext}
          className="rounded border border-zinc-300 px-4 py-2 text-sm disabled:opacity-40 dark:border-zinc-700"
        >
          次へ
        </button>
      </nav>
    </div>
  );
}
