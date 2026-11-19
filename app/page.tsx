import { redirect } from "next/navigation";

// The inspection flow arrives in Stage 7. Until then the root shows the design system.
export default function Home() {
  redirect("/design");
}
