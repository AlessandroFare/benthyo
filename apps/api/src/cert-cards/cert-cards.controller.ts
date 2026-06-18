import { Body, Controller, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { CertCardsService } from './cert-cards.service';
import { ParseCertCardDto, SaveCertCardDto } from './dto/cert-card.dto';

@ApiTags('cert-cards')
@Controller('cert-cards')
export class CertCardsController {
  constructor(private readonly certCards: CertCardsService) {}

  @Post('parse')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Parse certification card text (OCR output)' })
  parse(@Body() dto: ParseCertCardDto) {
    return this.certCards.parse(dto);
  }

  @Post()
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Save verified certification card record' })
  save(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: SaveCertCardDto,
  ) {
    return this.certCards.save(token, user.id, dto);
  }
}
