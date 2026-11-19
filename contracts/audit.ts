// Audit log (domain model E23; D8). Read-only; inspectors and admins only.

import { z } from "zod";
import { AuditAction, AuditActorKind, OrgScoped, PageInput, Timestamp, Uuid, page } from "./common";

export const AuditEvent = z.strictObject({
  id: z.number().int().positive(),
  occurredAt: Timestamp,
  actorId: Uuid.nullable(),
  actorName: z.string().nullable(),
  actorKind: AuditActorKind,
  action: AuditAction,
  entityType: z.string(),
  entityId: Uuid,
  details: z.record(z.string(), z.unknown()),
});

// listAuditEvents --------------------------------------------------------------------
export const ListAuditEventsInput = OrgScoped.extend({
  entityType: z.enum(["report", "finding", "finding_escalation"]).optional(),
  entityId: Uuid.optional(),
  action: AuditAction.optional(),
  page: PageInput.default({ limit: 50 }),
});
export const ListAuditEventsOutput = page(AuditEvent);
