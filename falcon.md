---
title: "Accessible Checkpoints Drive Falcon Adoption"
permalink: /falcon/
excerpt: "Across 137 Hugging Face checkpoints, the Falcon models people actually download are the accessible ones: the small sizes and the ready-to-run builds."
header:
  overlay_image: /assets/images/hero-ember.svg
  overlay_filter: 0.5
  teaser: /assets/images/falcon_adoption.png
toc: true
toc_sticky: true
---

*TII has shipped 137 Falcon checkpoints on Hugging Face since 2023: many sizes, several architectures, and a wide range of quantized and edge builds. This post looks at the download numbers across all of them, with one question in mind. What actually drives adoption?*

The answer is consistent across every era. The checkpoints people download are the accessible ones. Small sizes that run on common hardware, and builds that are ready to use without extra work, pull far more traffic than large or hard-to-run models, regardless of how capable those larger models are. Where TII shipped accessible variants, adoption followed.

## Methodology

All figures come from the `tiiuae` org on Hugging Face: all-time downloads and rolling 30-day downloads for every repository, plus each repo's release date. I split the 137 repos into three groups: the legacy models (Falcon 1.0, Falcon2, and Falcon-Mamba), Falcon3, and the specialized lines that followed (Falcon-H1, Falcon-E, Tiny, and the multimodal models). One caveat to keep in mind: a lot of real-world GGUF and quantized usage goes through community re-uploads (TheBloke, bartowski, and others) rather than the official `tiiuae` repos, so these counts understate how much the accessible, quantized builds actually get used.

![Falcon adoption across three eras](/assets/images/falcon_adoption.png)

## 2023: runnable beat large

The original Falcon line accounts for 59.4M of the family's 63.7M lifetime downloads, about 93% of the total, from 26 repos. The split inside that number is the first piece of evidence.

| Model | Released | All-time downloads |
|---|---|---|
| falcon-7b-instruct | Apr 2023 | 27,076,974 |
| falcon-7b | Apr 2023 | 14,033,599 |
| falcon-40b-instruct | May 2023 | 10,506,479 |
| falcon-40b | May 2023 | 2,675,561 |
| falcon-rw-1b | Apr 2023 | 2,257,675 |
| falcon-180B | Aug 2023 | 282,109 |
| falcon-180B-chat | Sep 2023 | 226,360 |

The two 7B checkpoints add up to about 41M between them. Falcon-180B was the largest open model available when it shipped and the most capable Falcon at the time, but it needs roughly eight A100s to load, and its downloads landed two orders of magnitude below the 7B. People picked the size they could run. That preference set the direction for everything TII did next.

## Mamba: shipping ready-to-run formats

Falcon2 (May 2024) was two checkpoints: `falcon-11B` (574K all-time) and `falcon-11B-vlm` (43K). Lean in count, but each one was downloaded heavily.

Falcon-Mamba (mid-2024) introduced the habit that mattered most for accessibility. Alongside the 7B state-space base (614K) and instruct (366K) models, TII shipped a full range of quantized formats: 4-bit, Q8_0, Q4_K_M, F16, and BF16 GGUFs. The point was to let people pull the exact build their setup needs without converting anything themselves. `falcon-mamba-7b` still gets around 145K downloads a month, which keeps it among the more active Falcon models today.

## Falcon3: more accessible variants, and the small ones lead

Falcon3 (December 2024) widened the catalog to 40 repositories: four sizes (1B, 3B, 7B, 10B) in base and instruct, a Mamba-7B variant, and a long list of quantizations (GGUF, AWQ, GPTQ-Int4/Int8, and 1.58-bit BitNet). The aim was an official build for almost any size, framework, and precision.

It lifted the total. Falcon3 has 2.53M downloads, about 4.1x Falcon2. More useful for the question here is which builds inside Falcon3 attract current traffic. Ranked by downloads over the last 30 days, the smaller instruct models lead, not the flagships:

| Model | Size | 30-day downloads |
|---|---|---|
| Falcon3-3B-Instruct | 3B | 24,154 |
| Falcon3-1B-Instruct | 1B | 23,546 |
| Falcon3-7B-Instruct | 7B | 13,130 |
| Falcon3-10B-Instruct | 10B | 5,276 |

The 1B and 3B models each pull more recent traffic than the 7B, and several times more than the 10B. The same model family, released the same day, and the smaller a checkpoint is, the more people are still reaching for it.

![Falcon2 vs Falcon3: breadth vs depth](/assets/images/falcon2_vs_falcon3.png)

## Falcon-H1: the smallest models are the breakouts

After Falcon3, TII kept adding accessible variants: the Falcon-H1 hybrid-attention line from 0.5B up to 34B, a Tiny line down to 90M parameters, Falcon-E BitNet edge models, and the Falcon-OCR and Falcon-Perception multimodal models. Over the last 30 days this whole group pulled 232K downloads, more than the entire Falcon3 family at 127K.

Almost all of that recent traffic goes to the smallest models. Lining up the Falcon-H1 base checkpoints by size makes the relationship hard to miss:

| Base model | Size | All-time downloads |
|---|---|---|
| Falcon-H1-0.5B-Base | 0.5B | 563,120 |
| Falcon-H1-3B-Base | 3B | 32,617 |
| Falcon-H1-34B-Base | 34B | 28,927 |
| Falcon-H1-7B-Base | 7B | 28,891 |
| Falcon-H1-1.5B-Base | 1.5B | 26,154 |

The 0.5B base has roughly 17x the downloads of any larger base in its own line, and at about 127K downloads in the last month it is the most active Falcon model after the legacy falcon-7b. The second most-downloaded model in this era is `Falcon-H1-Tiny-90M-Instruct` at 327K all-time, the smallest model TII ships. Even among the quantized builds, the most active one recently is `Falcon-H1-Tiny-90M-Instruct-GGUF`: tiny and ready to run, with about 10K downloads in the last month. The smallest, easiest-to-run checkpoints are the ones doing the work.

## A note on the falling per-model numbers

It would be easy to read the drop in per-model downloads across generations as a decline. A like-for-like on the 7B-Instruct flagship looks steep:

| Flagship | Released | Lifetime rate |
|---|---|---|
| falcon-7b-instruct | 2023 | ~711K / month |
| Falcon3-7B-Instruct | 2024 | ~25K / month |
| Falcon-H1-7B-Instruct | 2025 | ~4.3K / month |

Most of that is the market, not the models. Falcon was one of the only open models worth running in 2023, before Llama 2/3, Mistral, Qwen, and Gemma arrived. Once they did, downloads spread across far more options for everyone. The signal that survives the crowding is the one this post is about: within each generation, in any market, the accessible variants are what people choose.

## Takeaways

The Falcon catalog points the same way in every era. In 2023 the runnable 7B beat the larger, more capable 180B by two orders of magnitude. In Falcon3 the 1B and 3B models lead current downloads over the flagships. In Falcon-H1 the 0.5B base and the 90M Tiny model are the two most-downloaded checkpoints of the whole era. Capability and parameter count track adoption far less than whether a model is small enough to run and ready to use.

For anyone shipping open models, the lesson is practical. Releasing accessible variants, small sizes and ready-to-run builds, is what turns a model into something people actually download. TII's growing investment in small and edge models (Falcon-E, Falcon-H1-0.5B, the Tiny line) is aimed exactly where the downloads have always gone.

---

*Data: Hugging Face Hub API (`author=tiiuae`), all 137 repositories, snapshot as of June 2026. Download counts reflect official `tiiuae` repos only and exclude community re-uploads.*

*Back to [the blog home](../index.md).*
