import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { Public } from '../common/decorators/public.decorator';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { CreateFeedPostDto, SendMessageDto } from './dto/social.dto';
import { SocialService } from './social.service';

@ApiTags('social')
@Controller()
export class SocialController {
  constructor(private readonly social: SocialService) {}

  @Get('conversations')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'List buddy DM conversations' })
  listConversations(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.social.listConversations(token, user.id);
  }

  @Get('conversations/:id/messages')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Messages in a conversation' })
  listMessages(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id', new ParseUUIDPipe()) id: string,
  ) {
    return this.social.listMessages(token, user.id, id);
  }

  /**
   * Send a buddy DM. Rate-limited to 30/min/user to prevent DM spam
   * (DD-2.11). The body is trimmed + length-checked by the DB CHECK
   * (BETWEEN 1 AND 2000) as the second line of defense.
   */
  @Post('messages')
  @ApiBearerAuth()
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @ApiOperation({ summary: 'Send a buddy DM (creates conversation if needed)' })
  sendMessage(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: SendMessageDto,
  ) {
    return this.social.sendMessage(token, user.id, dto);
  }

  @Public()
  @Get('feed')
  @ApiOperation({ summary: 'Public social dive feed' })
  listFeed(@Query('limit') limit?: string) {
    return this.social.listFeed(undefined, limit ? Number(limit) : 30);
  }

  @Post('feed')
  @ApiBearerAuth()
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @ApiOperation({ summary: 'Post a dive highlight to the social feed' })
  createFeedPost(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: CreateFeedPostDto,
  ) {
    return this.social.createFeedPost(token, user.id, dto);
  }
}
