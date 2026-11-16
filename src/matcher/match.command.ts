import { Command, CommandRunner, Option } from 'nest-commander';
import { MatcherService, type MatchOptions } from './matcher.service.js';

// The default command: `node dist/main.js` runs it with no arguments,
// which is how the scheduled and manual ECS runs start it.
@Command({
  name: 'match',
  description: 'Analyse the input file against the jobscan data',
  options: { isDefault: true },
})
export class MatchCommand extends CommandRunner {
  constructor(private readonly matcher: MatcherService) {
    super();
  }

  async run(_args: string[], options: MatchOptions): Promise<void> {
    await this.matcher.run(options);
  }

  @Option({
    flags: '--key <key>',
    description: 'S3 key to process instead of the newest file',
  })
  parseKey(value: string): string {
    return value;
  }

  @Option({
    flags: '--dry-run',
    description: 'Analyse without saving results',
  })
  parseDryRun(): boolean {
    return true;
  }
}
