<script module lang="ts">
  let lifecycleRegistered = false;
</script>

<script lang="ts">
  import { browser } from "$app/environment";
  import { afterNavigate } from "$app/navigation";
  import type { Snippet } from "svelte";

  import "@tiqian/core/styles.css";
  import { registerSnapshotBundle } from "@tiqian/web-component/snapshot-client";

  import type { PreparedTiqianProse } from "./server.js";

  interface Props {
    html?: string;
    prepared?: PreparedTiqianProse;
    disabled?: boolean;
    strongAsEmphasisMarks?: boolean;
    emphasisDotGapEm?: number;
    class?: string;
    children?: Snippet;
    [attribute: string]: unknown;
  }

  let {
    html,
    prepared,
    disabled = false,
    strongAsEmphasisMarks = false,
    emphasisDotGapEm,
    class: className,
    children,
    ...attributes
  }: Props = $props();
  let proseElement = $state<HTMLElement>();
  const renderedHtml = $derived(prepared?.html ?? html);
  const rootAttributes = $derived(prepared?.rootAttributes ?? {});

  const resolveSnapshotRef = () => {
    const snapshot = prepared?.snapshot;
    if (!snapshot || !browser) return snapshot?.id;
    const registered = document.getElementById(snapshot.id);
    if (registered?.tagName === "TEMPLATE") return snapshot.id;
    try {
      return registerSnapshotBundle(snapshot);
    } catch (error) {
      console.warn("Tiqian client snapshot registration failed", error);
      return undefined;
    }
  };

  const snapshotRef = $derived(resolveSnapshotRef());

  $effect(() => {
    proseElement?.toggleAttribute("disabled", Boolean(disabled));
  });

  if (browser && !lifecycleRegistered) {
    lifecycleRegistered = true;
    afterNavigate(() => {
      void import("@tiqian/web-component/element");
    });
  }
</script>

<tiqian-prose
  bind:this={proseElement}
  {...attributes}
  {...rootAttributes}
  class={className}
  snapshot-ref={snapshotRef}
  disabled={disabled}
  strong-as-emphasis-marks={strongAsEmphasisMarks || undefined}
  emphasis-dot-gap-em={emphasisDotGapEm}
>
  {#if renderedHtml !== undefined}
    {@html renderedHtml}
  {:else if children}
    {@render children()}
  {/if}
</tiqian-prose>
