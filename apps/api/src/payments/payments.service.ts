import { Injectable } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import { CreatePaymentLinkDto } from '../medical/dto/medical.dto';

@Injectable()
export class PaymentsService {
  constructor(private readonly supabase: SupabaseService) {}

  async listForOperator(token: string, operatorId: string) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('operator_payment_links')
        .select('*')
        .eq('operator_id', operatorId)
        .order('created_at', { ascending: false })
        .limit(50),
    );
  }

  async create(
    token: string,
    userId: string,
    operatorId: string,
    dto: CreatePaymentLinkDto,
  ) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('operator_payment_links')
        .insert({
          operator_id: operatorId,
          created_by: userId,
          amount_cents: dto.amount_cents,
          currency: dto.currency ?? 'eur',
          description: dto.description,
          payment_url: dto.payment_url,
          customer_email: dto.customer_email ?? null,
        })
        .select('*')
        .single(),
    );
  }
}
