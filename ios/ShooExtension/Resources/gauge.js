// Owner: lead. Score visuals shared by popup.js (content script) and blocked.html. Plain script.
// Figma "Scam Score Gauge / Glass" (half gauge, sheet + block screen) and "Score ring" (mini card).
// One colour set per level; geometry and colours are copied from the Figma export.

(() => {
    /** Level=Sedang (30–49), Level=Tinggi (50–79), Level=Bahaya (≥80). */
    const LEVELS = {
        sedang: {
            halo: "#FFF0DB",
            track: ["#FFEED6", "#FFF7EB"],
            tube: [[0.671, "#FFA21F"], [0.8, "#FFB54D"], [0.9, "#FFC573"], [0.955, "#FFD79E"], [1, "#FFC573"]],
            glow: null, // Figma has no shadow on this level
            shade: null,
        },
        tinggi: {
            halo: "#FFF0DB",
            track: ["#FFE6C4", "#FFF4E3"],
            tube: [[0.68, "#EB8900"], [0.76, "#FF9500"], [0.86, "#FFB752"], [0.95, "#FF9500"], [1, "#E58600"]],
            glow: "rgba(255,148,0,.25)",
            shade: "rgba(166,97,0,.35)",
        },
        bahaya: {
            halo: "#FBE5E4",
            track: ["#F9D9D6", "#FFF4E3"],
            tube: [[0.68, "#C42B1C"], [0.76, "#E5483B"], [0.86, "#FF7A6B"], [0.95, "#E5483B"], [1, "#BF3424"]],
            glow: "rgba(229,71,59,.25)",
            shade: "rgba(138,28,18,.35)",
        },
    };

    const clamp = (score) => Math.min(100, Math.max(0, Number(score) || 0));
    const n = (value) => Number(value.toFixed(3));

    /** Point at `deg` (0 = right, 90 = up) on a circle around (cx, cy); SVG y grows down. */
    function at(cx, cy, r, deg) {
        const rad = (deg * Math.PI) / 180;
        return [n(cx + r * Math.cos(rad)), n(cy - r * Math.sin(rad))];
    }

    /** Ring segment between radii r and R, clockwise on screen from angle `from` to angle `to`. */
    function band(cx, cy, r, R, from, to) {
        const sweep = from - to;
        if (sweep <= 0) return "";
        if (sweep >= 360) return band(cx, cy, r, R, from, from - 359.99);
        const large = sweep > 180 ? 1 : 0;
        const [ax, ay] = at(cx, cy, R, from);
        const [bx, by] = at(cx, cy, R, to);
        const [cx2, cy2] = at(cx, cy, r, to);
        const [dx, dy] = at(cx, cy, r, from);
        return `M${ax} ${ay}A${R} ${R} 0 ${large} 1 ${bx} ${by}L${cx2} ${cy2}A${r} ${r} 0 ${large} 0 ${dx} ${dy}Z`;
    }

    const stops = (list) => list.map(([offset, color]) => `<stop offset="${offset}" stop-color="${color}"/>`).join("");

    /** Inner shadow layer inside the shape, like Figma's "Inner shadow" effect. */
    function inner(result, dx, dy, blur, color) {
        return `<feOffset in="SourceAlpha" dx="${dx}" dy="${dy}"/><feGaussianBlur stdDeviation="${blur}"/>` +
            `<feComposite in2="SourceAlpha" operator="arithmetic" k2="-1" k3="1" result="${result}m"/>` +
            `<feFlood flood-color="${color}"/><feComposite in2="${result}m" operator="in" result="${result}"/>`;
    }

    /** Drop shadow + white top-left highlight + dark bottom-right shade on the coloured tube. */
    function tubeFilter(id, level, k) {
        if (!level.glow) return "";
        return `<filter id="${id}" x="-30%" y="-30%" width="160%" height="170%" color-interpolation-filters="sRGB">` +
            `<feGaussianBlur in="SourceAlpha" stdDeviation="${n(2.5 * k)}"/><feOffset dy="${n(2 * k)}" result="${id}o"/>` +
            `<feFlood flood-color="${level.glow}"/><feComposite in2="${id}o" operator="in" result="${id}d"/>` +
            inner(`${id}h`, n(-k), n(-k), n(k), "rgba(255,255,255,.45)") +
            inner(`${id}s`, n(k), n(1.5 * k), n(1.25 * k), level.shade) +
            `<feMerge><feMergeNode in="${id}d"/><feMergeNode in="SourceGraphic"/><feMergeNode in="${id}h"/><feMergeNode in="${id}s"/></feMerge></filter>`;
    }

    // White fade towards the bottom of the half gauge: the arc ends melt into the card.
    const FADE = '<stop stop-color="#fff" stop-opacity="0"/><stop offset=".26" stop-color="#fff" stop-opacity="0"/>' +
        '<stop offset=".45" stop-color="#fff" stop-opacity=".55"/><stop offset=".56" stop-color="#fff"/>';

    // Dots inside the tube (Figma "Dots strong" / "Dots soft"), in gauge coordinates.
    const DOTS_STRONG = [[23.4, 0.9], [34.65, 0.9], [45.9, 0.9], [90.9, 0.9], [23.4, 12.15], [34.65, 12.15], [57.15, 12.15],
        [68.4, 12.15], [23.4, 23.4], [0.9, 34.65], [0.9, 45.9]].map(([x, y]) => [x + 71.1, y + 38.85]);
    const DOTS_SOFT = [[90.9, 0.9], [57.15, 12.15], [102.15, 12.15], [124.65, 12.15], [135.9, 12.15], [12.15, 23.4], [23.4, 23.4],
        [0.9, 34.65], [0.9, 45.9]].map(([x, y]) => [x + 59.85, y + 38.85]);
    const dots = (list) => list.map(([x, y]) => `<circle cx="${n(x)}" cy="${n(y)}" r=".9"/>`).join("");

    const TICK_OPACITY = [0.18, 0.34, 0.48, 0.57, 0.6, 0.57, 0.48, 0.34, 0.18];

    /**
     * Half gauge, 277.5 × 177.75 (Figma). The score runs from the left horizontal (0) to the right
     * horizontal (100); the band reaches 12.6° further below on both sides and the tube always starts there.
     * @param {number} score  0–100
     * @param {"sedang"|"tinggi"|"bahaya"} levelName
     * @returns {string} SVG markup (no text: callers lay the value and label over it)
     */
    function gauge(score, levelName) {
        const level = LEVELS[levelName] ?? LEVELS.tinggi;
        const [cx, cy, r, R] = [138.75, 132.75, 75, 111.75];
        const start = 192.6;
        const end = -12.6;
        const value = 180 - 1.8 * clamp(score);
        const tube = band(cx, cy, r, R, start, value);
        const ticks = TICK_OPACITY.map((opacity, i) => {
            const deg = 180 - 22.5 * i;
            const [x, y] = at(cx, cy, 81.375, deg);
            return `<rect x="${n(x - 2.625)}" y="${n(y - 0.675)}" width="5.25" height="1.35" rx=".675" fill="rgb(63,77,90)" ` +
                `fill-opacity="${opacity}" transform="rotate(${n(-deg)} ${x} ${y})"/>`;
        }).join("");
        const [nx, ny] = at(cx, cy, 83, value);
        return `<svg xmlns="http://www.w3.org/2000/svg" width="277.5" height="177.75" viewBox="0 0 277.5 177.75" aria-hidden="true">` +
            `<defs>` +
            `<linearGradient id="sg-fade-halo" x1="0" y1="14.25" x2="0" y2="251.25" gradientUnits="userSpaceOnUse">${FADE}</linearGradient>` +
            `<linearGradient id="sg-fade" x1="0" y1="21" x2="0" y2="244.5" gradientUnits="userSpaceOnUse">${FADE}</linearGradient>` +
            `<radialGradient id="sg-track" cx="${cx}" cy="${cy}" r="${R}" gradientUnits="userSpaceOnUse">` +
            stops([[0.67, level.track[0]], [1, level.track[1]]]) + `</radialGradient>` +
            `<radialGradient id="sg-tube" cx="${cx}" cy="${cy}" r="${R}" gradientUnits="userSpaceOnUse">${stops(level.tube)}</radialGradient>` +
            `<filter id="sg-blur" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur stdDeviation="1.125"/></filter>` +
            tubeFilter("sg-shadow", level, 3.1875) +
            `<clipPath id="sg-clip"><path d="${tube}"/></clipPath>` +
            `</defs>` +
            `<g filter="url(#sg-blur)"><path d="${band(cx, cy, R, 118.5, start, end)}" fill="${level.halo}"/>` +
            `<path d="${band(cx, cy, R, 118.5, start, end)}" fill="url(#sg-fade-halo)"/></g>` +
            `<path d="${band(cx, cy, r, R, start, end)}" fill="url(#sg-track)"/>` +
            `<path d="${band(cx, cy, r, R, start, end)}" fill="url(#sg-fade)"/>` +
            (tube
                ? `<g${level.glow ? ' filter="url(#sg-shadow)"' : ""}><path d="${tube}" fill="url(#sg-tube)"/>` +
                  `<path d="${tube}" fill="url(#sg-fade)" fill-opacity=".45"/></g>` +
                  `<g clip-path="url(#sg-clip)" fill="#fff"><g opacity=".95">${dots(DOTS_STRONG)}</g><g opacity=".55">${dots(DOTS_SOFT)}</g></g>`
                : "") +
            ticks +
            `<rect x="${n(nx - 9)}" y="${n(ny - 1.125)}" width="18" height="2.25" rx="1.125" fill="#383d43" ` +
            `transform="rotate(${n(-value)} ${nx} ${ny})"/>` +
            `</svg>`;
    }

    /**
     * Full ring for the mini card, drawn on Figma's 85.94 canvas: the 72 px ring sits at (6.97, 4.65),
     * the rest is room for its shadow. The tube runs clockwise from the top.
     */
    function ring(score, levelName) {
        const level = LEVELS[levelName] ?? LEVELS.tinggi;
        const [cx, cy] = [42.9677, 40.6452];
        const tube = band(cx, cy, 22.9006, 33.6774, 90, 90 - 3.6 * clamp(score));
        const shadow = (id, dy, blur, color) =>
            `<filter id="${id}" x="-30%" y="-30%" width="160%" height="170%" color-interpolation-filters="sRGB">` +
            `${inner(`${id}i`, 0, dy, blur, color)}<feMerge><feMergeNode in="SourceGraphic"/><feMergeNode in="${id}i"/></feMerge></filter>`;
        return `<svg xmlns="http://www.w3.org/2000/svg" width="85.9355" height="85.9355" viewBox="0 0 85.9355 85.9355" aria-hidden="true">` +
            `<defs>` +
            `<filter id="sr-bezel" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dy="2.3226" stdDeviation="3.4839" flood-color="rgba(31,42,55,.08)"/></filter>` +
            shadow("sr-track", 0.5806, 0.5806, "rgba(31,42,55,.08)") +
            shadow("sr-center", 1.1613, 1.1613, "rgba(31,42,55,.06)") +
            tubeFilter("sr-tube", level, 1.1613) +
            `<linearGradient id="sr-bezel-fill" x1="0" y1="4.6452" x2="0" y2="76.6452" gradientUnits="userSpaceOnUse"><stop stop-color="#fff"/><stop offset="1" stop-color="#F3F4F6"/></linearGradient>` +
            `<linearGradient id="sr-center-fill" x1="0" y1="18.9059" x2="0" y2="62.3846" gradientUnits="userSpaceOnUse"><stop stop-color="#FAFAFB"/><stop offset="1" stop-color="#F0F1F3"/></linearGradient>` +
            `<radialGradient id="sr-tube-fill" cx="${cx}" cy="${cy}" r="33.6774" gradientUnits="userSpaceOnUse">${stops(level.tube)}</radialGradient>` +
            `</defs>` +
            `<g filter="url(#sr-bezel)"><circle cx="${cx}" cy="${cy}" r="36" fill="url(#sr-bezel-fill)"/>` +
            `<circle cx="${cx}" cy="${cy}" r="35.7097" fill="none" stroke="#E4E6EA" stroke-width=".5806"/></g>` +
            `<path d="${band(cx, cy, 22.9006, 33.6774, 90, -269.99)}" fill="#ECEDEF" filter="url(#sr-track)"/>` +
            (tube ? `<path d="${tube}" fill="url(#sr-tube-fill)"${level.glow ? ' filter="url(#sr-tube)"' : ""}/>` : "") +
            `<circle cx="${cx}" cy="${cy}" r="21.7394" fill="url(#sr-center-fill)" filter="url(#sr-center)"/>` +
            `<circle cx="${cx}" cy="${cy}" r="21.449" fill="none" stroke="#E3E4E7" stroke-width=".5806"/>` +
            `</svg>`;
    }

    globalThis.ShooGauge = { gauge, ring, LEVELS };
})();
