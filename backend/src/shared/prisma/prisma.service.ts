import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

// Single shared Prisma client for the whole app -- injected wherever a
// module needs DB access, never instantiated ad hoc. Connects on module
// init and disconnects cleanly on shutdown so tests/CI don't leak
// connections.
@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
