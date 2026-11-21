import { TaskStore } from "@taskflow/core";

export interface CreatePayload {
  id: string;
  title: string;
}

export function parsePayload(raw: string): CreatePayload {
  const parsed = JSON.parse(raw) as Partial<CreatePayload>;
  if (typeof parsed.id !== "string" || typeof parsed.title !== "string") {
    throw new Error("payload requires string id and title");
  }
  return { id: parsed.id, title: parsed.title };
}

export function handleCreate(store: TaskStore, rawBody: string): string {
  const payload = parsePayload(rawBody);
  const task = store.add(payload.id, payload.title);
  return JSON.stringify(task);
}
