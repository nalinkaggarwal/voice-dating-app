import { IsIn } from 'class-validator';
import { DecisionType } from '@prisma/client';

export class DecideDto {
  @IsIn([DecisionType.PASS, DecisionType.INTERESTED])
  decision!: DecisionType;
}
