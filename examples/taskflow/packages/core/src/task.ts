export interface Task {
  readonly id: string;
  readonly title: string;
  done: boolean;
}

export class TaskStore {
  private readonly items = new Map<string, Task>();

  add(id: string, title: string): Task {
    const trimmed = title.trim();
    if (!trimmed) throw new Error("title must not be empty");
    const task: Task = { id, title: trimmed, done: false };
    this.items.set(id, task);
    return task;
  }

  complete(id: string): Task {
    const task = this.items.get(id);
    if (!task) throw new Error(`unknown task: ${id}`);
    task.done = true;
    return task;
  }

  list(): Task[] {
    return Array.from(this.items.values());
  }
}
