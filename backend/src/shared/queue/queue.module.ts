import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { ConfigModule, ConfigService } from '@nestjs/config';

// Root Redis connection for every BullMQ queue in the app -- imported
// ONCE in AppModule. Individual feature modules only ever call
// BullModule.registerQueue({ name: ... }) for the specific queues they
// own; they never configure the connection themselves.
@Module({
  imports: [
    BullModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const url = new URL(config.get<string>('REDIS_URL', 'redis://localhost:6379'));
        return {
          connection: {
            host: url.hostname,
            port: Number(url.port || 6379),
          },
        };
      },
    }),
  ],
  exports: [BullModule],
})
export class QueueModule {}
