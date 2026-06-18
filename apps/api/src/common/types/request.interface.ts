import { Request } from 'express';
import { AuthUser } from './auth-user.interface';

export interface AuthenticatedRequest extends Request {
  user: AuthUser;
  accessToken: string;
}
