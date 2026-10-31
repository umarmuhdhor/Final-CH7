// Owner: lead. Live score bubble (EX-03). Plain content script, loaded after pipeline.js.
// Chrome copy of the Safari pill.js without the card's "See detail" (no Shoo app on Chrome to open).
// The extension can't drive the Dynamic Island (docs/spikes/dynamic-island.md), so the running
// score floats on the page instead: a round button the user can drag to either edge (like a chat
// head). It lives in the page: it exists only while a page is open in Safari and goes away with it.
// Rules: always on screen while a page is open, whatever the score · the number follows every
// (re)scan live (content.js re-checks the page when it changes) · hidden when blocked (block screen
// owns the page, EX-06) · tap opens a small card (status, score, top reasons, Hide) ·
// Hide hides it for the rest of this page · the dragged position is remembered across pages.

(() => {
    const { THRESHOLD } = globalThis.ShooPipeline;
    const MAX_REASONS = 2;
    const SIZE = 56; // bubble diameter, px (≥ 44 pt tap target)
    const MARGIN = 10; // gap between bubble and screen edge, px
    const DEFAULT_POS = { side: "right", y: 0.38 }; // clear of the EX-04 warning card, even on an iPhone SE

    /** "safe" < 30 · "warning" 30–49 · "danger" 50–79. Blocked never reaches the bubble. */
    function toneFor(score) {
        if (score >= THRESHOLD.secondWarning) return "danger";
        if (score >= THRESHOLD.firstWarning) return "warning";
        return "safe";
    }

    /**
     * Pure decision: what the bubble shows for the newest pipeline state. Free of DOM so it can be
     * tested in Node.
     * @returns {{ memo, view: { visible: boolean, score?, tone?, analyzing? } }}
     */
    function decide(memo, state) {
        if (!memo || memo.scanId !== state.scanId) memo = { scanId: state.scanId, dismissed: false };
        if (memo.dismissed || state.status === "blocked") return { memo, view: { visible: false } };

        return { memo, view: { visible: true, score: state.score, tone: toneFor(state.score), analyzing: !state.done } };
    }

    /** The user tapped Hide: the bubble stays hidden until the next page. */
    function dismissed(memo) {
        return memo ? { ...memo, dismissed: true } : memo;
    }

    /** Card text: the heaviest signals, Protected wording for parents (DT-04), deduped. */
    function reasonTexts(signals, { simple, lang }) {
        const texts = [...(signals ?? [])]
            .sort((a, b) => b.weight - a.weight)
            .map((s) => (simple ? s.labelSimple : s.label)?.[lang])
            .filter(Boolean);
        return [...new Set(texts)].slice(0, MAX_REASONS);
    }

    /**
     * Where a dropped bubble rests: snapped to the nearer side edge, kept inside the safe area.
     * @param {{x, y}} center  where the finger let go, px
     * @param {{width, height, top, bottom}} area  viewport size + safe-area insets, px
     * @returns {{ side: "left"|"right", y: number }}  y = centre height as a share of the viewport
     */
    function snap(center, area) {
        const side = center.x < area.width / 2 ? "left" : "right";
        return { side, y: clampY(center.y, area) / area.height };
    }

    /** Top-left pixel of the bubble for a stored position. */
    function place(pos, area) {
        const x = pos.side === "left" ? MARGIN : area.width - SIZE - MARGIN;
        const y = clampY(pos.y * area.height, area) - SIZE / 2;
        return { x, y };
    }

    function clampY(centerY, area) {
        const min = area.top + MARGIN + SIZE / 2;
        const max = area.height - area.bottom - MARGIN - SIZE / 2;
        return Math.min(Math.max(centerY, min), Math.max(min, max));
    }

    /** Stored position from storage.local, or the default when missing or malformed. */
    function validPos(pos) {
        const ok = pos && (pos.side === "left" || pos.side === "right") && pos.y >= 0 && pos.y <= 1;
        return ok ? { side: pos.side, y: pos.y } : { ...DEFAULT_POS };
    }

    globalThis.ShooPill = { toneFor, decide, dismissed, reasonTexts, snap, place, validPos, SIZE, MARGIN };

    // ---- View (browser only) -------------------------------------------------------------

    if (typeof document === "undefined" || typeof browser === "undefined") return;

    const POS_KEY = "shoo.bubble.pos";
    const DRAG_SLOP = 6; // px a finger may move before a tap becomes a drag
    const t = (key, sub) => browser.i18n.getMessage(key, sub) || key;
    const lang = (browser.i18n.getUILanguage?.() || "en").toLowerCase().startsWith("id") ? "id" : "en";
    const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

    const CSS = `
        :host { all: initial; }
        .bubble {
            position: fixed; top: 0; left: 0; z-index: 2147483647;
            box-sizing: border-box; width: ${SIZE}px; height: ${SIZE}px; padding: 0;
            display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 1px;
            border: 3px solid var(--tone); border-radius: 50%; background: #000; color: #fff;
            box-shadow: 0 4px 14px rgba(0,0,0,.35); cursor: grab; touch-action: none; user-select: none;
            -webkit-user-select: none; -webkit-tap-highlight-color: transparent;
            font: 700 15px/1 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            transition: opacity .3s ease, transform .3s cubic-bezier(.2,.8,.2,1), border-color .3s ease;
        }
        .bubble[data-tone="safe"] { --tone: #30d158; }
        .bubble[data-tone="warning"] { --tone: #ffb340; }
        .bubble[data-tone="danger"] { --tone: #ff453a; }
        .bubble.dragging { transition: opacity .3s ease; cursor: grabbing; }
        .bubble.placing { transition: opacity .3s ease; }
        .bubble.out { opacity: 0; pointer-events: none; }
        .bubble[data-analyzing] { animation: ring 1.2s ease-in-out infinite; }
        @keyframes ring { 50% { box-shadow: 0 4px 14px rgba(0,0,0,.35), 0 0 0 5px color-mix(in srgb, var(--tone) 35%, transparent); } }
        .logo { width: 18px; height: 18px; border-radius: 50%; object-fit: cover; pointer-events: none; }
        .score { font-variant-numeric: tabular-nums; color: var(--tone); letter-spacing: -.02em; }

        .card {
            position: fixed; z-index: 2147483647; box-sizing: border-box; width: min(280px, calc(100vw - 24px));
            padding: 14px; border-radius: 16px; background: #fff; color: #1c1c1e;
            box-shadow: 0 10px 30px rgba(0,0,0,.28);
            font: 15px/1.35 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            animation: pop .18s ease-out;
        }
        .card[hidden] { display: none; }
        .card[data-tone="safe"] { --accent: #1f9d45; --chip: #e3f7e8; }
        .card[data-tone="warning"] { --accent: #b86e00; --chip: #fff4e0; }
        .card[data-tone="danger"] { --accent: #c8262c; --chip: #ffe8e8; }
        @keyframes pop { from { opacity: 0; transform: scale(.96); } }
        .top { display: flex; align-items: center; gap: 8px; }
        .chip { padding: 3px 10px; border-radius: 999px; background: var(--chip); color: var(--accent);
                font-weight: 700; font-size: 12px; text-transform: uppercase; letter-spacing: .03em; }
        .big { margin-left: auto; font-weight: 800; font-size: 22px; color: var(--accent); font-variant-numeric: tabular-nums; }
        ul { margin: 10px 0 0; padding: 0 0 0 18px; }
        li { margin: 0 0 4px; }
        .note { margin: 10px 0 0; color: #636366; }
        .actions { display: flex; gap: 8px; margin-top: 12px; }
        .actions > * { flex: 1; box-sizing: border-box; min-height: 40px; padding: 10px; border: 0; border-radius: 10px;
                       font: inherit; font-weight: 600; line-height: 1.2; text-align: center; text-decoration: none; cursor: pointer; }
        .hide { background: #f2f2f7; color: #3a3a3c; }
        .probe { position: fixed; visibility: hidden; pointer-events: none;
                 padding: env(safe-area-inset-top, 0px) 0 env(safe-area-inset-bottom, 0px); }
        @media (prefers-reduced-motion: reduce) { .bubble, .card { transition: none; animation: none; } }
    `;

    const dom = globalThis.ShooDom; // the page can shadow document properties and hide our host (dom.js)
    let host = null;
    let release = () => {}; // stops guarding host
    let refs = null;
    let shown = 0; // the number on screen, counts toward the real score
    let tween = null;
    let pos = { ...DEFAULT_POS };
    let simple = false; // Protected → plain reason wording
    let last = null; // newest pipeline state + view, for the card

    browser.storage?.local
        .get(POS_KEY)
        .then((stored) => {
            pos = validPos(stored?.[POS_KEY]);
            if (refs && !refs.bubble.classList.contains("dragging")) jumpTo(place(pos, area()));
        })
        .catch(() => {});
    browser.runtime
        .sendMessage({ type: "profile" })
        .then((p) => {
            simple = Boolean(p?.onboarded && p.mode === "protected");
            if (refs && !refs.card.hidden) fillCard();
        })
        .catch(() => {});

    function el(tag, className, text) {
        const node = dom.create(document, tag);
        if (className) node.className = className;
        if (text != null) node.textContent = text;
        return node;
    }

    function area() {
        const probe = refs?.probe;
        const style = probe ? getComputedStyle(probe) : null;
        return {
            width: dom.root(document).clientWidth || innerWidth,
            height: innerHeight,
            top: parseFloat(style?.paddingTop) || 0,
            bottom: parseFloat(style?.paddingBottom) || 0,
        };
    }

    function mount() {
        if (host?.isConnected) return;
        host = dom.create(document, "shoo-live-score");
        const root = host.attachShadow({ mode: "closed" });
        const style = el("style");
        style.textContent = CSS;

        const bubble = el("button", "bubble out");
        bubble.type = "button";
        bubble.setAttribute("aria-haspopup", "dialog");
        bubble.setAttribute("aria-expanded", "false");
        bubble.innerHTML = `<img class="logo" alt=""><span class="score"></span>`;
        bubble.querySelector(".logo").src = browser.runtime.getURL("images/icon-96.png");

        const card = el("div", "card");
        card.hidden = true;
        card.setAttribute("role", "dialog");
        const top = el("div", "top");
        const chip = el("span", "chip");
        const big = el("span", "big");
        top.append(chip, big);
        const list = el("ul");
        const note = el("p", "note");
        const actions = el("div", "actions");
        const hideButton = el("button", "hide", t("pill_hide"));
        hideButton.type = "button";
        hideButton.addEventListener("click", () => {
            memo = dismissed(memo);
            hide();
        });
        actions.append(hideButton);
        card.append(top, list, note, actions);

        const probe = el("div", "probe");
        const live = el("span"); // screen readers hear score changes without opening the card
        live.setAttribute("role", "status");
        live.setAttribute("aria-live", "polite");
        Object.assign(live.style, { position: "fixed", width: "1px", height: "1px", overflow: "hidden", clip: "rect(0 0 0 0)" });
        root.append(style, probe, live, bubble, card);

        refs = { bubble, score: bubble.querySelector(".score"), card, chip, big, list, note, probe, live };
        release = dom.guard(host, dom.root(document)); // appends it, and puts it back if the page hides it
        shown = 0;
        jumpTo(place(pos, area()));
        drag(bubble);
        requestAnimationFrame(() => refs?.bubble.classList.remove("out"));
    }

    function moveTo({ x, y }) {
        if (refs) refs.bubble.style.transform = `translate3d(${x}px, ${y}px, 0)`;
    }

    /** Moves without the slide animation, so a new or restored bubble doesn't glide in from 0,0. */
    function jumpTo(xy) {
        const bubble = refs?.bubble;
        if (!bubble) return;
        bubble.classList.add("placing");
        moveTo(xy);
        requestAnimationFrame(() => bubble.classList.remove("placing"));
    }

    /** Pointer drag with tap detection. A drop snaps to the nearer edge and is remembered. */
    function drag(bubble) {
        let start = null;
        bubble.addEventListener("pointerdown", (e) => {
            if (e.button !== 0) return;
            const from = place(pos, area());
            start = { id: e.pointerId, px: e.clientX, py: e.clientY, cx: e.clientX, cy: e.clientY, x: from.x, y: from.y, moved: false };
            bubble.setPointerCapture(e.pointerId);
        });
        bubble.addEventListener("pointermove", (e) => {
            if (!start || e.pointerId !== start.id) return;
            const dx = e.clientX - start.px;
            const dy = e.clientY - start.py;
            if (!start.moved && Math.hypot(dx, dy) < DRAG_SLOP) return;
            if (!start.moved) {
                start.moved = true;
                bubble.classList.add("dragging");
                closeCard();
            }
            start.cx = e.clientX;
            start.cy = e.clientY;
            moveTo({ x: start.x + dx, y: start.y + dy });
        });
        const end = (e) => {
            if (!start || e.pointerId !== start.id) return;
            const { moved, cx, cy } = start;
            start = null;
            bubble.classList.remove("dragging");
            if (!moved) return e.type === "pointerup" && toggleCard();
            const a = area();
            // pointercancel may report 0,0, so drop where the finger was last seen.
            pos = snap({ x: cx, y: cy }, a);
            moveTo(place(pos, a));
            browser.storage?.local.set({ [POS_KEY]: pos }).catch(() => {});
        };
        bubble.addEventListener("pointerup", end);
        bubble.addEventListener("pointercancel", end);
        // Keyboard / VoiceOver activation arrives as a click with no pointer sequence.
        bubble.addEventListener("click", (e) => {
            if (e.detail === 0) toggleCard();
        });
    }

    function toggleCard() {
        if (!refs) return;
        if (refs.card.hidden) openCard();
        else closeCard();
    }

    function openCard() {
        refs.card.hidden = false;
        refs.bubble.setAttribute("aria-expanded", "true");
        fillCard();
        positionCard();
        dom.on(document, "pointerdown", outside, true);
        dom.on(document, "keydown", escape, true);
    }

    function closeCard() {
        if (!refs || refs.card.hidden) return;
        refs.card.hidden = true;
        refs.bubble.setAttribute("aria-expanded", "false");
        dom.off(document, "pointerdown", outside, true);
        dom.off(document, "keydown", escape, true);
    }

    // isTrusted: only the user's own taps and keys close the card, never events the page dispatches.
    function outside(e) {
        if (e.isTrusted && !e.composedPath().includes(host)) closeCard();
    }

    function escape(e) {
        if (e.isTrusted && e.key === "Escape") closeCard();
    }

    function fillCard() {
        if (!refs || !last) return;
        const { state, view } = last;
        const { card, chip, big, list, note } = refs;
        card.dataset.tone = view.tone;
        chip.textContent = t(view.analyzing ? "pill_status_checking" : `pill_status_${view.tone}`);
        big.textContent = `${view.score}%`;
        card.setAttribute("aria-label", `${chip.textContent} ${big.textContent}`);

        const reasons = reasonTexts(state.signals, { simple, lang });
        list.replaceChildren(...reasons.map((text) => el("li", null, text)));
        list.hidden = reasons.length === 0;
        note.textContent = reasons.length ? "" : t(view.analyzing ? "pill_still_checking" : "pill_no_reasons");
        note.hidden = reasons.length > 0;
    }

    /** Card sits beside the bubble's edge, above it when there's room, otherwise below. */
    function positionCard() {
        const { card } = refs;
        const a = area();
        const b = place(pos, a);
        const gap = 8;
        const height = card.offsetHeight;
        const above = b.y - gap - height;
        const y = above >= a.top + MARGIN ? above : Math.min(b.y + SIZE + gap, a.height - a.bottom - MARGIN - height);
        card.style.top = `${Math.max(a.top + MARGIN, y)}px`;
        card.style.left = pos.side === "left" ? `${MARGIN}px` : "auto";
        card.style.right = pos.side === "right" ? `${MARGIN}px` : "auto";
    }

    /** Counts the number on screen up (or down) to the new score so each layer visibly moves it. */
    function countTo(target) {
        cancelAnimationFrame(tween);
        const from = shown;
        if (reduceMotion || from === target) return paint(target);
        const begin = performance.now();
        const duration = 500;
        const step = (now) => {
            const p = Math.min(1, (now - begin) / duration);
            paint(Math.round(from + (target - from) * (1 - (1 - p) ** 3)));
            if (p < 1) tween = requestAnimationFrame(step);
        };
        tween = requestAnimationFrame(step);
    }

    function paint(value) {
        shown = value;
        if (refs) refs.score.textContent = `${value}%`;
    }

    function show(state, view) {
        last = { state, view };
        mount();
        const { bubble, live, card } = refs;
        bubble.classList.remove("out");
        bubble.dataset.tone = view.tone;
        bubble.toggleAttribute("data-analyzing", view.analyzing && !reduceMotion);
        const label = view.analyzing ? t("pill_checking", [String(view.score)]) : t("pill_score", [String(view.score)]);
        bubble.setAttribute("aria-label", `${label}. ${t("pill_open")}`);
        live.textContent = label;
        countTo(view.score);
        if (!card.hidden) {
            fillCard();
            positionCard();
        }
    }

    function hide() {
        cancelAnimationFrame(tween);
        if (!refs) return;
        closeCard();
        const gone = host;
        release();
        refs.bubble.classList.add("out");
        host = null;
        refs = null;
        setTimeout(() => gone.remove(), reduceMotion ? 0 : 300);
    }

    addEventListener("resize", () => {
        if (!refs) return;
        moveTo(place(pos, area()));
        if (!refs.card.hidden) positionCard();
    });

    let memo = null;
    globalThis.ShooPipeline.subscribe((state) => {
        const result = decide(memo, state);
        memo = result.memo;
        if (result.view.visible) show(state, result.view);
        else hide();
    });
})();
