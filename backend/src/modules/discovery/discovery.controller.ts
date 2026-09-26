import { Controller } from '@nestjs/common';
import { DiscoveryService } from './discovery.service.js';

// WP1 stub -- no routes yet. Exists so the module boundary and DI wiring
// are already in place when real endpoints land.
@Controller('discovery')
export class DiscoveryController {
  constructor(private readonly discoveryService: DiscoveryService) {}
}
