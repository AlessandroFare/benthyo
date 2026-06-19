/**
 * Parse certification card text (from client OCR or manual paste).
 * Supports common PADI / SSI patterns.
 */

export interface ParsedCertCard {
  agency: string | null;
  cert_number: string | null;
  cert_level: string | null;
  instructor_name: string | null;
  expiry_date: string | null;
  confidence: number;
}

export function parseCertCardText(raw: string): ParsedCertCard {
  const text = raw.slice(0, 8_000).replace(/\s+/g, ' ').trim();
  let agency: string | null = null;
  if (/\bPADI\b/i.test(text)) agency = 'PADI';
  else if (/\bSSI\b/i.test(text)) agency = 'SSI';
  else if (/\bRAID\b/i.test(text)) agency = 'RAID';
  else if (/\bCMAS\b/i.test(text)) agency = 'CMAS';

  const certNumber =
    text.match(/(?:cert(?:ification)?\s*(?:no|number|#)?[:\s]*)([A-Z0-9-]{5,20})/i)?.[1] ??
    text.match(/\b([0-9]{6,12})\b/)?.[1] ??
    null;

  let certLevel: string | null = null;
  if (/instructor/i.test(text)) certLevel = 'Instructor';
  else if (/divemaster/i.test(text)) certLevel = 'Divemaster';
  else if (/rescue/i.test(text)) certLevel = 'Rescue';
  else if (/advanced|aow/i.test(text)) certLevel = 'AOW';
  else if (/open\s*water|\bow\b/i.test(text)) certLevel = 'OW';

  const instructor =
    text.match(/instructor[:\s]+([A-Za-z .'-]{3,40})/i)?.[1]?.trim() ?? null;

  const expiry =
    text.match(/(?:expir(?:y|es|ation)|valid\s*until)[:\s]*(\d{4}-\d{2}-\d{2}|\d{2}[./]\d{2}[./]\d{4})/i)?.[1] ??
    null;

  let expiryIso: string | null = null;
  if (expiry) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(expiry)) expiryIso = expiry;
    else {
      const dmy = expiry.match(/^(\d{2})[./](\d{2})[./](\d{4})$/);
      if (dmy) expiryIso = `${dmy[3]}-${dmy[2]}-${dmy[1]}`;
    }
  }

  const fields = [agency, certNumber, certLevel, instructor, expiryIso].filter(Boolean);
  const confidence = Math.min(0.95, 0.35 + fields.length * 0.12);

  return {
    agency,
    cert_number: certNumber,
    cert_level: certLevel,
    instructor_name: instructor,
    expiry_date: expiryIso,
    confidence,
  };
}
