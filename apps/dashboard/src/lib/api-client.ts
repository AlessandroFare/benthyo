import { getAccessToken } from "@/lib/auth";
import type { ApiError } from "@/lib/types";

const API_BASE = import.meta.env.VITE_API_URL ?? "/api/v1";

export class ApiClientError extends Error {
  statusCode: number;
  code?: string;

  constructor(payload: ApiError) {
    super(payload.message);
    this.name = "ApiClientError";
    this.statusCode = payload.statusCode;
    this.code = payload.code;
  }
}

type RequestOptions = Omit<RequestInit, "body"> & {
  body?: unknown;
  params?: Record<string, string | number | boolean | undefined | null>;
};

function buildUrl(
  path: string,
  params?: RequestOptions["params"],
): string {
  const url = new URL(
    path.startsWith("http") ? path : `${API_BASE}${path}`,
    path.startsWith("http") ? undefined : window.location.origin,
  );

  if (params) {
    for (const [key, value] of Object.entries(params)) {
      if (value !== undefined && value !== null && value !== "") {
        url.searchParams.set(key, String(value));
      }
    }
  }

  return url.toString();
}

async function parseError(response: Response): Promise<ApiClientError> {
  let message = response.statusText || "Request failed";
  let code: string | undefined;

  try {
    const body = (await response.json()) as Partial<ApiError>;
    if (body.message) message = body.message;
    code = body.code;
  } catch {
    // ignore JSON parse errors
  }

  return new ApiClientError({
    message,
    statusCode: response.status,
    code,
  });
}

export async function apiClient<T>(
  path: string,
  options: RequestOptions = {},
): Promise<T> {
  const { body, params, headers, ...rest } = options;
  const token = await getAccessToken();

  const response = await fetch(buildUrl(path, params), {
    ...rest,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });

  if (!response.ok) {
    throw await parseError(response);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return (await response.json()) as T;
}

export const api = {
  get: <T>(path: string, params?: RequestOptions["params"]) =>
    apiClient<T>(path, { method: "GET", params }),

  post: <T>(path: string, body?: unknown) =>
    apiClient<T>(path, { method: "POST", body }),

  put: <T>(path: string, body?: unknown) =>
    apiClient<T>(path, { method: "PUT", body }),

  patch: <T>(path: string, body?: unknown) =>
    apiClient<T>(path, { method: "PATCH", body }),

  delete: <T>(path: string) => apiClient<T>(path, { method: "DELETE" }),
};
