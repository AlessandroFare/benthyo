import {
  CallHandler,
  ExecutionContext,
  Injectable,
  Logger,
  NestInterceptor,
} from '@nestjs/common';
import { Observable, tap } from 'rxjs';
import { AuthenticatedRequest } from '../types/request.interface';

@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger('HTTP');

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const { method, url } = request;
    const userId = request.user?.id ?? 'anonymous';
    const started = Date.now();

    return next.handle().pipe(
      tap({
        next: () => {
          const ms = Date.now() - started;
          this.logger.log(`${method} ${url} user=${userId} ${ms}ms`);
        },
        error: (err: Error) => {
          const ms = Date.now() - started;
          this.logger.warn(
            `${method} ${url} user=${userId} ${ms}ms error=${err.message}`,
          );
        },
      }),
    );
  }
}
