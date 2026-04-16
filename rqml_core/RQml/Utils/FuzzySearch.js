.pragma library

function normalizeQuery(query) {
    return (query || "").trim().toLowerCase();
}

function splitTerms(query) {
    const normalized = normalizeQuery(query);
    if (!normalized)
        return [];
    return normalized.split(/\s+/).filter(term => term.length > 0);
}

function singleTermScore(candidate, pattern) {
    if (!pattern)
        return 0;

    const s = (candidate || "").toLowerCase();
    const p = pattern.toLowerCase();
    let score = 0;
    let si = 0;
    let pi = 0;
    let consecutive = 0;
    while (si < s.length && pi < p.length) {
        if (s[si] === p[pi]) {
            consecutive++;
            score += consecutive * consecutive;
            if (si === 0 || "/_- ".includes(s[si - 1]))
                score += 5;
            pi++;
        } else {
            consecutive = 0;
        }
        si++;
    }
    return pi === p.length ? score : -1;
}

function scoreFields(fields, query) {
    const terms = splitTerms(query);
    if (terms.length === 0)
        return 0;

    const searchFields = Array.isArray(fields) ? fields : [fields];
    let totalScore = 0;
    for (const term of terms) {
        let bestTermScore = -1;
        for (const field of searchFields) {
            const score = singleTermScore(field, term);
            if (score > bestTermScore)
                bestTermScore = score;
        }
        if (bestTermScore < 0)
            return -1;
        totalScore += bestTermScore;
    }
    return totalScore;
}

function score(candidate, query) {
    return scoreFields(candidate, query);
}
