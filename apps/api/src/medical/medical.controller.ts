import { Body, Controller, Get, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Public } from '../common/decorators/public.decorator';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { SubmitMedicalFormDto } from './dto/medical.dto';
import { MedicalService } from './medical.service';

@ApiTags('medical')
@Controller('medical')
export class MedicalController {
  constructor(private readonly medical: MedicalService) {}

  @Public()
  @Get('template')
  @ApiOperation({ summary: 'Active medical questionnaire template' })
  getTemplate(@Query('operator_id') operatorId?: string) {
    return this.medical.getActiveTemplate(undefined, operatorId);
  }

  @Post('submit')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Submit signed medical questionnaire' })
  submit(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: SubmitMedicalFormDto,
  ) {
    return this.medical.submit(token, user.id, dto);
  }

  @Get('me/submissions')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'My medical form submissions' })
  mySubmissions(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.medical.mySubmissions(token, user.id);
  }
}
