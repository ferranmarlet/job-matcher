import { CommandFactory } from 'nest-commander';
import { AppModule } from './app.module.js';

await CommandFactory.run(AppModule, {
  logger: ['log', 'warn', 'error'],
  serviceErrorHandler: (error) => {
    console.error(error);
    process.exitCode = 1;
  },
});
