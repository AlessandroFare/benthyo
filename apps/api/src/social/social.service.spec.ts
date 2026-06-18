import { Test, TestingModule } from '@nestjs/testing';
import { BadRequestException } from '@nestjs/common';
import { SocialService } from './social.service';
import { SupabaseService } from '../database/supabase.service';

describe('SocialService', () => {
  let service: SocialService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SocialService,
        {
          provide: SupabaseService,
          useValue: {
            createClient: jest.fn(),
            anonClient: jest.fn(),
          },
        },
      ],
    }).compile();

    service = module.get(SocialService);
  });

  it('rejects self-messaging', async () => {
    await expect(
      service.getOrCreateConversation('token', 'user-1', 'user-1'),
    ).rejects.toThrow(BadRequestException);
  });
});
