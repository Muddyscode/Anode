"use client";

import { Button } from "./Button";

/** GeoJSON MultiPolygon coordinates in image pixels (contracts: MultiPolygon, A12). */
export type OutlineCoordinates = number[][][][];

export interface PhotoFrameProps {
  /** Image URL. Omitted only in previews, which show a plain placeholder. */
  src?: string;
  alt: string;
  /** The image's size in pixels; the outline uses the same coordinates. */
  widthPx: number;
  heightPx: number;
  /** Corrosion outline from the measurement. */
  outline?: OutlineCoordinates;
  /** measuring: the pulse laps the outline. measured: the outline draws on. rejected: reason and Retake. */
  state: "measuring" | "measured" | "rejected";
  /** Bottom-left caption, mono uppercase. */
  caption: string;
  /** Bottom-right scale card label, e.g. "ANODE SCALE 50 MM". Omitted when no scale card. */
  scaleLabel?: string;
  /** Why the photo was rejected, e.g. "No scale reference found". */
  rejectionReason?: string;
  onRetake?: () => void;
}

/** Fixed colours taken from the design system's PhotoFrame preview: they sit on a photo, not a theme. */
const PHOTO_PLACEHOLDER = "#6B4A36";
const SCALE_CARD_BG = "#F6F7F9";
const SCALE_CARD_INK = "#0E1420";
const CAPTION_SCRIM = "rgba(14, 20, 32, 0.72)";
const CAPTION_TEXT = "#FFFFFF";

function outlinePath(coords: OutlineCoordinates): string {
  return coords
    .flatMap((polygon) =>
      polygon.map((ring) => ring.map(([x, y], i) => `${i === 0 ? "M" : "L"}${x} ${y}`).join(" ") + " Z"),
    )
    .join(" ");
}

const Corner = ({ position }: { position: string }) => (
  <span aria-hidden="true" className={`absolute size-[18px] border-photo-mark ${position}`} />
);

/**
 * The inspection photo, framed like a report figure: blueprint corner marks, the corrosion outline
 * drawn in photo-mark with a 14% cobalt fill, the scale card label and a caption.
 */
export function PhotoFrame(props: PhotoFrameProps) {
  const { src, alt, widthPx, heightPx, outline, state, caption, scaleLabel, rejectionReason, onRetake } = props;
  const d = outline && state !== "rejected" ? outlinePath(outline) : null;
  return (
    <figure className="m-0 flex flex-col gap-3">
      <div
        className="relative w-full overflow-hidden rounded-md"
        style={{ aspectRatio: `${widthPx} / ${heightPx}`, background: PHOTO_PLACEHOLDER }}
      >
        {src ? (
          // eslint-disable-next-line @next/next/no-img-element -- signed storage URLs, sized by aspect-ratio
          <img src={src} alt={alt} className="absolute inset-0 size-full object-cover" />
        ) : (
          <span role="img" aria-label={alt} className="absolute inset-0" />
        )}
        {d && (
          <svg
            viewBox={`0 0 ${widthPx} ${heightPx}`}
            preserveAspectRatio="xMidYMid slice"
            aria-hidden="true"
            className="absolute inset-0 size-full"
          >
            <path
              className="ds-outline-draw"
              pathLength={900}
              d={d}
              fill="var(--cobalt)"
              fillOpacity={0.14}
              stroke="var(--photo-mark)"
              strokeWidth={2.5}
              vectorEffect="non-scaling-stroke"
            />
            {state === "measuring" && (
              <path
                className="ds-outline-pulse"
                pathLength={900}
                d={d}
                fill="none"
                stroke="var(--pulse)"
                strokeWidth={4}
                strokeLinecap="round"
                vectorEffect="non-scaling-stroke"
              />
            )}
          </svg>
        )}
        <Corner position="left-2 top-2 border-t-2 border-l-2" />
        <Corner position="right-2 top-2 border-t-2 border-r-2" />
        <Corner position="left-2 bottom-2 border-b-2 border-l-2" />
        <Corner position="right-2 bottom-2 border-b-2 border-r-2" />
        {scaleLabel && state !== "rejected" && (
          <span
            className="absolute right-4 bottom-4 px-2 py-1 font-mono text-[10px] tracking-[0.06em]"
            style={{ background: SCALE_CARD_BG, color: SCALE_CARD_INK }}
          >
            {scaleLabel}
          </span>
        )}
        <figcaption
          className="absolute bottom-4 left-4 px-2 py-1 font-mono text-[10px] tracking-[0.06em] uppercase"
          style={{ background: CAPTION_SCRIM, color: CAPTION_TEXT }}
        >
          {caption}
        </figcaption>
      </div>
      {state === "rejected" && (
        <div className="flex flex-wrap items-center gap-3">
          <p role="alert" className="m-0 text-body text-danger-text">
            {rejectionReason ?? "This photo cannot be graded."}
          </p>
          <Button variant="secondary" onClick={onRetake}>
            Retake photo
          </Button>
        </div>
      )}
    </figure>
  );
}
