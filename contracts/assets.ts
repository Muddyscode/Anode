// Asset register (domain model E9, E10; C4 to C6, A10).

import { z } from "zod";
import {
  AssetType,
  CoatingStatus,
  Environment,
  Material,
  NonBlank,
  OrgScoped,
  PageInput,
  Timestamp,
  Uuid,
  page,
} from "./common";

const Latitude = z.number().min(-90).max(90);
const Longitude = z.number().min(-180).max(180);

const AssetFields = {
  name: NonBlank(120),
  assetType: AssetType,
  material: Material,
  coatingStatus: CoatingStatus,
  coatingDescription: NonBlank(500).nullable(),
  environment: Environment,
  /** R5 flags. No defaults: the person must answer each one (A10). */
  isInsulated: z.boolean(),
  isPressureContaining: z.boolean(),
  failureCouldInjure: z.boolean(),
  locationText: NonBlank(500).nullable(),
  latitude: Latitude.nullable(),
  longitude: Longitude.nullable(),
};

/** C6: latitude and longitude come together. */
const bothOrNeither = (v: { latitude?: number | null | undefined; longitude?: number | null | undefined }) =>
  (v.latitude == null) === (v.longitude == null);

export const Asset = z.strictObject({
  id: Uuid,
  orgId: Uuid,
  ...AssetFields,
  /** Phase 1 grades coated steel only (C32). Derived for the UI; the grading engine enforces it. */
  gradeable: z.boolean(),
  archivedAt: Timestamp.nullable(),
  createdAt: Timestamp,
});

export const InspectionPoint = z.strictObject({
  id: Uuid,
  assetId: Uuid,
  label: z.string(),
  description: z.string().nullable(),
  archivedAt: Timestamp.nullable(),
  /** Most recent inspection, for the point list. */
  lastInspectedAt: Timestamp.nullable(),
});

// listAssets ---------------------------------------------------------------------------
export const ListAssetsInput = OrgScoped.extend({
  includeArchived: z.boolean().default(false),
  search: z.string().trim().max(120).optional(),
  page: PageInput.default({ limit: 25 }),
});
export const ListAssetsOutput = page(Asset);

// getAsset -----------------------------------------------------------------------------
export const GetAssetInput = z.strictObject({ assetId: Uuid });
export const GetAssetOutput = z.strictObject({ asset: Asset, points: z.array(InspectionPoint) });

// createAsset --------------------------------------------------------------------------
export const CreateAssetInput = OrgScoped.extend({
  /** Optional client-made id, so a retried request does not create a duplicate (A4). */
  id: Uuid.optional(),
  ...AssetFields,
  coatingDescription: AssetFields.coatingDescription.default(null),
  locationText: AssetFields.locationText.default(null),
  latitude: AssetFields.latitude.default(null),
  longitude: AssetFields.longitude.default(null),
}).refine(bothOrNeither, { message: "Give both latitude and longitude, or neither", path: ["longitude"] });
export const CreateAssetOutput = Asset;

// updateAsset --------------------------------------------------------------------------
export const UpdateAssetInput = z
  .strictObject({
    assetId: Uuid,
    patch: z.strictObject(AssetFields).partial(),
  })
  .refine(({ patch }) => Object.keys(patch).length > 0, "Nothing to update")
  .refine(
    ({ patch }) => !("latitude" in patch || "longitude" in patch) || bothOrNeither(patch),
    { message: "Give both latitude and longitude, or neither", path: ["patch", "longitude"] },
  );
export const UpdateAssetOutput = Asset;

// archiveAsset -------------------------------------------------------------------------
/** Assets are archived, never deleted (section 2). `archived: false` restores one. */
export const ArchiveAssetInput = z.strictObject({ assetId: Uuid, archived: z.boolean() });
export const ArchiveAssetOutput = Asset;

// createPoint --------------------------------------------------------------------------
export const CreatePointInput = z.strictObject({
  id: Uuid.optional(),
  assetId: Uuid,
  label: NonBlank(120),
  description: NonBlank(500).nullable().default(null),
});
export const CreatePointOutput = InspectionPoint;

// updatePoint --------------------------------------------------------------------------
export const UpdatePointInput = z
  .strictObject({
    pointId: Uuid,
    patch: z.strictObject({ label: NonBlank(120), description: NonBlank(500).nullable() }).partial(),
  })
  .refine(({ patch }) => Object.keys(patch).length > 0, "Nothing to update");
export const UpdatePointOutput = InspectionPoint;

// archivePoint -------------------------------------------------------------------------
export const ArchivePointInput = z.strictObject({ pointId: Uuid, archived: z.boolean() });
export const ArchivePointOutput = InspectionPoint;
