import { Body, Controller, Get, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { CreatePaymentLinkDto } from '../medical/dto/medical.dto';
import { OperatorsService } from '../operators/operators.service';
import { PaymentsService } from './payments.service';

@ApiTags('payments')
@ApiBearerAuth()
@Controller('operators/me/payment-links')
export class PaymentsController {
  constructor(
    private readonly payments: PaymentsService,
    private readonly operators: OperatorsService,
  ) {}

  @Get()
  @ApiOperation({ summary: 'List payment links for my operator' })
  async list(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    const op = await this.operators.getMyOperator(token, user.id);
    return this.payments.listForOperator(token, op.id);
  }

  @Post()
  @ApiOperation({ summary: 'Create a deposit/payment link record' })
  async create(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: CreatePaymentLinkDto,
  ) {
    const op = await this.operators.getMyOperator(token, user.id);
    return this.payments.create(token, user.id, op.id, dto);
  }
}
