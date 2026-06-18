import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import { CreateFeedPostDto, SendMessageDto } from './dto/social.dto';

@Injectable()
export class SocialService {
  constructor(private readonly supabase: SupabaseService) {}

  private orderedPair(userId: string, otherId: string): [string, string] {
    if (userId === otherId) {
      throw new BadRequestException('Cannot message yourself');
    }
    return userId < otherId ? [userId, otherId] : [otherId, userId];
  }

  async listConversations(token: string, userId: string) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('buddy_conversations')
        .select('*')
        .or(`participant_a.eq.${userId},participant_b.eq.${userId}`)
        .order('last_message_at', { ascending: false, nullsFirst: false }),
    );
  }

  async getOrCreateConversation(token: string, userId: string, otherId: string) {
    const [a, b] = this.orderedPair(userId, otherId);
    const client = this.supabase.createClient(token);

    const existing = assertNoError(
      await client
        .from('buddy_conversations')
        .select('*')
        .eq('participant_a', a)
        .eq('participant_b', b)
        .maybeSingle(),
    );
    if (existing) return existing;

    return assertNoError(
      await client
        .from('buddy_conversations')
        .insert({ participant_a: a, participant_b: b })
        .select('*')
        .single(),
    );
  }

  async listMessages(token: string, userId: string, conversationId: string) {
    const client = this.supabase.createClient(token);
    await this.assertParticipant(client, userId, conversationId);

    return assertNoError(
      await client
        .from('buddy_messages')
        .select('*, sender:users(id, username, full_name, avatar_url)')
        .eq('conversation_id', conversationId)
        .order('created_at', { ascending: true })
        .limit(100),
    );
  }

  async sendMessage(token: string, userId: string, dto: SendMessageDto) {
    const conv = await this.getOrCreateConversation(token, userId, dto.recipient_id);
    const client = this.supabase.createClient(token);

    return assertNoError(
      await client
        .from('buddy_messages')
        .insert({
          conversation_id: conv.id,
          sender_id: userId,
          body: dto.body.trim(),
        })
        .select('*, sender:users(id, username, full_name, avatar_url)')
        .single(),
    );
  }

  async listFeed(token: string | undefined, limit = 30) {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    return assertNoError(
      await client
        .from('social_feed_posts')
        .select(
          '*, user:users(id, username, full_name, avatar_url), site:dive_sites(name, slug)',
        )
        .order('created_at', { ascending: false })
        .limit(Math.min(limit, 50)),
    );
  }

  async createFeedPost(token: string, userId: string, dto: CreateFeedPostDto) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('social_feed_posts')
        .insert({
          user_id: userId,
          body: dto.body.trim(),
          dive_log_id: dto.dive_log_id ?? null,
          dive_site_id: dto.dive_site_id ?? null,
          photo_url: dto.photo_url ?? null,
        })
        .select(
          '*, user:users(id, username, full_name, avatar_url), site:dive_sites(name, slug)',
        )
        .single(),
    );
  }

  private async assertParticipant(
    client: ReturnType<SupabaseService['createClient']>,
    userId: string,
    conversationId: string,
  ): Promise<void> {
    const conv = assertNoError(
      await client
        .from('buddy_conversations')
        .select('id')
        .eq('id', conversationId)
        .or(`participant_a.eq.${userId},participant_b.eq.${userId}`)
        .maybeSingle(),
    );
    if (!conv) throw new NotFoundException('Conversation not found');
  }
}
