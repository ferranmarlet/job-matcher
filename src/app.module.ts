import { Module } from '@nestjs/common';
import { MatcherModule } from './matcher/matcher.module.js';

@Module({
  imports: [MatcherModule],
})
export class AppModule {}
