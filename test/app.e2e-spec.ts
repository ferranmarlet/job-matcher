import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const runCli = (args: string[]) =>
  promisify(execFile)('node', ['dist/main.js', ...args]);

describe('job-matcher CLI (e2e)', () => {
  it('runs the match command by default and exits with code 0', async () => {
    const { stdout } = await runCli([]);

    expect(stdout).toContain('Match finished');
  });

  it('prints help', async () => {
    const { stdout } = await runCli(['--help']);

    expect(stdout).toContain('match');
  });
});
