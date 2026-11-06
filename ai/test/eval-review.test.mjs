import { test } from "node:test";
import assert from "node:assert/strict";
import { evalReview, dummyTruth } from "../eval/dataset/eval-review.mjs";

// One ai_dataset row per Guardian decision: domain-level fields repeat per family, so the eval must count a domain once.
const row = (domain, over) => ({ domain, final_label: "scam_weak", families_not_safe: 3, domain_avg_score: 80, review_suggestion: "approve", review_result: "scam", shared_host: false, ...over });

const FOUR = [
    row("tp.test", {}), // scam, rule approves, LLM approves
    row("tp.test", {}), // second family row of the same domain
    row("fp.test", { final_label: "safe" }), // safe, both approve
    row("fn.test", { families_not_safe: 1, review_suggestion: "none", review_result: "unsure" }), // scam, neither approves
    row("tn.test", { final_label: "safe", families_not_safe: 0, domain_avg_score: 30, review_suggestion: "none", review_result: "unsure" }),
];

test("four known domains (TP, FP, FN, TN) give precision 0.5 and recall 0.5 for the rule and for the LLM", () => {
    const r = evalReview(FOUR);
    assert.equal(r.n, 4);
    for (const side of [r.rule, r.llm]) {
        assert.deepEqual([side.tp, side.fp, side.fn, side.tn], [1, 1, 1, 1]);
        assert.equal(side.precision, 0.5);
        assert.equal(side.recall, 0.5);
    }
});

test("shared hosts, unlabelled domains and domains without a review are left out", () => {
    const r = evalReview([
        ...FOUR,
        row("shared.test", { shared_host: true }),
        row("nolabel.test", { final_label: null }),
        row("noreview.test", { review_result: null, review_suggestion: null }),
    ]);
    assert.equal(r.n, 4);
});

test("the rule needs both 2+ not_safe families and an average score of 50+", () => {
    const base = { review_suggestion: "none", review_result: "unsure" };
    const r = evalReview([
        row("a.test", { ...base, families_not_safe: 2, domain_avg_score: 50 }), // approve -> TP
        row("b.test", { ...base, families_not_safe: 2, domain_avg_score: 49 }), // no -> FN
        row("c.test", { ...base, families_not_safe: 1, domain_avg_score: 99 }), // no -> FN
    ]);
    assert.deepEqual([r.rule.tp, r.rule.fn], [1, 2]);
    assert.equal(r.llm.precision, null); // nothing predicted positive: undefined, not 0
    assert.equal(r.llm.recall, 0);
});

test("dummyTruth reads the dummy domain name, so a legit-* domain the votes labelled scam_weak still counts as not scam", () => {
    const rows = [
        row("scam-01.shoo-dummy.test", {}), // scam, rule + LLM approve -> TP
        row("scam-07.shoo-dummy.test", { families_not_safe: 2, domain_avg_score: 40, review_suggestion: "none", review_result: "unsure" }), // scam, neither approves -> FN
        // 2 N + 2 Y: the votes make it scam_weak and the rule approves it; the LLM says unsure
        row("legit-05.shoo-dummy.test", { families_not_safe: 2, domain_avg_score: 55, review_suggestion: "none", review_result: "unsure" }),
        row("maybe-01.shoo-dummy.test", {}), // neither scam-* nor legit-*: left out
    ];
    assert.equal(dummyTruth(rows[2]), false);
    assert.equal(dummyTruth(rows[3]), null);
    const r = evalReview(rows, { truth: dummyTruth });
    assert.equal(r.n, 3);
    assert.deepEqual([r.rule.tp, r.rule.fp, r.rule.fn, r.rule.tn], [1, 1, 1, 0]); // the rule approves legit-05: a false approve
    assert.deepEqual([r.llm.tp, r.llm.fp, r.llm.fn, r.llm.tn], [1, 0, 1, 1]); // the LLM holds it back: true negative
    // with the default (final_label) truth every row here is scam_weak: legit-05 (and maybe-01) count as scam, so the rule's
    // false approve of legit-05 shows up as a true positive and it has no false positives at all
    const byLabel = evalReview(rows).rule;
    assert.deepEqual([byLabel.tp, byLabel.fp], [3, 0]);
});
