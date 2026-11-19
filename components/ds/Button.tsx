"use client";

import { useId, type ButtonHTMLAttributes } from "react";

export type ButtonVariant = "primary" | "secondary" | "escalate";

export interface ButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "className" | "style"> {
  variant?: ButtonVariant;
  /** Shown next to a disabled button: why it cannot be used yet ("Add a scale card to grade"). */
  disabledReason?: string;
}

const VARIANT: Record<ButtonVariant, string> = {
  // One per screen: the next step.
  primary: "border-0 bg-cobalt text-on-cobalt",
  secondary: "border-[1.5px] border-line-strong bg-transparent text-ink font-medium",
  // Only for sending a finding to a human inspector.
  escalate: "border-[1.5px] border-sev-4 bg-transparent text-danger-text",
};

/**
 * Buttons are 48px tall with radius-md corners and sentence-case labels in the button style.
 * Focus: 2px cobalt outline, 2px offset. Press: 1px downward nudge over 80ms.
 */
export function Button({ variant = "primary", disabled, disabledReason, type = "button", children, ...rest }: ButtonProps) {
  const reasonId = useId();
  const look = disabled ? "border-0 bg-line text-muted cursor-not-allowed" : VARIANT[variant];
  const showReason = Boolean(disabled && disabledReason);
  const button = (
    <button
      type={type}
      disabled={disabled}
      aria-describedby={showReason ? reasonId : undefined}
      className={`ds-press h-12 rounded-md px-[22px] font-sans text-button whitespace-nowrap ${look}`}
      {...rest}
    >
      {children}
    </button>
  );
  if (!showReason) return button;
  return (
    <span className="inline-flex flex-wrap items-center gap-3">
      {button}
      <span id={reasonId} className="text-body text-muted">
        {disabledReason}
      </span>
    </span>
  );
}
