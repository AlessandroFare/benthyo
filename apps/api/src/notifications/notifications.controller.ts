import { Body, Controller, Headers, Post, UnauthorizedException } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Public } from '../common/decorators/public.decorator';
import { SendEmailDto, SendTemplateEmailDto } from './dto/notification.dto';
import { NotificationsService } from './notifications.service';

@ApiTags('notifications')
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  private assertInternalKey(key: string | undefined): void {
    const expected = process.env['INTERNAL_API_KEY'] ?? '';
    if (!expected || key !== expected) {
      throw new UnauthorizedException('Invalid internal API key');
    }
  }

  @Public()
  @Post('email')
  @ApiOperation({ summary: 'Send a raw email (internal)' })
  sendEmail(
    @Headers('x-internal-key') internalKey: string,
    @Body() dto: SendEmailDto,
  ) {
    this.assertInternalKey(internalKey);
    return this.notificationsService.sendRaw(dto);
  }

  @Public()
  @Post('email/template')
  @ApiOperation({ summary: 'Send a templated email (internal)' })
  sendTemplateEmail(
    @Headers('x-internal-key') internalKey: string,
    @Body() dto: SendTemplateEmailDto,
  ) {
    this.assertInternalKey(internalKey);
    return this.notificationsService.sendTemplate(dto);
  }
}
