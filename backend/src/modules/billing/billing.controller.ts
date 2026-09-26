import { Controller } from '@nestjs/common';
import { BillingService } from './billing.service.js';

// WP1 stub -- no routes yet. Exists so the module boundary and DI wiring
// are already in place when real endpoints land.
@Controller('billing')
export class BillingController {
  constructor(private readonly billingService: BillingService) {}
}
