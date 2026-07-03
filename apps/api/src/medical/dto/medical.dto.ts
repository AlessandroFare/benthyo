import {
  IsArray,
  IsInt,
  IsOptional,
  IsString,
  IsUrl,
  IsUUID,
  Matches,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

export class SubmitMedicalFormDto {
  @IsUUID()
  template_id!: string;

  @IsOptional()
  @IsUUID()
  operator_id?: string;

  @IsOptional()
  @IsUUID()
  trip_id?: string;

  @IsString()
  @MinLength(2)
  signer_name!: string;

  @IsArray()
  answers!: Array<{ id: string; value: boolean | string }>;
}

export class CreatePaymentLinkDto {
  @IsInt()
  @Min(100)
  amount_cents!: number;

  @IsString()
  @MinLength(3)
  @MaxLength(120)
  description!: string;

  // DD-2.14: The previous version had @IsString + @MinLength(10) which
  // accepted any URL — including javascript: URIs. We now require a real
  // https:// URL AND it must be on a Stripe checkout domain (the
  // standard Benthyo flow generates Stripe Checkout Session URLs).
  @IsUrl({ protocols: ['https'], require_protocol: true, require_valid_protocol: true })
  @Matches(/^https:\/\/(checkout\.stripe\.com|buy\.stripe\.com|billing\.stripe\.com)\//i, {
    message: 'payment_url must be a Stripe Checkout URL (https://checkout.stripe.com/...)',
  })
  @MaxLength(500)
  payment_url!: string;

  @IsOptional()
  @IsString()
  @Matches(/^.+@.+\..+$/, { message: 'customer_email must be a valid email' })
  customer_email?: string;

  @IsOptional()
  @IsString()
  @MinLength(3)
  @MaxLength(3)
  currency?: string;
}

export class CreateApiKeyDto {
  @IsString()
  @MinLength(2)
  name!: string;
}
