const MAX_LOG_LINES: number = 8;

export class ActivityLog {
  entries: string[] = [];

  add(actor: string, line: string): void {
    const now = new Date();
    const hh: string = now.getHours().toString().padStart(2, '0');
    const mm: string = now.getMinutes().toString().padStart(2, '0');
    const ss: string = now.getSeconds().toString().padStart(2, '0');
    const entry: string = `${hh}:${mm}:${ss} ${actor.padEnd(7)} ${line}`;

    const next: string[] = [entry];
    for (let i = 0; i < this.entries.length && i < MAX_LOG_LINES - 1; i++) {
      next.push(this.entries[i]);
    }
    this.entries = next;
    console.info(`[Login] ${entry}`);
  }

  clear(): void {
    this.entries = [];
  }
}
