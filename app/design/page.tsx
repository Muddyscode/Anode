import type { Metadata } from "next";
import { DesignSystem } from "./DesignSystem";

export const metadata: Metadata = {
  title: "Design system | Anode",
  description: "Galvanic Steel: Anode's tokens and components, in light and dark.",
};

export default function DesignPage() {
  return <DesignSystem />;
}
