import { Module } from '@nestjs/common';
import { ProfileController } from './profile.controller.js';
import { ProfileService } from './profile.service.js';
import { StorageModule } from '../../shared/storage/storage.module.js';
import { IdentityModule } from '../identity/identity.module.js';

@Module({
  imports: [StorageModule, IdentityModule],
  controllers: [ProfileController],
  providers: [ProfileService],
  exports: [ProfileService],
})
export class ProfileModule {}
