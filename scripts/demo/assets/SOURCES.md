# Asset sources — Biblo demo corpus

Collected 2026-10-12. Every file is a **byte-for-byte copy** of an official Microsoft or GitHub file. Nothing has been redrawn, recolored, cropped or edited; only the file names were changed. Each file was checked with `file`, parsed with Python `xml.etree`, rendered to `previews/*.png` with headless Microsoft Edge, and visually inspected.

**The SVGs aren't in git** (see `.gitignore`), and neither are the demo files made from them. Before running `scripts/make-demo.sh`, download each one from its direct source below, save it here under the name in the table, and check its sha256.

> **Usage caution, applies to all files.** The Microsoft icon terms permit use "in architectural diagrams, training materials, or documentation". GitHub's terms allow a logo "in a blog post or news article about GitHub" but forbid modifying it or implying affiliation or endorsement. Microsoft's general Trademark and Brand Guidelines (https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) are stricter: "our logos, app and product icons, illustrations, photographs, videos, and designs can never be used without an express license", and "Don't alter, animate, distort, or misappropriate Microsoft's Brand Assets". A public social-media demo may fall outside these permitted uses, so confirm through the proper internal brand/trademark channel before posting. The safest pattern is to show the logos only *inside* sample documents and diagrams in the corpus, never as Biblo's own branding. MIT licenses on the icon *packages* are copyright licenses; they don't grant trademark rights.

| File | What it is | sha256 |
|---|---|---|
| `microsoft-foundry.svg` | Microsoft Foundry service icon (Azure Architecture Icons V24) | `fab039a771f72780ae34e59065d61c66a02d3c347d50923ef2956f34912ea02c` |
| `microsoft-fabric.svg` | Microsoft Fabric product icon, 48 px color | `ef80d2edbfc1b045241d2e9550b7930b648d8018e0274116a3df6d6ccf3adbf9` |
| `microsoft-copilot-2023.svg` | Microsoft Copilot icon, **2023–2026 design (superseded)** | `e5a0ff6dc93e0f2c86f7d4d53e0be24de7171667a706e14cb67e7736a01450c4` |
| `github-copilot.svg` | GitHub Copilot octicon, 96 px (UI icon) | `7278b4cf7e491143c95cdf1327db4f6535b288d97075a9a1cb1b9d82da5f1ba5` |
| `github-copilot-lockup.svg` | Official "GitHub Copilot" product lockup, black | `204fcf55a8e36a3e233483561ec80d4c025c997d04cd37a13941b8fe2c976f1b` |

---

## 1. `microsoft-foundry.svg`
- **What:** The Microsoft Foundry service icon: an indigo/blue folded-ribbon shape. SVG, `viewBox="0 0 18 18"`, 2,824 bytes.
- **Original file:** `Azure_Public_Service_Icons/Icons/ai + machine learning/035746832-icon-service-AI-Foundry.svg` inside the V24 zip. The file name keeps the legacy "AI-Foundry" naming, while the documentation page calls the product **Microsoft Foundry**.
- **Direct source:** https://arch-center.azureedge.net/icons/Azure_Public_Service_Icons_V24.zip
- **Documented on:** https://learn.microsoft.com/en-us/azure/architecture/icons/ (ms.date 2026-07-09). The July 2026 changelog row says: "this batch includes 10 new or updated Microsoft Foundry icons, including Foundry Models, Foundry Projects, and Foundry Agent Service."
- **Terms (quoted from that page):** "Microsoft permits the use of these icons in architectural diagrams, training materials, or documentation. You can copy, distribute, and display the icons only for the permitted use unless granted explicit permission by Microsoft. Microsoft reserves all other rights."
  - Don'ts on the same page: "Don't crop, flip, or rotate icons." / "Don't distort or change icon shape in any way." / "Don't use Microsoft product icons to represent your product or service."
  - The zip also contains `Microsoft_Terms_of_Use.pdf`, which has the same terms.
- **Related official icons in the same zip (not extracted):** Foundry Agent Service, Foundry Models, Foundry Control Plane, Foundry Local, Foundry Labs, Foundry Project, Foundry Application, AI Foundry IQ, and the legacy AI Studio icon.

## 2. `microsoft-fabric.svg`
- **What:** The Microsoft Fabric product icon, a green/teal folded-ribbon "F". This is the 48 px color variant, the largest size in the set. 4,558 bytes.
  - The SVG has `width`/`height` of 48 but **no `viewBox`**, so it won't scale with CSS. Wrap it or rasterize it at a higher device-scale factor.
- **Original file:** `v6.1.0/package/dist/svg/fabric_48_color.svg` inside Icons.zip (npm package `@fabric-msft/svg-icons` 6.1.0, built 2026-02-27).
  - It is byte-identical to `svg/fabric_48_color.svg` in the latest npm release, **8.4.0** (changelog date 10 Aug 2026), checked via https://cdn.jsdelivr.net/npm/@fabric-msft/svg-icons@8.4.0/svg/fabric_48_color.svg.
- **Direct source:** https://raw.githubusercontent.com/microsoft/fabric-samples/main/docs-samples/Icons.zip
  - Linked from https://github.com/microsoft/fabric-samples/blob/main/docs-samples/Icons.zip; last updated by commit `564ec41397`, 2026-02-28, "Updating Icons".
- **Documented on:** https://learn.microsoft.com/en-us/fabric/fundamentals/icons ("Download icons from GitHub").
- **Terms (quoted):** "Microsoft permits the use of these icons in architectural diagrams, training materials, or documentation. You can copy, distribute, and display the icons only for the permitted use unless granted explicit permission by Microsoft. Microsoft reserves all other rights. Fabric icons are also available as a npm package for use in Microsoft Fabric platform extension development."
  - Same Don'ts as the Azure page.
  - The package `LICENSE` reads "MIT License / Copyright (c) 2025 Microsoft Corporation".
  - The package.json description reads "A publicly available collection of SVG icons for use in Microsoft Fabric platform extension development."

## 3. `microsoft-copilot-2023.svg` ⚠️ previous design
- **What:** The Microsoft Copilot icon in the multicolor two-ribbon design (blue/green/yellow plus pink/orange/purple), used from 2023 until the 2026 redesign. 48 px color, 3,423 bytes, no `viewBox`.
- **Original file:** `v6.1.0/package/dist/svg/copilot_48_color.svg` in the same official Fabric Icons.zip as #2. It is still byte-identical in the latest npm release, 8.4.0 (2026-08-10).
- **Direct source and documentation page:** same as #2. **Terms:** same as #2.
- **Why the name says 2023:** Microsoft has replaced this icon.
  - Microsoft Design, "More than a mark — How Copilot's icon joined the conversation" (published 2026-10-05, https://microsoft.design/articles/more-than-a-mark/), describes the new icon as two simple rounded-square forms forming one silhouette. Its image alt text describes the change as "redesigning a single, complex overlapping ribbon into two simplified rectangular shapes with the same blue-to-pink gradient".
- **No official download of the new (2026) icon was found.** These sources were checked:
  - Fluent UI System Icons: none of its 2,994 icon folders is a Copilot icon.
  - Azure Architecture Icons V24: none.
  - Microsoft 365 architecture/content icons: retired page, no Copilot icon.
  - Power Platform icons: only Copilot Studio and Agent 365.
  - Dynamics 365 icons: none.
  - Fabric icons 8.4.0: still the old design.
  - news.microsoft.com image gallery: only 2023 marketing graphics.
  - Third-party copies (seeklogo, Wikimedia "Microsoft-copilot-2026-seeklogo.svg", Figma community files, brandlogos.net) were **rejected as unofficial**.
  - The current mark should be requested through official Microsoft brand channels, not copied from a website.

## 4. `github-copilot.svg`
- **What:** The Primer Octicon `copilot-96.svg`, the GitHub Copilot icon (a friendly pilot/robot head with goggles). This is the largest size; the set also has 16, 24 and 48 px, plus `copilot-error-16` and `copilot-warning-16`. `viewBox="0 0 96 96"`, 1,990 bytes.
  - **It's a UI icon, not the current logo.** GitHub's brand toolkit says: "Beginning in 2025, GitHub Copilot no longer has a standalone logo that heros the Copilot icon." Use #5 where a logo is needed.
- **Direct source (pinned commit):** https://raw.githubusercontent.com/primer/octicons/97825f832c98f817867f770d084c08e3edc6f78c/icons/copilot-96.svg
  - Commit dated 2026-10-07; the latest release tag seen was `@primer/octicons-react@19.40.0`.
- **Documented on:** https://github.com/primer/octicons (README) and https://primer.style/octicons/.
- **Terms (quoted from README):** "(c) GitHub, Inc. When using the GitHub logos, be sure to follow the GitHub logo guidelines (https://github.com/logos). Code License: MIT".
  - LICENSE: "MIT License … Copyright (c) 2026 GitHub Inc."

## 5. `github-copilot-lockup.svg`
- **What:** The official **GitHub Copilot** product lockup: the Invertocat plus the "GitHub Copilot" wordmark, in black. 734×95, 9,620 bytes.
  - The zip also has White and `_Clearspace` variants, plus `Copilot_Lockup_*` (Invertocat + "Copilot") and `Copilot_Icon_*` files.
- **Original file:** `GitHub Logos/SVG/GitHub_Copilot_Lockup_Black.svg` inside GitHub_Logos.zip (files dated 2026-01-09).
- **Direct source:** https://brand.github.com/GitHub_Logos.zip (https://github.com/logos redirects to the brand toolkit).
- **Documented on:** https://brand.github.com/foundations/logo and https://brand.github.com/brand-identity/copilot.
  - From the Copilot page: "Product-specific lockups like GitHub Copilot allow the product to build its own recognition while maintaining connection to the GitHub ecosystem."
- **Terms (quoted from the logo page):** "No adaptation or use of any kind of any of our registered trademarks or copyrights, or any other contents of this website, is allowed without the express written permission of GitHub, Inc."
  - Do's include: "Blog posts and news: Use the GitHub logo in a blog post or news article about GitHub."
  - Don'ts include: "Do not use the GitHub name or any GitHub logo in a way that suggests you are GitHub, your offering or project is by GitHub, or that GitHub is endorsing you…"; "Do not use any GitHub logo as the icon or logo for your business/organization…"; "Do not modify the permitted GitHub logos, including changing the color, dimensions, or combining with other words or design elements."
