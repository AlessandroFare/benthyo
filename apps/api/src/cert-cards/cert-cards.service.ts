import { Injectable } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import { parseCertCardText } from './cert-card.parser';
import { ParseCertCardDto, SaveCertCardDto } from './dto/cert-card.dto';

@Injectable()
export class CertCardsService {
  constructor(private readonly supabase: SupabaseService) {}

  parse(dto: ParseCertCardDto) {
    return parseCertCardText(dto.raw_text);
  }

  async save(token: string, userId: string, dto: SaveCertCardDto) {
    const parsed = parseCertCardText(dto.raw_text);
    const client = this.supabase.createClient(token);

    const agencyMap: Record<string, string> = {
      PADI: 'PADI',
      SSI: 'SSI',
      RAID: 'RAID',
      CMAS: 'CMAS',
    };
    const levelMap: Record<string, string> = {
      OW: 'OW',
      AOW: 'AOW',
      Rescue: 'Rescue',
      Divemaster: 'Divemaster',
      Instructor: 'Instructor',
    };

    const agency = dto.agency ?? parsed.agency;
    const level = dto.cert_level ?? parsed.cert_level;

    return assertNoError(
      await client
        .from('cert_card_records')
        .insert({
          user_id: userId,
          operator_id: dto.operator_id ?? null,
          photo_url: dto.photo_url ?? null,
          agency: agency ? agencyMap[agency] ?? 'other' : null,
          cert_number: dto.cert_number ?? parsed.cert_number,
          cert_level: level ? levelMap[level] ?? 'OW' : null,
          instructor_name: dto.instructor_name ?? parsed.instructor_name,
          expiry_date: dto.expiry_date ?? parsed.expiry_date,
          raw_ocr_text: dto.raw_text,
          verified_at: new Date().toISOString(),
        })
        .select('*')
        .single(),
    );
  }
}
