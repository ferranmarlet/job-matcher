import { Module } from '@nestjs/common';
import { MatchCommand } from './match.command.js';
import { MatcherService } from './matcher.service.js';

@Module({
  providers: [MatchCommand, MatcherService],
})
export class MatcherModule {}
