import {
  BadRequestException,
  Injectable,
  Logger,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Resend } from 'resend';
import { ResendConfig } from '../config/resend.config';
import { SendEmailDto, SendTemplateEmailDto } from './dto/notification.dto';

@Injectable()
export class NotificationsService implements OnModuleInit {
  private readonly logger = new Logger(NotificationsService.name);
  private client: Resend | null = null;
  private config!: ResendConfig;

  constructor(private readonly configService: ConfigService) {}

  onModuleInit(): void {
    this.config = this.configService.get<ResendConfig>('resend')!;
    if (this.config.apiKey) {
      this.client = new Resend(this.config.apiKey);
    } else {
      this.logger.warn('Resend API key is not configured — email sending disabled');
    }
  }

  async sendRaw(dto: SendEmailDto): Promise<{ id: string }> {
    const toList = Array.isArray(dto.to) ? dto.to : [dto.to];

    if (!this.config.apiKey) {
      this.logger.warn(
        `Skipped email (Resend disabled): "${dto.subject}" → ${toList.join(', ')}`,
      );
      return { id: 'dev-skipped' };
    }

    const result = await this.client!.emails.send({
      from: `${this.config.fromName} <${this.config.fromEmail}>`,
      to: toList,
      subject: dto.subject,
      html: dto.html,
      text: dto.text,
    });

    if (result.error) {
      throw new BadRequestException(result.error.message);
    }

    return { id: result.data!.id };
  }

  async sendTemplate(dto: SendTemplateEmailDto): Promise<{ id: string }> {
    const { subject, html, text } = this.renderTemplate(dto.template, dto.data ?? {});

    return this.sendRaw({
      to: dto.to,
      subject,
      html,
      text,
    });
  }

  private renderTemplate(
    template: SendTemplateEmailDto['template'],
    data: Record<string, string>,
  ): { subject: string; html: string; text: string } {
    switch (template) {
      case 'welcome':
        return {
          subject: 'Welcome to Benthyo',
          html: `<p>Hi ${data.name ?? 'diver'},</p><p>Welcome to Benthyo — start logging dives and building your life list.</p>`,
          text: `Hi ${data.name ?? 'diver'}, welcome to Benthyo.`,
        };
      case 'badge_earned':
        return {
          subject: `You earned the ${data.badge_name ?? 'new'} badge!`,
          html: `<p>Congratulations! You earned the <strong>${data.badge_name ?? 'badge'}</strong>.</p>`,
          text: `You earned the ${data.badge_name ?? 'badge'}.`,
        };
      case 'operator_invite':
        return {
          subject: `You've been invited to ${data.operator_name ?? 'an operator'} on Benthyo`,
          html: `<p>You have been invited to join <strong>${data.operator_name ?? 'an operator'}</strong> on Benthyo.</p>`,
          text: `You have been invited to join ${data.operator_name ?? 'an operator'}.`,
        };
      default:
        throw new BadRequestException(`Unknown template: ${template}`);
    }
  }
}