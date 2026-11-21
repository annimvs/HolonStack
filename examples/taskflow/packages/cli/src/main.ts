import { TaskStore } from "@taskflow/core";

export function runCommand(store: TaskStore, args: string[]): string {
  const [cmd, id, ...rest] = args;
  if (cmd === "add" && id) {
    const task = store.add(id, rest.join(" "));
    return `added ${task.id}: ${task.title}`;
  }
  if (cmd === "done" && id) {
    const task = store.complete(id);
    return `done ${task.id}`;
  }
  return store.list().map((t) => `${t.done ? "[x]" : "[ ]"} ${t.id} ${t.title}`).join("\n");
}
