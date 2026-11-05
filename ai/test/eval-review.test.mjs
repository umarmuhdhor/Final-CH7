import { test } from "node:test";
import assert from "node:assert/strict";
import { evalReview } from "../eval/dataset/eval-review.mjs";

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
