import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Public } from '../common/decorators/public.decorator';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { CreateSiteReviewDto } from './dto/review.dto';
import { ReviewsService } from './reviews.service';

@ApiTags('reviews')
@Controller('reviews')
export class ReviewsController {
  constructor(private readonly reviews: ReviewsService) {}

  @Post()
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Submit a dive site review' })
  create(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: CreateSiteReviewDto,
  ) {
    return this.reviews.create(token, user.id, dto);
  }

  @Public()
  @Get('site/:siteId')
  @ApiOperation({ summary: 'List reviews for a dive site' })
  listForSite(@Param('siteId') siteId: string) {
    return this.reviews.listForSite(undefined, siteId);
  }
}
