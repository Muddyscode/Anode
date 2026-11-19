// Session, profile, organisation and membership (domain model E1 to E3, section 9).

import { z } from "zod";
import { MemberRole, NonBlank, OrgScoped, Uuid } from "./common";

export const Profile = z.strictObject({
  id: Uuid,
  displayName: z.string(),
  qualification: z.string().nullable(),
});

export const OrganisationMembership = z.strictObject({
  orgId: Uuid,
  name: z.string(),
  role: MemberRole,
  isDemo: z.boolean(),
});

// getSession ----------------------------------------------------------------------
export const GetSessionInput = z.strictObject({});
export const GetSessionOutput = z.strictObject({
  user: Profile,
  organisations: z.array(OrganisationMembership).min(1),
});

// updateProfile -----------------------------------------------------------------
export const UpdateProfileInput = z
  .strictObject({
    displayName: NonBlank(120).optional(),
    /** Printed beside the signature on reports (A21). null clears it. */
    qualification: NonBlank(200).nullable().optional(),
  })
  .refine((v) => v.displayName !== undefined || v.qualification !== undefined, "Nothing to update");
export const UpdateProfileOutput = Profile;

// renameOrganisation (admin) -------------------------------------------------------
export const RenameOrganisationInput = OrgScoped.extend({ name: NonBlank(120) });
export const RenameOrganisationOutput = OrganisationMembership;

// listMembers -------------------------------------------------------------------------
export const Member = z.strictObject({
  userId: Uuid,
  displayName: z.string(),
  role: MemberRole,
  joinedAt: z.string(),
});
export const ListMembersInput = OrgScoped;
export const ListMembersOutput = z.strictObject({ members: z.array(Member) });

// changeMemberRole (admin) ------------------------------------------------------------
export const ChangeMemberRoleInput = OrgScoped.extend({ userId: Uuid, role: MemberRole });
export const ChangeMemberRoleOutput = Member;
