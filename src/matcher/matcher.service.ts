import { Injectable, Logger } from '@nestjs/common';

export interface MatchOptions {
  /** S3 key to process instead of the newest file under the input prefix */
  key?: string;
  /** Analyse without saving results */
  dryRun?: boolean;
}

@Injectable()
export class MatcherService {
  private readonly logger = new Logger(MatcherService.name);

  async run(options: MatchOptions): Promise<void> {
    this.logger.log(
      `Starting match (key: ${options.key ?? 'newest file'}, dry run: ${options.dryRun ?? false})`,
    );

    // TODO: download the input file from S3, read the jobscan data from RDS,
    // and send it to Claude for analysis.

    this.logger.log('Match finished');
  }
}
