# Web Search API Comparison for Moltis AI

**Date**: 2026-02-16
**Status**: Complete

---

## Comparison Table

| Tool | Free Tier | Price/1000 calls | Rate Limit | Quality | Notes |
|------|-----------|------------------|------------|---------|-------|
| **Tavily** | 1,000/month | $5-10 | 1K/month free | ⭐⭐⭐⭐⭐ | **AI-optimized for LLMs** |
| **Serper.dev** | 2,500 (one-time) | $2.50 | 100/min | ⭐⭐⭐⭐ | Best value for Google results |
| **Brave Search** | 2,000/month | $5.00 | Unspecified | ⭐⭐⭐⭐⭐ | Privacy-focused, independent |
| **DuckDuckGo** | **COMPLETELY FREE** | **$0** | None | ⭐⭐⭐ | **No API key needed** |
| **Wikipedia API** | **COMPLETELY FREE** | **$0** | None | ⭐⭐⭐ | **No API key needed** |
| **Bing Web Search** | 1,000/month | $7.00 | 3/sec | ⭐⭐⭐⭐ | Azure account required |
| **SerpAPI** | 100 searches | $50.00 | 5/min free | ⭐⭐⭐⭐ | Expensive, scraping-based |
| **Perplexity** | Limited | ~$10-20 | Unspecified | ⭐⭐⭐⭐⭐ | AI-powered, most expensive |

---

## Top 3 Recommendations

### 🥇 #1: Tavily (FREE Tier Available)

**Best for**: Production AI assistants requiring quality results

**Why:**
- **1,000 free calls/month** - sufficient for testing and light production
- **Designed specifically for LLMs** - optimized for AI consumption
- **Clean, structured responses** - perfect for RAG applications
- **Competitive pricing** at scale

**Cost Estimate:**
- 1,000 searches: **FREE**
- 10,000 searches: ~$50/month
- 100,000 searches: ~$500/month

---

### 🥈 #2: Serper.dev (Best Budget Option)

**Best for**: Budget-conscious projects needing Google results

**Why:**
- **2,500 free calls** (one-time) for testing
- **$2.50/1000 calls** - lowest price among Google APIs
- **Simple REST API** - very easy integration
- **Google-quality results**

**Cost Estimate:**
- 2,500 searches: **FREE** (one-time)
- 10,000 searches: **$25/month**
- 100,000 searches: **$250/month**

---

### 🥉 #3: Brave Search (Privacy + Free Tier)

**Best for**: Privacy-focused applications

**Why:**
- **2,000 free calls/month** (recurring)
- **$5/1000 calls** - competitive pricing
- **Independent search index** - not dependent on Google
- **Privacy-focused** - no tracking

**Cost Estimate:**
- 2,000 searches: **FREE**
- 10,000 searches: **$40/month**
- 100,000 searches: **$400/month**

---

## Completely FREE Options (No API Key)

### DuckDuckGo Instant Answer API
```typescript
const response = await fetch(
  `https://api.duckduckgo.com/?q=${query}&format=json`
);
```
- **100% FREE**, no API key
- Best for: Quick facts, definitions
- Limitation: Instant answers only (not full search)

### Wikipedia API
```typescript
const response = await fetch(
  `https://en.wikipedia.org/api/rest_v1/page/summary/${query}`
);
```
- **100% FREE**, no API key
- Best for: Encyclopedic information, definitions

---

## Cost Comparison Table (Monthly)

| Monthly Searches | Tavily | Serper.dev | Brave | Bing |
|------------------|--------|------------|-------|------|
| 1,000 | **FREE** | **FREE** | **FREE** | **FREE** |
| 5,000 | **FREE** | $12.50 | $15 | $28 |
| 10,000 | ~$50 | **$25** | $40 | $70 |
| 50,000 | ~$250 | **$125** | $200 | $350 |
| 100,000 | ~$500 | **$250** | $400 | $700 |

*(Bold = lowest price)*

---

## Recommended Hybrid Strategy for Moltis

```typescript
// Smart search router to minimize costs
async function webSearch(query: string) {
  // 1. Try FREE options first
  if (isSimpleFactQuery(query)) {
    return await duckDuckGoSearch(query);
  }

  if (isEncyclopedicQuery(query)) {
    return await wikipediaSearch(query);
  }

  // 2. Use Tavily free tier for complex queries
  if (withinTavilyFreeTier()) {
    return await tavilySearch(query);
  }

  // 3. Fallback to Serper.dev for budget efficiency
  return await serperSearch(query);
}
```

---

## Implementation Roadmap

1. **Phase 1 (Zero Cost)**: Implement DuckDuckGo + Wikipedia
2. **Phase 2 (Testing)**: Get Tavily API key, test 1,000 free calls
3. **Phase 3 (Evaluation)**: Compare quality after 500 queries
4. **Phase 4 (Scale)**: Choose based on actual usage patterns

---

## API Documentation

- **Tavily**: https://tavily.com/docs/api
- **Serper.dev**: https://serper.dev/api-documentation
- **Brave Search**: https://api.search.brave.com/app/documentation
- **DuckDuckGo**: https://duckduckgo.com/api
- **Wikipedia**: https://en.wikipedia.org/api/rest_v1/
