import { Controller } from '@nestjs/common';
import { ConnectionsService } from './connections.service.js';

// WP1 stub -- no routes yet. ConnectionsService's method signatures are
// already final (see its docstring); routes get wired to them in WP3.
@Controller('connections')
export class ConnectionsController {
  constructor(private readonly connectionsService: ConnectionsService) {}
}
