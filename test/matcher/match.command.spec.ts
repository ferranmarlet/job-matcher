import { CommandTestFactory } from 'nest-commander-testing';
import { MatcherModule } from '../../src/matcher/matcher.module.js';
import { MatcherService } from '../../src/matcher/matcher.service.js';

describe('MatchCommand', () => {
  const run = vi.fn();

  async function runCommand(args: string[]): Promise<void> {
    const app = await CommandTestFactory.createTestingCommand({
      imports: [MatcherModule],
    })
      .overrideProvider(MatcherService)
      .useValue({ run })
      .compile();

    await CommandTestFactory.run(app, args);
  }

  beforeEach(() => {
    run.mockReset();
  });

  it('runs as the default command with no arguments', async () => {
    await runCommand([]);

    expect(run).toHaveBeenCalledWith({});
  });

  it('passes --key and --dry-run to the matcher', async () => {
    await runCommand(['match', '--key', 'exports/2026-11.csv', '--dry-run']);

    expect(run).toHaveBeenCalledWith({
      key: 'exports/2026-11.csv',
      dryRun: true,
    });
  });
});
